// SPDX-License-Identifier: GPL-3.0-or-later

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QRegularExpression>
#include <QSocketNotifier>
#include <QStringList>
#include <QTextStream>
#include <QTimer>

#include <security/pam_appl.h>

#include <cerrno>
#include <algorithm>
#include <climits>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <pwd.h>
#include <sys/file.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <syslog.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "DiagnosticLog.h"
#include "OmarchyTheme.h"

extern "C" __attribute__((used, visibility("default")))
const char omarchy_face_id_elevation_marker[] =
    "Omarchy Face ID elevation bridge 1";

namespace {
constexpr int promptChannelFd = 3;
constexpr int promptReadyTimeoutMs = 5000;
constexpr int decisionTimeoutMs = 30000;
constexpr int verificationTimeoutMs = 20000;
constexpr int successHoldMs = 700;
constexpr int fallbackHoldMs = 900;

enum class ConsentResult {
  Approved = 0,
  Declined = 10,
  Unavailable = 20,
};

bool testMode() {
  return qEnvironmentVariableIsSet(
      "OMARCHY_FACE_ID_ELEVATION_ALLOW_UNPRIVILEGED");
}

volatile sig_atomic_t coordinatorSignal = 0;

void noteCoordinatorSignal(int signal) {
  coordinatorSignal = signal;
}

struct Account {
  uid_t uid = static_cast<uid_t>(-1);
  gid_t gid = static_cast<gid_t>(-1);
  QByteArray name;
  QByteArray home;

  bool valid() const {
    return uid != static_cast<uid_t>(-1) && gid != static_cast<gid_t>(-1) &&
           !name.isEmpty() && !home.isEmpty();
  }
};

Account targetAccount() {
  if (testMode()) {
    const passwd *entry = getpwuid(getuid());
    return entry
               ? Account{entry->pw_uid, entry->pw_gid,
                         QByteArray(entry->pw_name), QByteArray(entry->pw_dir)}
               : Account{};
  }

  QString name = qEnvironmentVariable("PAM_USER").trimmed();
  if (name.isEmpty())
    return {};
  const QByteArray encoded = name.toLocal8Bit();
  const passwd *entry = getpwnam(encoded.constData());
  return entry ? Account{entry->pw_uid, entry->pw_gid,
                         QByteArray(entry->pw_name), QByteArray(entry->pw_dir)}
               : Account{};
}

bool configureTrustedHyprlandInstance(const Account &account,
                                      const QString &runtimePath,
                                      const QString &waylandDisplay) {
  const QString hyprlandRoot = runtimePath + QStringLiteral("/hypr");
  const QByteArray encodedRoot = QFile::encodeName(hyprlandRoot);
  struct stat rootInfo {};
  if (lstat(encodedRoot.constData(), &rootInfo) != 0 ||
      !S_ISDIR(rootInfo.st_mode) || rootInfo.st_uid != account.uid ||
      (rootInfo.st_mode & 0022) != 0)
    return false;

  static const QRegularExpression safeSignature(
      QStringLiteral("^[A-Za-z0-9._-]{1,200}$"));
  const QDir root(hyprlandRoot);
  const QStringList candidates = root.entryList(
      QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
  for (const QString &candidate : candidates) {
    if (!safeSignature.match(candidate).hasMatch())
      continue;

    const QString candidatePath = hyprlandRoot + QLatin1Char('/') + candidate;
    const QByteArray encodedCandidate = QFile::encodeName(candidatePath);
    struct stat candidateInfo {};
    if (lstat(encodedCandidate.constData(), &candidateInfo) != 0 ||
        !S_ISDIR(candidateInfo.st_mode) ||
        candidateInfo.st_uid != account.uid ||
        (candidateInfo.st_mode & 0022) != 0)
      continue;

    const QByteArray encodedSocket =
        QFile::encodeName(candidatePath + QStringLiteral("/.socket.sock"));
    struct stat socketInfo {};
    if (lstat(encodedSocket.constData(), &socketInfo) != 0 ||
        !S_ISSOCK(socketInfo.st_mode) || socketInfo.st_uid != account.uid ||
        (socketInfo.st_mode & 0022) != 0)
      continue;

    const QByteArray encodedLock =
        QFile::encodeName(candidatePath + QStringLiteral("/hyprland.lock"));
    const int lock = open(encodedLock.constData(), O_RDONLY | O_CLOEXEC |
                                                    O_NOFOLLOW);
    if (lock < 0)
      continue;
    struct stat lockInfo {};
    char lockContents[257] = {};
    const ssize_t length = fstat(lock, &lockInfo) == 0 &&
                                   S_ISREG(lockInfo.st_mode) &&
                                   lockInfo.st_uid == account.uid &&
                                   (lockInfo.st_mode & 0022) == 0 &&
                                   lockInfo.st_size > 0 &&
                                   lockInfo.st_size <
                                       static_cast<off_t>(sizeof(lockContents))
                               ? read(lock, lockContents,
                                      sizeof(lockContents) - 1)
                               : -1;
    close(lock);
    if (length <= 0)
      continue;

    const QStringList lines =
        QString::fromUtf8(lockContents, static_cast<qsizetype>(length))
            .split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    bool pidValid = false;
    const qint64 compositorPid = lines.value(0).toLongLong(&pidValid);
    if (!pidValid || compositorPid <= 1 ||
        lines.value(1) != waylandDisplay)
      continue;

    const QByteArray encodedProcess =
        QFile::encodeName(QStringLiteral("/proc/%1").arg(compositorPid));
    struct stat processInfo {};
    if (stat(encodedProcess.constData(), &processInfo) != 0 ||
        !S_ISDIR(processInfo.st_mode) || processInfo.st_uid != account.uid)
      continue;

    const QByteArray signature = candidate.toUtf8();
    return setenv("HYPRLAND_INSTANCE_SIGNATURE", signature.constData(), 1) ==
           0;
  }
  return false;
}

bool trustedDesktopEndpoint(const Account &account) {
  const QString testRuntime = qEnvironmentVariable(
      "OMARCHY_FACE_ID_ELEVATION_TEST_DESKTOP_RUNTIME");
  if (testMode() && testRuntime.isEmpty())
    return true;

  const QString expectedRuntime = testRuntime.isEmpty()
      ? QStringLiteral("/run/user/%1").arg(account.uid)
      : testRuntime;

  struct stat runtimeInfo{};
  const QByteArray runtimePath = QFile::encodeName(expectedRuntime);
  if (lstat(runtimePath.constData(), &runtimeInfo) != 0 ||
      !S_ISDIR(runtimeInfo.st_mode) || runtimeInfo.st_uid != account.uid ||
      (runtimeInfo.st_mode & 0077) != 0)
    return false;

  const auto trustedSocket = [&](const QString &display) {
    if (!display.startsWith(QStringLiteral("wayland-"))
        || display.contains(QLatin1Char('/'))
        || display.endsWith(QStringLiteral(".lock")))
      return false;
    const QByteArray socketPath =
        QFile::encodeName(expectedRuntime + QLatin1Char('/') + display);
    struct stat socketInfo{};
    return lstat(socketPath.constData(), &socketInfo) == 0
        && S_ISSOCK(socketInfo.st_mode) && socketInfo.st_uid == account.uid;
  };

  QString display = qEnvironmentVariable("WAYLAND_DISPLAY");
  if (!trustedSocket(display)) {
    display.clear();
    const QDir runtime(expectedRuntime);
    const QStringList candidates = runtime.entryList(
        {QStringLiteral("wayland-*")}, QDir::Files | QDir::System,
        QDir::Name);
    for (const QString &candidate : candidates) {
      if (trustedSocket(candidate)) {
        display = candidate;
        break;
      }
    }
  }
  if (display.isEmpty())
    return false;

  const QByteArray runtimeValue = QFile::encodeName(expectedRuntime);
  const QByteArray displayValue = display.toLocal8Bit();
  return setenv("XDG_RUNTIME_DIR", runtimeValue.constData(), 1) == 0 &&
         setenv("WAYLAND_DISPLAY", displayValue.constData(), 1) == 0 &&
         configureTrustedHyprlandInstance(account, expectedRuntime, display);
}

QString lockPath() {
  if (!testMode())
    return QStringLiteral("/run/omarchy-face-id-elevation.lock");
  const QString root =
      qEnvironmentVariable("OMARCHY_FACE_ID_ELEVATION_RUNTIME_DIR");
  return root.isEmpty() ? QString()
                        : root + QStringLiteral("/single-flight.lock");
}

int acquireSingleFlightLock() {
  const QString path = lockPath();
  if (path.isEmpty())
    return -1;
  const QByteArray encoded = QFile::encodeName(path);
  const int descriptor = open(encoded.constData(),
                              O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (descriptor < 0)
    return -1;

  struct stat info{};
  const uid_t expectedOwner = testMode() ? getuid() : 0;
  if (fstat(descriptor, &info) != 0 || !S_ISREG(info.st_mode) ||
      info.st_uid != expectedOwner || (info.st_mode & 0077) != 0 ||
      flock(descriptor, LOCK_EX | LOCK_NB) != 0) {
    close(descriptor);
    return -1;
  }
  return descriptor;
}

int testPhaseTimeoutMs(int productionValue, int minimum) {
  if (!testMode())
    return productionValue;
  bool valid = false;
  const int value = qEnvironmentVariableIntValue(
      "OMARCHY_FACE_ID_ELEVATION_TEST_TIMEOUT_MS", &valid);
  return valid && value >= 50 && value <= 5000
      ? std::max(value, minimum) : productionValue;
}

void closeDescriptorsFrom(int first) {
#ifdef SYS_close_range
  if (syscall(SYS_close_range, static_cast<unsigned int>(first), UINT_MAX, 0) ==
      0)
    return;
#endif
  const long maximum = sysconf(_SC_OPEN_MAX);
  const int limit =
      maximum > 0 && maximum < INT_MAX ? static_cast<int>(maximum) : 65536;
  for (int descriptor = first; descriptor < limit; ++descriptor)
    close(descriptor);
}

void closeUnrelatedDescriptors() {
  closeDescriptorsFrom(promptChannelFd + 1);
}

bool resetChildSignals() {
  sigset_t empty;
  if (sigemptyset(&empty) != 0 || sigprocmask(SIG_SETMASK, &empty, nullptr) != 0)
    return false;
  struct sigaction action {};
  action.sa_handler = SIG_DFL;
  if (sigemptyset(&action.sa_mask) != 0)
    return false;
  for (const int signal : {SIGINT, SIGTERM, SIGHUP, SIGCHLD, SIGPIPE}) {
    if (sigaction(signal, &action, nullptr) != 0)
      return false;
  }
  return true;
}

bool protectFromParentDeath(pid_t expectedParent) {
  return prctl(PR_SET_PDEATHSIG, SIGKILL) == 0 && getppid() == expectedParent &&
         expectedParent > 1;
}

bool redirectStandardDescriptors() {
  const int nullFd = open("/dev/null", O_RDWR | O_CLOEXEC);
  if (nullFd < 0)
    return false;
  bool ok = true;
  for (int descriptor = STDIN_FILENO; descriptor <= STDERR_FILENO;
       ++descriptor) {
    if (dup2(nullFd, descriptor) < 0)
      ok = false;
  }
  if (nullFd > STDERR_FILENO)
    close(nullFd);
  return ok;
}

bool dropToAccount(const Account &account) {
  if (testMode())
    return true;
  if (initgroups(account.name.constData(), account.gid) != 0 ||
      setgid(account.gid) != 0 || setuid(account.uid) != 0)
    return false;
  return getuid() == account.uid && geteuid() == account.uid &&
         getgid() == account.gid && getegid() == account.gid;
}

QByteArray selfPath() {
  QByteArray path(4096, '\0');
  const ssize_t length = readlink("/proc/self/exe", path.data(),
                                  static_cast<size_t>(path.size() - 1));
  if (length <= 0)
    return {};
  path.resize(static_cast<qsizetype>(length));
  return path;
}

void configurePromptEnvironment(const Account &account) {
  setenv("HOME", account.home.constData(), 1);
  setenv("USER", account.name.constData(), 1);
  setenv("LOGNAME", account.name.constData(), 1);
  // Automated tests set a bounded timeout and render offscreen. The opt-in
  // manual smoke test is also unprivileged, but must use the real Wayland
  // desktop so a human can inspect and operate the prompt.
  if (testMode() && qEnvironmentVariableIsSet(
                        "OMARCHY_FACE_ID_ELEVATION_TEST_TIMEOUT_MS")) {
    setenv("QT_QPA_PLATFORM", "offscreen", 1);
    setenv("QT_QUICK_BACKEND", "software", 1);
  } else {
    setenv("QT_QPA_PLATFORM", "wayland", 1);
  }
  for (const char *name : {
           "DISPLAY",
           "QML_IMPORT_PATH",
           "QML2_IMPORT_PATH",
           "QT_PLUGIN_PATH",
           "QT_IM_MODULE",
           "QT_QPA_PLATFORMTHEME",
           "QT_QPA_PLATFORM_PLUGIN_PATH",
           "QT_QUICK_CONTROLS_CONF",
           "QT_QUICK_CONTROLS_STYLE",
           "QT_STYLE_OVERRIDE",
           "QSG_RENDER_LOOP",
           "QSG_RHI_BACKEND",
           "QSG_INFO",
           "LD_AUDIT",
           "LD_LIBRARY_PATH",
           "LD_PRELOAD",
       })
    unsetenv(name);
  unsetenv("SUDO_ASKPASS");
}

class ConsentBridge final : public QObject {
  Q_OBJECT
  Q_PROPERTY(QString phase READ phase NOTIFY phaseChanged)

public:
  explicit ConsentBridge(QObject *parent = nullptr)
      : QObject(parent), m_notifier(promptChannelFd, QSocketNotifier::Read,
                                    this) {
    m_diagnostics.record(QStringLiteral("elevation.authentication"),
                         QStringLiteral("consent_prompt_opened"));
    connect(&m_notifier, &QSocketNotifier::activated, this,
            &ConsentBridge::receiveCoordinatorMessage);
  }

  QString phase() const { return m_phase; }

  void markReady() { sendMessage(QByteArrayLiteral("ready")); }

  Q_INVOKABLE void respond(const QString &response) {
    if (m_finished || m_phase != QStringLiteral("deciding"))
      return;
    const QByteArray message =
        response == QStringLiteral("approve") ? QByteArrayLiteral("approve")
        : response == QStringLiteral("deny")  ? QByteArrayLiteral("deny")
                                              : response.toUtf8();
    m_diagnostics.record(
        QStringLiteral("elevation.authentication"),
        response == QStringLiteral("approve")
            ? QStringLiteral("consent_approved")
        : response == QStringLiteral("deny")
            ? QStringLiteral("consent_declined")
            : QStringLiteral("consent_response_invalid"),
        response == QStringLiteral("approve") ||
                response == QStringLiteral("deny")
            ? DiagnosticLog::Level::Info
            : DiagnosticLog::Level::Warning);
    if (!message.isEmpty())
      sendMessage(message);
  }

  Q_INVOKABLE void dismiss() {
    if (m_finished)
      return;
    m_diagnostics.record(QStringLiteral("elevation.authentication"),
                         QStringLiteral("consent_dismissed"),
                         DiagnosticLog::Level::Info);
    m_finished = true;
    QCoreApplication::quit();
  }

  Q_INVOKABLE void cancel() {
    if (m_finished)
      return;
    m_diagnostics.record(QStringLiteral("elevation.authentication"),
                         QStringLiteral("consent_cancelled"),
                         DiagnosticLog::Level::Info);
    sendMessage(QByteArrayLiteral("cancel"));
  }

signals:
  void phaseChanged();

private:
  void sendMessage(const QByteArray &message) {
    (void)send(promptChannelFd, message.constData(),
               static_cast<size_t>(message.size()), MSG_NOSIGNAL);
  }

  void setPhase(const QString &phase, const QString &event,
                DiagnosticLog::Level level = DiagnosticLog::Level::Info) {
    if (m_finished || phase == m_phase)
      return;
    m_phase = phase;
    m_diagnostics.record(QStringLiteral("elevation.authentication"), event,
                         level);
    emit phaseChanged();
  }

  void receiveCoordinatorMessage() {
    char message[17] = {};
    const ssize_t length = recv(promptChannelFd, message, sizeof(message) - 1,
                                MSG_DONTWAIT);
    if (length <= 0) {
      if (length == 0 || (errno != EAGAIN && errno != EINTR)) {
        m_finished = true;
        QCoreApplication::quit();
      }
      return;
    }
    const QByteArray token(message, static_cast<qsizetype>(length));
    if (token == QByteArrayLiteral("checking")) {
      setPhase(QStringLiteral("checking"),
               QStringLiteral("face_verification_started"));
    } else if (token == QByteArrayLiteral("success")) {
      setPhase(QStringLiteral("success"),
               QStringLiteral("face_verification_succeeded"));
    } else if (token == QByteArrayLiteral("fallback")) {
      setPhase(QStringLiteral("fallback"),
               QStringLiteral("face_verification_unavailable"),
               DiagnosticLog::Level::Warning);
    } else {
      m_finished = true;
      QCoreApplication::quit();
    }
  }

  bool m_finished = false;
  QString m_phase = QStringLiteral("deciding");
  QSocketNotifier m_notifier;
  DiagnosticLog m_diagnostics;
};

struct HyprlandWindow {
  QString address;
  bool floating = false;

  bool valid() const {
    static const QRegularExpression addressPattern(
        QStringLiteral("^0x[0-9a-f]+$"));
    return addressPattern.match(address).hasMatch();
  }
};

QString hyprctlPath() {
  if (testMode()) {
    const QString testPath = qEnvironmentVariable(
        "OMARCHY_FACE_ID_ELEVATION_TEST_HYPRCTL");
    if (!testPath.isEmpty())
      return testPath;
    // Headless automated tests do not have a compositor. The opt-in manual
    // smoke test omits the test timeout and should exercise real placement.
    if (qEnvironmentVariableIsSet(
            "OMARCHY_FACE_ID_ELEVATION_TEST_TIMEOUT_MS"))
      return {};
  }
  return QStringLiteral("/usr/bin/hyprctl");
}

bool runHyprctl(const QString &path, const QStringList &arguments,
                QByteArray *standardOutput = nullptr) {
  const QFileInfo executable(path);
  if (!executable.isAbsolute() || !executable.isFile() ||
      !executable.isExecutable())
    return false;

  QProcess process;
  QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
  environment.insert(QStringLiteral(
                         "OMARCHY_FACE_ID_ELEVATION_PROMPT_PID"),
                     QString::number(getpid()));
  process.setProcessEnvironment(environment);
  process.setProgram(path);
  process.setArguments(arguments);
  process.start();
  const int deadlineMs = testMode() ? -1 : 500;
  if (!process.waitForStarted(deadlineMs)
      || !process.waitForFinished(deadlineMs)) {
    process.kill();
    process.waitForFinished();
    return false;
  }
  if (standardOutput)
    *standardOutput = process.readAllStandardOutput();
  return process.exitStatus() == QProcess::NormalExit &&
         process.exitCode() == 0;
}

HyprlandWindow ownHyprlandWindow(const QString &path) {
  QByteArray output;
  if (!runHyprctl(path, {QStringLiteral("clients"), QStringLiteral("-j")},
                   &output) ||
      output.size() > 1024 * 1024)
    return {};

  QJsonParseError parseError;
  const QJsonDocument document = QJsonDocument::fromJson(output, &parseError);
  if (parseError.error != QJsonParseError::NoError || !document.isArray())
    return {};

  for (const QJsonValue &value : document.array()) {
    const QJsonObject window = value.toObject();
    if (window.value(QStringLiteral("pid")).toInteger() != getpid() ||
        window.value(QStringLiteral("class")).toString() !=
            QStringLiteral("io.omarchy.FaceId.Elevation"))
      continue;
    const HyprlandWindow result{
        window.value(QStringLiteral("address")).toString(),
        window.value(QStringLiteral("floating")).toBool()};
    return result.valid() ? result : HyprlandWindow{};
  }
  return {};
}

bool applyOverlayPlacement(const QString &path,
                           const HyprlandWindow &window) {
  const QString selector = QStringLiteral("address:") + window.address;
  QStringList commands;
  if (!window.floating) {
    commands.append(QStringLiteral(
                        "dispatch hl.dsp.window.float({ window = \"%1\", "
                        "action = \"toggle\" })")
                        .arg(selector));
  }
  commands.append(
      QStringLiteral(
          "dispatch hl.dsp.window.resize({ window = \"%1\", x = 560, y = "
          "500 })")
          .arg(selector));
  commands.append(
      QStringLiteral("dispatch hl.dsp.window.center({ window = \"%1\" })")
          .arg(selector));
  commands.append(
      QStringLiteral(
          "dispatch hl.dsp.window.alter_zorder({ window = \"%1\", mode = "
          "\"top\" })")
          .arg(selector));
  return runHyprctl(path,
                    {QStringLiteral("--batch"),
                     commands.join(QStringLiteral("; "))});
}

bool prepareOverlayRule(const QString &path) {
  return runHyprctl(
      path,
      {QStringLiteral("eval"),
       QStringLiteral(
           "if _G.omarchy_face_id_elevation_rule == nil then "
           "_G.omarchy_face_id_elevation_rule = hl.window_rule({ name = "
           "\"omarchy-face-id-elevation\", match = { class = "
           "\"io.omarchy.FaceId.Elevation\" }, float = true, center = true, "
           "size = { 560, 500 } }) else "
           "_G.omarchy_face_id_elevation_rule:set_enabled(true) end")});
}

void scheduleOverlayPlacement(const QString &path, int attemptsRemaining = 10) {
  if (path.isEmpty())
    return;
  const HyprlandWindow window = ownHyprlandWindow(path);
  if (window.valid()) {
    DiagnosticLog diagnostics;
    diagnostics.record(
        QStringLiteral("elevation.presentation"),
        applyOverlayPlacement(path, window)
            ? QStringLiteral("overlay_placement_applied")
            : QStringLiteral("overlay_placement_unavailable"),
        DiagnosticLog::Level::Info);
    return;
  }
  if (attemptsRemaining <= 1) {
    DiagnosticLog diagnostics;
    diagnostics.record(QStringLiteral("elevation.presentation"),
                       QStringLiteral("overlay_placement_unavailable"),
                       DiagnosticLog::Level::Info);
    return;
  }
  QTimer::singleShot(30, QCoreApplication::instance(),
                     [path, attemptsRemaining] {
                       scheduleOverlayPlacement(path, attemptsRemaining - 1);
                     });
}

int runPrompt(int argc, char **argv) {
  if (prctl(PR_SET_DUMPABLE, 0) != 0)
    return 1;

  QGuiApplication app(argc, argv);
  QCoreApplication::setApplicationName(QStringLiteral("Omarchy Face ID"));
  QGuiApplication::setDesktopFileName(
      QStringLiteral("io.omarchy.FaceId.Elevation"));
  ConsentBridge bridge;
  OmarchyTheme theme;
  QQmlApplicationEngine engine;
  engine.rootContext()->setContextProperty(QStringLiteral("consentBridge"),
                                           &bridge);
  engine.rootContext()->setContextProperty(QStringLiteral("theme"), &theme);
  const QString compositorCommand = hyprctlPath();
  if (!compositorCommand.isEmpty() &&
      !prepareOverlayRule(compositorCommand)) {
    DiagnosticLog diagnostics;
    diagnostics.record(QStringLiteral("elevation.presentation"),
                       QStringLiteral("overlay_rule_unavailable"),
                       DiagnosticLog::Level::Warning);
    return 1;
  }
  engine.load(QUrl(QStringLiteral("qrc:/elevation/ConsentPrompt.qml")));
  if (engine.rootObjects().isEmpty()) {
    DiagnosticLog diagnostics;
    diagnostics.record(QStringLiteral("elevation.authentication"),
                       QStringLiteral("consent_prompt_unavailable"),
                       DiagnosticLog::Level::Warning);
    return 1;
  }
  const QString testBehavior =
      testMode() ? qEnvironmentVariable(
                       "OMARCHY_FACE_ID_ELEVATION_TEST_RESPONSE")
                 : QString();
  if (testBehavior != QStringLiteral("no-ready"))
    bridge.markReady();

  if (testMode() && qEnvironmentVariableIsSet(
                        "OMARCHY_FACE_ID_ELEVATION_TEST_HYPRCTL")) {
    scheduleOverlayPlacement(compositorCommand);
  } else {
    QTimer::singleShot(0, &app, [compositorCommand] {
      scheduleOverlayPlacement(compositorCommand);
    });
  }

  if (testMode() && qEnvironmentVariableIsSet(
                        "OMARCHY_FACE_ID_ELEVATION_TEST_RESPONSE")) {
    const QString behavior = testBehavior;
    QTimer::singleShot(0, &app, [&bridge, behavior] {
      if (behavior == QStringLiteral("hang") ||
          behavior == QStringLiteral("no-ready"))
        return;
      if (behavior == QStringLiteral("crash")) {
        raise(SIGKILL);
        return;
      }
      if (behavior == QStringLiteral("close")) {
        bridge.dismiss();
        return;
      }
      if (behavior == QStringLiteral("require-desktop")) {
        const QString expectedRuntime = qEnvironmentVariable(
            "OMARCHY_FACE_ID_ELEVATION_TEST_DESKTOP_RUNTIME");
        const QString expectedDisplay = qEnvironmentVariable(
            "OMARCHY_FACE_ID_ELEVATION_TEST_DESKTOP_DISPLAY");
        bridge.respond(qEnvironmentVariable("XDG_RUNTIME_DIR") == expectedRuntime
                               && qEnvironmentVariable("WAYLAND_DISPLAY")
                                      == expectedDisplay
                           ? QStringLiteral("approve")
                           : QStringLiteral("malformed"));
        return;
      }
      if (behavior == QStringLiteral("cancel-checking")) {
        bridge.respond(QStringLiteral("approve"));
        QTimer::singleShot(50, &bridge, [&bridge] { bridge.cancel(); });
        return;
      }
      bridge.respond(behavior == QStringLiteral("approve")
                         ? QStringLiteral("approve")
                     : behavior == QStringLiteral("deny")
                         ? QStringLiteral("deny")
                         : QStringLiteral("malformed"));
    });
  }
  return app.exec();
}

long long monotonicMilliseconds() {
  struct timespec now {};
  return clock_gettime(CLOCK_MONOTONIC, &now) == 0
             ? static_cast<long long>(now.tv_sec) * 1000 +
                   static_cast<long long>(now.tv_nsec / 1000000)
             : 0;
}

bool sendToken(int channel, const char *token) {
  const size_t length = std::strlen(token);
  return length <= 16 &&
         send(channel, token, length, MSG_NOSIGNAL) ==
             static_cast<ssize_t>(length);
}

void reapChild(pid_t child) {
  if (child <= 0)
    return;
  while (waitpid(child, nullptr, 0) < 0 && errno == EINTR) {
  }
}

bool childExited(pid_t child, int *status) {
  if (child <= 0)
    return false;
  *status = -1;
  const pid_t result = waitpid(child, status, WNOHANG);
  return result == child || (result < 0 && errno == ECHILD);
}

void killAndReap(pid_t child, int signal) {
  if (child <= 0)
    return;
  if (kill(child, signal) != 0 && errno != ESRCH)
    return;
  reapChild(child);
}

void terminatePrompt(pid_t prompt) {
  if (prompt <= 0)
    return;
  (void)kill(prompt, SIGTERM);
  for (int attempt = 0; attempt < 20; ++attempt) {
    int status = 0;
    if (childExited(prompt, &status))
      return;
    usleep(10000);
  }
  killAndReap(prompt, SIGKILL);
}

pid_t spawnPrompt(const Account &account, int channel) {
  const pid_t child = fork();
  if (child != 0)
    return child;

  const pid_t expectedParent = getppid();
  if (!resetChildSignals() || dup2(channel, promptChannelFd) < 0)
    _exit(20);
  if (channel != promptChannelFd)
    close(channel);
  const int flags = fcntl(promptChannelFd, F_GETFD);
  if (flags < 0 || fcntl(promptChannelFd, F_SETFD, flags & ~FD_CLOEXEC) != 0)
    _exit(20);
  closeUnrelatedDescriptors();
  if (!dropToAccount(account))
    _exit(20);
  if (!protectFromParentDeath(expectedParent))
    _exit(20);
  configurePromptEnvironment(account);
  if (prctl(PR_SET_DUMPABLE, 0) != 0)
    _exit(20);
  const QByteArray executable = selfPath();
  if (executable.isEmpty())
    _exit(20);
  char *const arguments[] = {const_cast<char *>(executable.constData()),
                             const_cast<char *>("prompt"), nullptr};
  execv(executable.constData(), arguments);
  _exit(20);
}

pid_t spawnVerifier() {
  const pid_t child = fork();
  if (child != 0)
    return child;

  const pid_t expectedParent = getppid();
  if (!resetChildSignals() || !protectFromParentDeath(expectedParent) ||
      setsid() < 0 || !redirectStandardDescriptors())
    _exit(20);
  closeDescriptorsFrom(STDERR_FILENO + 1);

  QByteArray executable = selfPath();
  if (testMode()) {
    const QByteArray override =
        qgetenv("OMARCHY_FACE_ID_ELEVATION_TEST_VERIFIER");
    if (!override.isEmpty())
      executable = override;
  }
  if (executable.isEmpty() || executable.at(0) != '/')
    _exit(20);
  char *const arguments[] = {executable.data(), const_cast<char *>("verify"),
                             nullptr};
  execv(executable.constData(), arguments);
  _exit(20);
}

int refusingConversation(int count, const struct pam_message **messages,
                         struct pam_response **responses, void *) {
  if (count <= 0 || messages == nullptr || responses == nullptr)
    return PAM_CONV_ERR;
  for (int index = 0; index < count; ++index) {
    if (messages[index] == nullptr ||
        messages[index]->msg_style == PAM_PROMPT_ECHO_ON ||
        messages[index]->msg_style == PAM_PROMPT_ECHO_OFF)
      return PAM_CONV_ERR;
  }
  auto *answers = static_cast<struct pam_response *>(
      calloc(static_cast<size_t>(count), sizeof(struct pam_response)));
  if (answers == nullptr)
    return PAM_BUF_ERR;
  *responses = answers;
  return PAM_SUCCESS;
}

int runVerifier() {
  if (geteuid() != 0 && !testMode())
    return 20;
  if (testMode() &&
      qgetenv("OMARCHY_FACE_ID_ELEVATION_TEST_PAM_DIR").isEmpty()) {
    const QByteArray result =
        qgetenv("OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT");
    if (result == "hang") {
      for (;;)
        pause();
    }
    if (result == "crash")
      raise(SIGKILL);
    return result.isEmpty() || result == "success" ? 0 : 20;
  }

  const QByteArray pamDirectory =
      testMode()
          ? qgetenv("OMARCHY_FACE_ID_ELEVATION_TEST_PAM_DIR")
          : QByteArrayLiteral("/usr/lib/omarchy-face-id/pam.d");
  const QByteArray pamFile = pamDirectory + QByteArrayLiteral("/sudo");
  struct stat directoryInfo {};
  struct stat info {};
  const uid_t expectedOwner = testMode() ? getuid() : 0;
  if (pamDirectory.isEmpty() || pamDirectory.at(0) != '/' ||
      lstat(pamDirectory.constData(), &directoryInfo) != 0 ||
      !S_ISDIR(directoryInfo.st_mode) ||
      directoryInfo.st_uid != expectedOwner ||
      (directoryInfo.st_mode & 0022) != 0 ||
      lstat(pamFile.constData(), &info) != 0 || !S_ISREG(info.st_mode) ||
      info.st_uid != expectedOwner || (info.st_mode & 0022) != 0) {
    syslog(LOG_AUTHPRIV | LOG_WARNING,
           "omarchy-face-id verification unavailable: gate=pam-config");
    return 20;
  }

  const Account account = targetAccount();
  if (!account.valid())
    return 20;
  const struct pam_conv conversation = {refusingConversation, nullptr};
  pam_handle_t *handle = nullptr;
  int result = pam_start_confdir("sudo", account.name.constData(),
                                 &conversation, pamDirectory.constData(),
                                 &handle);
  if (result == PAM_SUCCESS)
    result = pam_authenticate(handle, PAM_SILENT);
  if (handle != nullptr)
    pam_end(handle, result);
  if (result == PAM_SUCCESS)
    return 0;
  syslog(LOG_AUTHPRIV | LOG_INFO,
         "omarchy-face-id verification did not succeed: pam-code=%d",
         result);
  return 20;
}

void installCoordinatorSignalHandlers() {
  struct sigaction handled {};
  handled.sa_handler = noteCoordinatorSignal;
  sigemptyset(&handled.sa_mask);
  for (const int signal : {SIGINT, SIGTERM, SIGHUP})
    (void)sigaction(signal, &handled, nullptr);
  struct sigaction ignored {};
  ignored.sa_handler = SIG_IGN;
  sigemptyset(&ignored.sa_mask);
  (void)sigaction(SIGPIPE, &ignored, nullptr);
}

ConsentResult requestConsent() {
  if (geteuid() != 0 && !testMode())
    return ConsentResult::Unavailable;
  const Account account = targetAccount();
  if (!account.valid() || !trustedDesktopEndpoint(account)) {
    syslog(LOG_AUTHPRIV | LOG_WARNING,
           "omarchy-face-id consent unavailable: gate=desktop-endpoint");
    return ConsentResult::Unavailable;
  }

  const int lock = acquireSingleFlightLock();
  if (lock < 0) {
    syslog(LOG_AUTHPRIV | LOG_INFO,
           "omarchy-face-id consent unavailable: gate=single-flight");
    return ConsentResult::Unavailable;
  }
  int channels[2] = {-1, -1};
  if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, channels) != 0) {
    close(lock);
    return ConsentResult::Unavailable;
  }

  installCoordinatorSignalHandlers();
  coordinatorSignal = 0;
  const pid_t prompt = spawnPrompt(account, channels[1]);
  close(channels[1]);
  if (prompt < 0) {
    close(channels[0]);
    close(lock);
    return ConsentResult::Unavailable;
  }

  enum class Phase { WaitingForReady, Deciding, Checking };
  Phase phase = Phase::WaitingForReady;
  pid_t verifier = -1;
  long long deadline = monotonicMilliseconds() +
                       testPhaseTimeoutMs(promptReadyTimeoutMs, 1000);
  ConsentResult outcome = ConsentResult::Unavailable;
  bool finished = false;

  while (!finished) {
    if (coordinatorSignal != 0)
      break;
    const bool deadlineActive = deadline > 0;
    const long long remaining = deadlineActive
                                    ? deadline - monotonicMilliseconds()
                                    : 50;
    if (deadlineActive && remaining <= 0)
      break;
    struct pollfd descriptor { channels[0], POLLIN | POLLHUP | POLLERR, 0 };
    const int ready = poll(&descriptor, 1,
                           static_cast<int>(std::min<long long>(remaining, 50)));
    if (ready < 0 && errno != EINTR)
      break;

    char response[17] = {};
    if (ready > 0 && (descriptor.revents & POLLIN)) {
      const ssize_t length = recv(channels[0], response, sizeof(response) - 1,
                                  MSG_DONTWAIT);
      const QByteArray token = length > 0
                                   ? QByteArray(response,
                                                static_cast<qsizetype>(length))
                                   : QByteArray();
      if (phase == Phase::WaitingForReady && token == "ready") {
        phase = Phase::Deciding;
        deadline = testMode()
                       ? monotonicMilliseconds() +
                             testPhaseTimeoutMs(decisionTimeoutMs, 1000)
                       : 0;
      } else if (phase == Phase::Deciding && token == "approve") {
        if (!sendToken(channels[0], "checking"))
          break;
        verifier = spawnVerifier();
        if (verifier < 0)
          break;
        phase = Phase::Checking;
        deadline = monotonicMilliseconds() +
                   testPhaseTimeoutMs(verificationTimeoutMs, 50);
      } else if (phase == Phase::Deciding && token == "deny") {
        outcome = ConsentResult::Declined;
        finished = true;
      } else if (phase == Phase::Checking && token == "cancel") {
        killAndReap(verifier, SIGKILL);
        verifier = -1;
        outcome = ConsentResult::Declined;
        finished = true;
      } else {
        break;
      }
    }

    int promptStatus = 0;
    if (!finished && childExited(prompt, &promptStatus)) {
      if (verifier > 0) {
        killAndReap(verifier, SIGKILL);
        verifier = -1;
      }
      close(channels[0]);
      close(lock);
      return ConsentResult::Unavailable;
    }

    if (!finished && phase == Phase::Checking && verifier > 0) {
      int verifierStatus = 0;
      if (childExited(verifier, &verifierStatus)) {
        verifier = -1;
        const bool verified = WIFEXITED(verifierStatus) &&
                              WEXITSTATUS(verifierStatus) == 0;
        const bool delivered =
            sendToken(channels[0], verified ? "success" : "fallback");
        usleep(static_cast<useconds_t>(testMode() ? 10000 :
                                      (verified ? successHoldMs
                                                : fallbackHoldMs) * 1000));
        outcome = verified && delivered ? ConsentResult::Approved
                                        : ConsentResult::Unavailable;
        finished = true;
      }
    }
    if (!finished && ready > 0 &&
        (descriptor.revents & (POLLHUP | POLLERR)))
      break;
  }

  if (verifier > 0) {
    killAndReap(verifier, SIGKILL);
    verifier = -1;
    if (phase == Phase::Checking) {
      (void)sendToken(channels[0], "fallback");
      if (!testMode())
        usleep(static_cast<useconds_t>(fallbackHoldMs * 1000));
    }
  }
  close(channels[0]);
  terminatePrompt(prompt);
  close(lock);
  return outcome;
}
} // namespace

int main(int argc, char *argv[]) {
  // PAM can launch the root-owned helper with the invoking account as the
  // real UID. Normalize only the privileged coordinator. The visual child
  // is deliberately dropped back to the desktop account before exec.
  if (argc >= 2 && std::strcmp(argv[1], "prompt") != 0 &&
      getuid() != geteuid()) {
    if (geteuid() != 0 || setuid(0) != 0 || getuid() != geteuid())
      return 20;
  }

  if (argc == 2 && std::strcmp(argv[1], "prompt") == 0)
    return runPrompt(argc, argv);
  if (argc == 2 && std::strcmp(argv[1], "verify") == 0)
    return runVerifier();
  if (argc == 2 && std::strcmp(argv[1], "--version") == 0) {
    QTextStream(stdout) << "Omarchy Face ID elevation helper 3" << Qt::endl;
    return 0;
  }
  if (argc != 2)
    return 2;
  if (std::strcmp(argv[1], "request") == 0)
    return static_cast<int>(requestConsent());
  return 2;
}

#include "main.moc"
