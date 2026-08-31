// SPDX-License-Identifier: GPL-3.0-or-later

#include "GazeClient.h"

#include "CameraInventory.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <QTextStream>

#include <gst/app/gstappsink.h>
#include <gst/gst.h>

#include <pwd.h>
#include <cstdio>
#include <unistd.h>

namespace {
constexpr auto serviceName = "com.gundulabs.Gaze";
constexpr auto objectPath = "/com/gundulabs/Gaze";
constexpr auto interfaceName = "com.gundulabs.Gaze";
constexpr auto facePamPath = "/etc/pam.d/omarchy-face-id-lock";
constexpr auto pluginId = "fitzzz.face-id";

bool gazeConfigAllowsParallelPreview(const QString &path)
{
    QFile config(path);
    if (!config.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;

    bool inCameras = false;
    QString rgb;
    QString ir;
    const QRegularExpression entry(
        QStringLiteral("^\\s*(rgb|ir)\\s*=\\s*[\\\"']([^\\\"']*)"));
    QTextStream stream(&config);
    while (!stream.atEnd()) {
        const QString line = stream.readLine().trimmed();
        if (line.startsWith(QLatin1Char('['))) {
            inCameras = line == QStringLiteral("[cameras]");
            continue;
        }
        if (!inCameras)
            continue;
        const auto match = entry.match(line);
        if (!match.hasMatch())
            continue;
        if (match.captured(1) == QStringLiteral("rgb"))
            rgb = match.captured(2).trimmed();
        else
            ir = match.captured(2).trimmed();
    }

    return ir.isEmpty()
        && (rgb == QStringLiteral("primary")
            || rgb.startsWith(QStringLiteral("pipewiresrc")));
}

QString enrollmentReceiptPath()
{
    QString stateRoot = qEnvironmentVariable("XDG_STATE_HOME");
    if (stateRoot.isEmpty())
        stateRoot = QDir::homePath() + QStringLiteral("/.local/state");
    return stateRoot + QStringLiteral("/omarchy-face-id/enrolled-face");
}

bool jpegDecoderAvailable()
{
    const QString testMarker = qEnvironmentVariable(
        "OMARCHY_FACE_ID_JPEG_DECODER_MARKER");
    if (!testMarker.isEmpty())
        return QFileInfo(testMarker).isFile();

    gst_init(nullptr, nullptr);
    gst_registry_scan_path(gst_registry_get(), "/usr/lib/gstreamer-1.0");
    GstElementFactory *factory = gst_element_factory_find("jpegdec");
    if (!factory)
        return false;
    gst_object_unref(factory);
    return true;
}

QByteArray resourceContents(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return file.readAll();
}

bool fileMatches(const QString &path, const QByteArray &expected)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) && file.readAll() == expected;
}

QString presenceHelperSourcePath()
{
    const QString overridePath = qEnvironmentVariable(
        "OMARCHY_FACE_ID_PRESENCE_HELPER_PATH");
    const QString applicationDirectory = QCoreApplication::applicationDirPath();
    const QStringList candidates = overridePath.isEmpty()
        ? QStringList{
              applicationDirectory + QStringLiteral("/omarchy-face-id-presence"),
              QDir::cleanPath(applicationDirectory
                              + QStringLiteral("/../libexec/omarchy-face-id-presence"))}
        : QStringList{overridePath};

    for (const QString &candidate : candidates) {
        const QFileInfo info(candidate);
        if (info.isFile() && info.isReadable() && info.isExecutable()
            && !info.isSymLink())
            return candidate;
    }
    return {};
}

bool pluginEnabled(const QString &configRoot)
{
    QFile config(configRoot + QStringLiteral("/omarchy/shell.json"));
    if (!config.open(QIODevice::ReadOnly))
        return false;

    const QJsonDocument document = QJsonDocument::fromJson(config.readAll());
    if (!document.isObject())
        return false;

    const QJsonArray plugins = document.object().value(QStringLiteral("plugins")).toArray();
    for (const QJsonValue &entry : plugins) {
        if (entry.isObject()
            && entry.toObject().value(QStringLiteral("id")).toString()
                == QString::fromLatin1(pluginId))
            return true;
    }
    return false;
}

QString installedGazeVersion()
{
    QDir database(QStringLiteral("/var/lib/pacman/local"));
    const QStringList packages = database.entryList(
        {QStringLiteral("gaze-bin-*"), QStringLiteral("gaze-*")},
        QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &package : packages) {
        QFile description(database.filePath(package + QStringLiteral("/desc")));
        if (!description.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        QTextStream stream(&description);
        while (!stream.atEnd()) {
            if (stream.readLine() == QStringLiteral("%VERSION%") && !stream.atEnd())
                return stream.readLine().trimmed();
        }
    }
    return QStringLiteral("unknown");
}

QDBusInterface gazeInterface()
{
    return QDBusInterface(QString::fromLatin1(serviceName),
                          QString::fromLatin1(objectPath),
                          QString::fromLatin1(interfaceName),
                          QDBusConnection::systemBus());
}
}

GazeClient::GazeClient(QObject *parent)
    : QObject(parent)
{
    m_diagnostics.record(
        QStringLiteral("app.lifecycle"),
        QStringLiteral("session_started"),
        DiagnosticLog::Level::Info,
        {{QStringLiteral("app_version"), QStringLiteral(OMARCHY_FACE_ID_VERSION)},
         {QStringLiteral("log_schema_version"), 1}});
    ensureUserConfig();
    m_themeRoot = qEnvironmentVariable("OMARCHY_FACE_ID_THEME_ROOT",
                                       QDir::homePath()
                                           + QStringLiteral("/.local/state/omarchy/current"));
    m_themeReloadTimer.setSingleShot(true);
    m_themeReloadTimer.setInterval(40);
    connect(&m_themeReloadTimer, &QTimer::timeout, this, &GazeClient::reloadTheme);
    connect(&m_themeWatcher, &QFileSystemWatcher::fileChanged,
            this, &GazeClient::scheduleThemeReload);
    connect(&m_themeWatcher, &QFileSystemWatcher::directoryChanged,
            this, &GazeClient::scheduleThemeReload);
    m_faceSetupPollTimer.setInterval(1000);
    connect(&m_faceSetupPollTimer, &QTimer::timeout, this, [this] {
        ++m_faceSetupPollCount;

        QFile status(m_faceSetupStatusPath);
        if (status.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString result = QString::fromUtf8(status.readAll()).trimmed();
            if (result == QStringLiteral("failure")) {
                finishFaceSetup(
                    false,
                    QStringLiteral("Face ID system setup did not finish. Try again."));
                return;
            }
            if (result == QStringLiteral("success")) {
                refresh();
                if (m_installed && m_serviceAvailable && m_cameraSupportAvailable) {
                    finishFaceSetup(true);
                    return;
                }
            }
        }

        if (m_faceSetupPollCount >= 300) {
            finishFaceSetup(
                false,
                QStringLiteral("Setup took too long. Check the installer and try again."));
        }
    });
    m_lockActivationDeadline.setSingleShot(true);
    connect(&m_lockActivationDeadline, &QTimer::timeout, this, [this] {
        if (m_lockActivationPhase == LockActivationPhase::Idle)
            return;
        refreshLockIntegrationStatus();
        finishLockActivation(
            m_lockIntegrationInstalled,
            m_lockIntegrationInstalled
                ? QString()
                : QStringLiteral("Face ID setup timed out. Nothing changed; try again."));
    });
    reloadTheme();
    refreshLockIntegrationStatus();

    auto bus = QDBusConnection::systemBus();
    bus.connect(QString::fromLatin1(serviceName),
                QString::fromLatin1(objectPath),
                QString::fromLatin1(interfaceName),
                QStringLiteral("EnrollStatus"),
                this,
                SLOT(onEnrollStatus(QString,uint,uint,bool,QString,double)));
    bus.connect(QString::fromLatin1(serviceName),
                QString::fromLatin1(objectPath),
                QString::fromLatin1(interfaceName),
                QStringLiteral("FaceStatus"),
                this,
                SLOT(onFaceStatus(QString)));
    bus.connect(QString::fromLatin1(serviceName),
                QString::fromLatin1(objectPath),
                QString::fromLatin1(interfaceName),
                QStringLiteral("PreviewFrame"),
                this,
                SLOT(onPreviewFrame(QByteArray)));
    refresh();
    CameraInventory::recordSnapshot(
        m_diagnostics,
        qEnvironmentVariable("OMARCHY_FACE_ID_GAZE_CONFIG",
                             QStringLiteral("/etc/gaze/config.toml")),
        QStringLiteral("app_start"));
}

GazeClient::~GazeClient()
{
    m_diagnostics.record(QStringLiteral("app.lifecycle"),
                         QStringLiteral("session_stopped"));
    if (!m_faceSetupInstalling && !m_faceSetupStatusPath.isEmpty())
        QFile::remove(m_faceSetupStatusPath);
    stopParallelPreview();
    releaseClaim();
}

bool GazeClient::installed() const { return m_installed; }
bool GazeClient::serviceAvailable() const { return m_serviceAvailable; }
bool GazeClient::cameraAvailable() const { return m_cameraAvailable; }
bool GazeClient::cameraSupportAvailable() const { return m_cameraSupportAvailable; }
bool GazeClient::parallelPreviewAvailable() const { return m_parallelPreviewAvailable; }
bool GazeClient::faceSetupInstalling() const { return m_faceSetupInstalling; }
QString GazeClient::faceSetupError() const { return m_faceSetupError; }
bool GazeClient::enrolling() const { return m_enrolling; }
bool GazeClient::enrollmentComplete() const { return m_enrollmentComplete; }
int GazeClient::enrollmentProgress() const { return m_enrollmentProgress; }
int GazeClient::enrollmentMaximum() const { return m_enrollmentMaximum; }
QString GazeClient::enrollmentPrompt() const { return m_enrollmentPrompt; }
QString GazeClient::faceStatus() const { return m_faceStatus; }
QString GazeClient::previewDataUrl() const { return m_previewDataUrl; }
QString GazeClient::errorMessage() const { return m_errorMessage; }
bool GazeClient::lockIntegrationInstalled() const { return m_lockIntegrationInstalled; }
bool GazeClient::lockIntegrationInstalling() const { return m_lockIntegrationInstalling; }
QString GazeClient::lockIntegrationError() const { return m_lockIntegrationError; }
QColor GazeClient::themeBackground() const { return m_themeBackground; }
QColor GazeClient::themeDarkBackground() const { return m_themeDarkBackground; }
QColor GazeClient::themeDarkerBackground() const { return m_themeDarkerBackground; }
QColor GazeClient::themeLighterBackground() const { return m_themeLighterBackground; }
QColor GazeClient::themeForeground() const { return m_themeForeground; }
QColor GazeClient::themeMuted() const { return m_themeMuted; }
QColor GazeClient::themeAccent() const { return m_themeAccent; }
QColor GazeClient::themeOrange() const { return m_themeOrange; }
QColor GazeClient::themeGreen() const { return m_themeGreen; }
QColor GazeClient::themeRed() const { return m_themeRed; }

void GazeClient::ensureUserConfig()
{
    QString configRoot = qEnvironmentVariable("OMARCHY_FACE_ID_CONFIG_HOME");
    if (configRoot.isEmpty())
        configRoot = qEnvironmentVariable("OMARCHY_FACE_ID_CONFIG_ROOT");
    if (configRoot.isEmpty())
        configRoot = QStandardPaths::writableLocation(
            QStandardPaths::GenericConfigLocation);
    const QString directory = configRoot + QStringLiteral("/omarchy-face-id");
    const QString targetPath = directory + QStringLiteral("/config.toml");
    const QFileInfo targetInfo(targetPath);

    if (targetInfo.isSymLink()) {
        m_diagnostics.record(QStringLiteral("app.configuration"),
                             QStringLiteral("user_config_rejected"),
                             DiagnosticLog::Level::Error,
                             {{QStringLiteral("reason"), QStringLiteral("symlink")}});
        return;
    }
    if (targetInfo.exists()) {
        m_diagnostics.record(QStringLiteral("app.configuration"),
                             QStringLiteral("user_config_observed"),
                             DiagnosticLog::Level::Info,
                             {{QStringLiteral("created"), false}});
        return;
    }

    const bool directoryExisted = QFileInfo::exists(directory);
    if (!QDir().mkpath(directory)) {
        m_diagnostics.record(QStringLiteral("app.configuration"),
                             QStringLiteral("user_config_create_failed"),
                             DiagnosticLog::Level::Error,
                             {{QStringLiteral("stage"), QStringLiteral("directory")}});
        return;
    }
    if (!directoryExisted) {
        QFile::setPermissions(directory,
                              QFileDevice::ReadOwner | QFileDevice::WriteOwner
                                  | QFileDevice::ExeOwner);
    }

    const QByteArray defaults = resourceContents(
        QStringLiteral(":/config/default-config.toml"));
    QSaveFile target(targetPath);
    if (defaults.isEmpty()
        || !target.open(QIODevice::WriteOnly)
        || target.write(defaults) != defaults.size()
        || !target.commit()
        || !QFile::setPermissions(
            targetPath, QFileDevice::ReadOwner | QFileDevice::WriteOwner)) {
        m_diagnostics.record(QStringLiteral("app.configuration"),
                             QStringLiteral("user_config_create_failed"),
                             DiagnosticLog::Level::Error,
                             {{QStringLiteral("stage"), QStringLiteral("file")}});
        return;
    }

    m_diagnostics.record(QStringLiteral("app.configuration"),
                         QStringLiteral("user_config_observed"),
                         DiagnosticLog::Level::Info,
                         {{QStringLiteral("created"), true}});
}

void GazeClient::refresh()
{
    const bool wasInstalled = m_installed;
    const bool wasAvailable = m_serviceAvailable;
    const bool wasCameraAvailable = m_cameraAvailable;
    const bool wasCameraSupportAvailable = m_cameraSupportAvailable;
    const bool wasParallelPreviewAvailable = m_parallelPreviewAvailable;

    m_installed = QFileInfo(qEnvironmentVariable(
        "OMARCHY_FACE_ID_GAZE_PATH", QStringLiteral("/usr/bin/gaze"))).isExecutable();
    m_cameraSupportAvailable = jpegDecoderAvailable();
    auto *busInterface = QDBusConnection::systemBus().interface();
    const QDBusReply<bool> registered = busInterface
        ? busInterface->isServiceRegistered(QString::fromLatin1(serviceName))
        : QDBusReply<bool>();
    m_serviceAvailable = registered.isValid() && registered.value();
    m_cameraAvailable = false;
    m_parallelPreviewAvailable = gazeConfigAllowsParallelPreview(
        qEnvironmentVariable("OMARCHY_FACE_ID_GAZE_CONFIG",
                             QStringLiteral("/etc/gaze/config.toml")));

    if (m_serviceAvailable) {
        auto iface = gazeInterface();
        const QDBusReply<bool> reply = iface.call(QStringLiteral("IsCameraAvailable"));
        m_cameraAvailable = reply.isValid() && reply.value();
        if (!reply.isValid())
            setError(reply.error().message());
        else
            setError({});
    }

    if (wasInstalled != m_installed || wasAvailable != m_serviceAvailable
        || wasCameraAvailable != m_cameraAvailable
        || wasCameraSupportAvailable != m_cameraSupportAvailable
        || wasParallelPreviewAvailable != m_parallelPreviewAvailable) {
        m_diagnostics.record(
            QStringLiteral("app.environment"),
            QStringLiteral("gaze_snapshot_changed"),
            DiagnosticLog::Level::Info,
            {{QStringLiteral("installed"), m_installed},
             {QStringLiteral("package_version"), installedGazeVersion()},
             {QStringLiteral("service_available"), m_serviceAvailable},
             {QStringLiteral("camera_available"), m_cameraAvailable},
             {QStringLiteral("camera_support_available"),
              m_cameraSupportAvailable},
             {QStringLiteral("parallel_preview_eligible"),
              m_parallelPreviewAvailable}});
        emit availabilityChanged();
    }
}

void GazeClient::installFaceSetup()
{
    if (m_faceSetupInstalling)
        return;

    m_diagnostics.record(QStringLiteral("dependency.gaze"),
                         QStringLiteral("setup_requested"));

    refresh();
    if (m_installed && m_serviceAvailable && m_cameraSupportAvailable) {
        m_faceSetupError.clear();
        emit faceSetupChanged();
        return;
    }

    const QString terminalLauncher = QStandardPaths::findExecutable(
        QStringLiteral("omarchy-launch-terminal"));
    const QByteArray installerContents = resourceContents(
        QStringLiteral(":/scripts/install-gaze-arch.sh"));
    if (terminalLauncher.isEmpty() || installerContents.isEmpty()) {
        m_faceSetupError = QStringLiteral("The Gaze package installer is unavailable.");
        emit faceSetupChanged();
        return;
    }

    QTemporaryFile installer(
        QDir::tempPath() + QStringLiteral("/omarchy-face-id-installer.XXXXXX"));
    installer.setAutoRemove(false);
    if (!installer.open()
        || installer.write(installerContents) != installerContents.size()
        || !installer.flush()) {
        m_faceSetupError = QStringLiteral("Could not prepare the Gaze package installer.");
        emit faceSetupChanged();
        return;
    }
    const QString installerPath = installer.fileName();
    installer.close();
    QFile::setPermissions(
        installerPath,
        QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);

    QTemporaryFile status(
        QDir::tempPath() + QStringLiteral("/omarchy-face-id-install.XXXXXX"));
    status.setAutoRemove(false);
    if (!status.open()) {
        QFile::remove(installerPath);
        m_faceSetupError = QStringLiteral("Could not start Gaze package setup.");
        emit faceSetupChanged();
        return;
    }
    m_faceSetupStatusPath = status.fileName();
    status.close();
    QFile::remove(m_faceSetupStatusPath);

    qint64 installerPid = 0;
    const bool launched = QProcess::startDetached(
        terminalLauncher,
        {QStringLiteral("/usr/bin/bash"),
         installerPath,
         QStringLiteral("--wizard"),
         QStringLiteral("--status-file"), m_faceSetupStatusPath,
         QStringLiteral("--self-delete")},
        QString(),
        &installerPid);
    if (!launched) {
        QFile::remove(installerPath);
        m_faceSetupStatusPath.clear();
        m_faceSetupError = QStringLiteral("Could not open the Gaze package installer.");
        emit faceSetupChanged();
        return;
    }

    m_faceSetupPollCount = 0;
    m_faceSetupError.clear();
    m_faceSetupInstalling = true;
    m_faceSetupPollTimer.start();
    emit faceSetupChanged();
}

void GazeClient::finishFaceSetup(bool success, const QString &error)
{
    m_diagnostics.record(
        QStringLiteral("dependency.gaze"),
        QStringLiteral("setup_finished"),
        success ? DiagnosticLog::Level::Info : DiagnosticLog::Level::Error,
        {{QStringLiteral("success"), success},
         {QStringLiteral("failure_class"),
          success ? QStringLiteral("none") : QStringLiteral("installer")}});
    m_faceSetupPollTimer.stop();
    if (!m_faceSetupStatusPath.isEmpty())
        QFile::remove(m_faceSetupStatusPath);
    m_faceSetupStatusPath.clear();
    m_faceSetupPollCount = 0;
    m_faceSetupInstalling = false;
    m_faceSetupError = success ? QString() : error;
    if (success)
        refresh();
    if (success) {
        CameraInventory::recordSnapshot(
            m_diagnostics,
            qEnvironmentVariable("OMARCHY_FACE_ID_GAZE_CONFIG",
                                 QStringLiteral("/etc/gaze/config.toml")),
            QStringLiteral("dependency_ready"));
    }
    emit faceSetupChanged();
}

void GazeClient::beginEnrollment(const QString &faceName)
{
    if (m_enrolling)
        return;
    m_diagnostics.record(QStringLiteral("enrollment.workflow"),
                         QStringLiteral("start_requested"));
    CameraInventory::recordSnapshot(
        m_diagnostics,
        qEnvironmentVariable("OMARCHY_FACE_ID_GAZE_CONFIG",
                             QStringLiteral("/etc/gaze/config.toml")),
        QStringLiteral("enrollment_start"));
    refresh();
    if (!m_serviceAvailable) {
        m_diagnostics.record(
            QStringLiteral("enrollment.workflow"),
            QStringLiteral("start_rejected"),
            DiagnosticLog::Level::Error,
            {{QStringLiteral("reason"), QStringLiteral("service_unavailable")}});
        setError(QStringLiteral("The Gaze system service is not available."));
        return;
    }
    if (!m_cameraSupportAvailable) {
        m_diagnostics.record(
            QStringLiteral("enrollment.workflow"),
            QStringLiteral("start_rejected"),
            DiagnosticLog::Level::Error,
            {{QStringLiteral("reason"),
              QStringLiteral("camera_support_unavailable")}});
        setError(QStringLiteral("Required camera support is not installed."));
        return;
    }

    const QString resolvedName = faceName.trimmed().isEmpty()
        ? QStringLiteral("default")
        : faceName.trimmed();
    const passwd *account = getpwuid(getuid());
    const QString username = account && account->pw_name
        ? QString::fromLocal8Bit(account->pw_name)
        : QString();
    if (username.isEmpty()) {
        m_diagnostics.record(
            QStringLiteral("enrollment.workflow"),
            QStringLiteral("start_rejected"),
            DiagnosticLog::Level::Error,
            {{QStringLiteral("reason"), QStringLiteral("account_unavailable")}});
        setError(QStringLiteral("Could not determine the current user."));
        return;
    }

    auto iface = gazeInterface();
    QDBusReply<void> claimReply = iface.call(QStringLiteral("Claim"), username);
    if (!claimReply.isValid()) {
        m_diagnostics.record(
            QStringLiteral("enrollment.gaze_dbus"),
            QStringLiteral("claim_finished"),
            DiagnosticLog::Level::Error,
            {{QStringLiteral("success"), false},
             {QStringLiteral("error_id"), claimReply.error().name()}});
        setError(claimReply.error().message());
        return;
    }
    m_diagnostics.record(
        QStringLiteral("enrollment.gaze_dbus"),
        QStringLiteral("claim_finished"),
        DiagnosticLog::Level::Info,
        {{QStringLiteral("success"), true}});
    m_claimed = true;

    m_enrollmentProgress = 0;
    m_enrollmentMaximum = 5;
    m_enrollmentComplete = false;
    m_enrollmentPrompt = QStringLiteral("Starting enrollment…");
    m_faceStatus.clear();
    m_previewDataUrl.clear();
    m_remotePreviewFrames = 0;
    m_parallelPreviewFrames = 0;
    m_enrolling = true;
    m_enrollmentFaceName = resolvedName;
    emit enrollingChanged();
    emit enrollmentChanged();
    emit previewChanged();

    const int enrollmentGeneration = ++m_enrollmentGeneration;
    iface.setTimeout(120000);
    auto *watcher = new QDBusPendingCallWatcher(
        iface.asyncCall(QStringLiteral("EnrollStart"), resolvedName), this);
    m_diagnostics.record(QStringLiteral("enrollment.gaze_dbus"),
                         QStringLiteral("enroll_start_sent"));
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, watcher, enrollmentGeneration] {
                const QDBusPendingReply<void> enrollReply = *watcher;
                watcher->deleteLater();

                if (enrollmentGeneration != m_enrollmentGeneration) {
                    if (enrollReply.isValid() && !m_enrolling) {
                        auto iface = gazeInterface();
                        iface.call(QDBus::NoBlock, QStringLiteral("EnrollStop"));
                    }
                    return;
                }

                if (!enrollReply.isValid()) {
                    m_diagnostics.record(
                        QStringLiteral("enrollment.gaze_dbus"),
                        QStringLiteral("enroll_start_finished"),
                        DiagnosticLog::Level::Error,
                        {{QStringLiteral("success"), false},
                         {QStringLiteral("error_id"), enrollReply.error().name()}});
                    m_enrolling = false;
                    emit enrollingChanged();
                    stopParallelPreview();
                    releaseClaim();
                    setError(enrollReply.error().message());
                    return;
                }

                m_diagnostics.record(
                    QStringLiteral("enrollment.gaze_dbus"),
                    QStringLiteral("enroll_start_finished"),
                    DiagnosticLog::Level::Info,
                    {{QStringLiteral("success"), true}});
                setError({});
                // Enrollment owns the camera. Give Gaze time to establish its
                // capture stream before attaching the optional shared preview;
                // a preview must never be able to break the biometric scan.
                QTimer::singleShot(1000, this, [this, enrollmentGeneration] {
                    if (enrollmentGeneration == m_enrollmentGeneration
                        && m_enrolling
                        && m_parallelPreviewAvailable
                        && m_previewDataUrl.isEmpty())
                        startParallelPreview();
                });
            });
}

void GazeClient::cancelEnrollment()
{
    m_diagnostics.record(QStringLiteral("enrollment.workflow"),
                         QStringLiteral("cancel_requested"));
    ++m_enrollmentGeneration;
    if (m_serviceAvailable) {
        auto iface = gazeInterface();
        iface.call(QDBus::NoBlock, QStringLiteral("EnrollStop"));
    }
    stopParallelPreview(true);
    releaseClaim();
    m_enrolling = false;
    m_enrollmentPrompt = QStringLiteral("Enrollment cancelled");
    emit enrollingChanged();
    emit enrollmentChanged();
}

void GazeClient::enableLockIntegration()
{
    if (m_lockIntegrationInstalling)
        return;

    m_diagnostics.record(QStringLiteral("lock.activation"),
                         QStringLiteral("start_requested"));

    m_lockIntegrationError.clear();
    m_lockPluginDiscoveryPasses = 0;
    const QByteArray pamContents = resourceContents(
        QStringLiteral(":/packaging/pam/omarchy-face-id-lock"));
    if (pamContents.isEmpty()) {
        m_lockIntegrationError = QStringLiteral("The Face ID service file is missing from this build.");
        emit lockIntegrationChanged();
        return;
    }

    const QString configuredPamPath = qEnvironmentVariable(
        "OMARCHY_FACE_ID_PAM_PATH", QString::fromLatin1(facePamPath));
    if (QFileInfo::exists(configuredPamPath)) {
        if (!fileMatches(configuredPamPath, pamContents)) {
            m_lockIntegrationError = QStringLiteral(
                "A different Face ID service already exists. It was left unchanged.");
            emit lockIntegrationChanged();
            return;
        }
        const int configuredTimeout = qEnvironmentVariableIntValue(
            "OMARCHY_FACE_ID_ACTIVATION_TIMEOUT_MS");
        m_lockActivationDeadline.start(configuredTimeout > 0 ? configuredTimeout : 90000);
        m_lockIntegrationInstalling = true;
        m_lockActivationPhase = LockActivationPhase::Authorizing;
        emit lockIntegrationChanged();
        continueLockIntegrationInstall();
        return;
    }

    const QString pkexec = QStandardPaths::findExecutable(QStringLiteral("pkexec"));
    if (pkexec.isEmpty()) {
        m_lockIntegrationError = QStringLiteral("System authorization is unavailable.");
        emit lockIntegrationChanged();
        return;
    }

    m_lockIntegrationPamFile = new QTemporaryFile(
        QDir::tempPath() + QStringLiteral("/omarchy-face-id-lock.XXXXXX"), this);
    if (!m_lockIntegrationPamFile->open()
        || m_lockIntegrationPamFile->write(pamContents) != pamContents.size()
        || !m_lockIntegrationPamFile->flush()) {
        m_lockIntegrationError = QStringLiteral("Could not prepare the Face ID service.");
        delete m_lockIntegrationPamFile;
        m_lockIntegrationPamFile = nullptr;
        emit lockIntegrationChanged();
        return;
    }
    m_lockIntegrationPamFile->close();

    const int configuredTimeout = qEnvironmentVariableIntValue(
        "OMARCHY_FACE_ID_ACTIVATION_TIMEOUT_MS");
    m_lockActivationDeadline.start(configuredTimeout > 0 ? configuredTimeout : 90000);
    m_lockIntegrationInstalling = true;
    m_lockActivationPhase = LockActivationPhase::Authorizing;
    emit lockIntegrationChanged();

    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    m_lockIntegrationProcess = process;
    connect(process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this, process](int, QProcess::ExitStatus) {
                if (m_lockIntegrationProcess != process
                    || m_lockActivationPhase != LockActivationPhase::Authorizing)
                    return;
                const QByteArray diagnostic = process->readAll();
                if (!diagnostic.isEmpty())
                    qWarning().noquote() << QString::fromLocal8Bit(diagnostic).trimmed();
                m_lockIntegrationProcess = nullptr;
                process->deleteLater();
                continueLockIntegrationInstall();
            },
            Qt::SingleShotConnection);
    connect(process, &QProcess::errorOccurred, this,
            [this, process](QProcess::ProcessError) {
                if (m_lockIntegrationProcess != process
                    || m_lockActivationPhase != LockActivationPhase::Authorizing)
                    return;
                abandonProcess(m_lockIntegrationProcess);
                continueLockIntegrationInstall();
            },
            Qt::SingleShotConnection);
    process->start(
        pkexec,
        {QStringLiteral("/usr/bin/install"),
         QStringLiteral("-o"), QStringLiteral("root"),
         QStringLiteral("-g"), QStringLiteral("root"),
         QStringLiteral("-m"), QStringLiteral("0644"),
         m_lockIntegrationPamFile->fileName(), configuredPamPath});
}

void GazeClient::refreshLockIntegrationStatus()
{
    const bool installed = lockIntegrationStateMatches();

    if (installed != m_lockIntegrationInstalled) {
        m_lockIntegrationInstalled = installed;
        emit lockIntegrationChanged();
    }

    // Version 0.3.0 predates enrollment receipts and always used "default".
    // A matching installed subscriber is sufficient evidence to migrate it.
    if (installed && !QFileInfo::exists(enrollmentReceiptPath()))
        recordEnrollmentOwnership(QStringLiteral("default"));
}

bool GazeClient::lockIntegrationStateMatches() const
{
    const QString configRoot = qEnvironmentVariable(
        "OMARCHY_FACE_ID_CONFIG_ROOT",
        QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation));
    const QString pluginRoot = configRoot
        + QStringLiteral("/omarchy/plugins/") + QString::fromLatin1(pluginId);
    const QString configuredPamPath = qEnvironmentVariable(
        "OMARCHY_FACE_ID_PAM_PATH", QString::fromLatin1(facePamPath));
    const QString presenceHelper = presenceHelperSourcePath();
    const QByteArray presenceHelperContents = resourceContents(presenceHelper);
    const QString installedPresenceHelper = pluginRoot
        + QStringLiteral("/presence-watcher");

    return !presenceHelperContents.isEmpty()
        && fileMatches(
        configuredPamPath,
        resourceContents(QStringLiteral(":/packaging/pam/omarchy-face-id-lock")))
        && fileMatches(
            pluginRoot + QStringLiteral("/Service.qml"),
            resourceContents(QStringLiteral(":/integration/omarchy-plugin/Service.qml")))
        && fileMatches(
            pluginRoot + QStringLiteral("/manifest.json"),
            resourceContents(QStringLiteral(":/integration/omarchy-plugin/manifest.json")))
        && fileMatches(
            pluginRoot + QStringLiteral("/ding.mp3"),
            resourceContents(QStringLiteral(":/assets/ding.mp3")))
        && fileMatches(
            pluginRoot + QStringLiteral("/log-event.sh"),
            resourceContents(QStringLiteral(":/integration/omarchy-plugin/log-event.sh")))
        && fileMatches(installedPresenceHelper, presenceHelperContents)
        && QFileInfo(installedPresenceHelper).isExecutable()
        && pluginEnabled(configRoot);
}

void GazeClient::recordEnrollmentOwnership(const QString &faceName)
{
    const QString receiptPath = enrollmentReceiptPath();
    const QFileInfo receiptInfo(receiptPath);
    if (!QDir().mkpath(receiptInfo.absolutePath()))
        return;

    QSaveFile receipt(receiptPath);
    const QByteArray contents = faceName.toUtf8() + '\n';
    if (receipt.open(QIODevice::WriteOnly)
        && receipt.write(contents) == contents.size()
        && receipt.commit()) {
        QFile::setPermissions(receiptPath,
                              QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    }
}

bool GazeClient::installUserPlugin(QString *error)
{
    const QString configRoot = qEnvironmentVariable(
        "OMARCHY_FACE_ID_CONFIG_ROOT",
        QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation));
    const QString pluginRoot = configRoot
        + QStringLiteral("/omarchy/plugins/") + QString::fromLatin1(pluginId);

    if (QFileInfo(pluginRoot).isSymLink()) {
        *error = QStringLiteral("The Face ID plugin folder is a symbolic link. It was left unchanged.");
        return false;
    }
    if (!QDir().mkpath(pluginRoot)) {
        *error = QStringLiteral("Could not create the Face ID plugin folder.");
        return false;
    }

    const auto writeContents = [error](const QByteArray &contents,
                                       const QString &targetPath,
                                       QFileDevice::Permissions permissions) {
        if (contents.isEmpty()) {
            *error = QStringLiteral("This build is missing an integration file.");
            return false;
        }
        if (QFileInfo(targetPath).isSymLink()) {
            *error = QStringLiteral("An integration file is a symbolic link. It was left unchanged.");
            return false;
        }
        QSaveFile target(targetPath);
        if (!target.open(QIODevice::WriteOnly)
            || target.write(contents) != contents.size()
            || !target.commit()) {
            *error = QStringLiteral("Could not install the Omarchy Face ID plugin.");
            return false;
        }
        if (!QFile::setPermissions(targetPath, permissions)) {
            *error = QStringLiteral("Could not secure an Omarchy Face ID integration file.");
            return false;
        }
        return true;
    };
    const auto writeResource = [&writeContents](const QString &resourcePath,
                                                const QString &targetPath,
                                                QFileDevice::Permissions permissions) {
        return writeContents(resourceContents(resourcePath), targetPath, permissions);
    };

    const auto readable = QFileDevice::ReadOwner | QFileDevice::WriteOwner
        | QFileDevice::ReadGroup | QFileDevice::ReadOther;
    const auto executable = readable | QFileDevice::ExeOwner
        | QFileDevice::ExeGroup | QFileDevice::ExeOther;
    const QByteArray presenceHelper = resourceContents(presenceHelperSourcePath());

    return writeResource(
               QStringLiteral(":/integration/omarchy-plugin/Service.qml"),
               pluginRoot + QStringLiteral("/Service.qml"), readable)
        && writeResource(
            QStringLiteral(":/integration/omarchy-plugin/manifest.json"),
            pluginRoot + QStringLiteral("/manifest.json"), readable)
        && writeResource(
            QStringLiteral(":/assets/ding.mp3"),
            pluginRoot + QStringLiteral("/ding.mp3"), readable)
        && writeResource(
            QStringLiteral(":/integration/omarchy-plugin/log-event.sh"),
            pluginRoot + QStringLiteral("/log-event.sh"), executable)
        && writeContents(
            presenceHelper,
            pluginRoot + QStringLiteral("/presence-watcher"), executable);
}

void GazeClient::continueLockIntegrationInstall()
{
    if (!m_lockIntegrationInstalling
        || m_lockActivationPhase != LockActivationPhase::Authorizing)
        return;

    if (m_lockIntegrationPamFile) {
        delete m_lockIntegrationPamFile;
        m_lockIntegrationPamFile = nullptr;
    }

    const QByteArray pamContents = resourceContents(
        QStringLiteral(":/packaging/pam/omarchy-face-id-lock"));
    const QString configuredPamPath = qEnvironmentVariable(
        "OMARCHY_FACE_ID_PAM_PATH", QString::fromLatin1(facePamPath));
    if (!fileMatches(configuredPamPath, pamContents)) {
        m_diagnostics.record(
            QStringLiteral("lock.activation"),
            QStringLiteral("pam_verification_finished"),
            DiagnosticLog::Level::Error,
            {{QStringLiteral("success"), false}});
        finishLockActivation(false,
                             QStringLiteral("Face ID wasn’t enabled. Nothing changed."));
        return;
    }
    m_diagnostics.record(
        QStringLiteral("lock.activation"),
        QStringLiteral("pam_verification_finished"),
        DiagnosticLog::Level::Info,
        {{QStringLiteral("success"), true}});

    // Installing into the watched Omarchy plugin directory reloads every
    // shell service, including the polkit agent. Do it only after pkexec has
    // finished so the password conversation cannot be destroyed mid-flight.
    QString pluginError;
    if (!installUserPlugin(&pluginError)) {
        finishLockActivation(false, pluginError);
        return;
    }

    m_lockPluginRescanCommand = QStandardPaths::findExecutable(
        QStringLiteral("omarchy-shell"));
    m_lockPluginEnableCommand = QStandardPaths::findExecutable(
        QStringLiteral("omarchy-plugin-enable"));
    if (m_lockPluginRescanCommand.isEmpty() || m_lockPluginEnableCommand.isEmpty()) {
        finishLockActivation(
            false,
            QStringLiteral("Face ID couldn’t be added to the lock screen. Try again."));
        return;
    }

    startLockPluginRescan();
}

void GazeClient::startLockPluginRescan()
{
    if (!m_lockIntegrationInstalling || m_lockPluginRescanCommand.isEmpty()
        || m_lockPluginEnableProcess)
        return;

    m_lockActivationPhase = LockActivationPhase::Rescanning;
    ++m_lockPluginDiscoveryPasses;
    m_diagnostics.record(
        QStringLiteral("lock.activation"),
        QStringLiteral("plugin_rescan_started"),
        DiagnosticLog::Level::Debug,
        {{QStringLiteral("pass"), m_lockPluginDiscoveryPasses}});
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    m_lockPluginEnableProcess = process;
    connect(process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this, process](int, QProcess::ExitStatus) {
                if (m_lockPluginEnableProcess != process
                    || m_lockActivationPhase != LockActivationPhase::Rescanning)
                    return;
                abandonProcess(m_lockPluginEnableProcess);
                startLockPluginEnable();
            },
            Qt::SingleShotConnection);
    connect(process, &QProcess::errorOccurred, this,
            [this, process](QProcess::ProcessError) {
                if (m_lockPluginEnableProcess != process
                    || m_lockActivationPhase != LockActivationPhase::Rescanning)
                    return;
                m_lockPluginEnableProcess = nullptr;
                process->deleteLater();
                startLockPluginEnable();
            },
            Qt::SingleShotConnection);
    process->start(m_lockPluginRescanCommand,
                   {QStringLiteral("shell"), QStringLiteral("rescanPlugins")});
}

void GazeClient::startLockPluginEnable()
{
    if (!m_lockIntegrationInstalling || m_lockPluginEnableCommand.isEmpty()
        || m_lockPluginEnableProcess)
        return;

    m_lockActivationPhase = LockActivationPhase::Enabling;
    m_diagnostics.record(
        QStringLiteral("lock.activation"),
        QStringLiteral("plugin_enable_started"),
        DiagnosticLog::Level::Debug,
        {{QStringLiteral("pass"), m_lockPluginDiscoveryPasses}});
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    m_lockPluginEnableProcess = process;
    const auto complete = [this, process] {
        if (m_lockPluginEnableProcess != process
            || m_lockActivationPhase != LockActivationPhase::Enabling)
            return;
        const QByteArray diagnostic = process->readAll();
        if (!diagnostic.isEmpty())
            qWarning().noquote() << QString::fromLocal8Bit(diagnostic).trimmed();
        abandonProcess(m_lockPluginEnableProcess);
        refreshLockIntegrationStatus();
        if (m_lockIntegrationInstalled) {
            finishLockActivation(true);
        } else if (m_lockPluginDiscoveryPasses < 3) {
            QTimer::singleShot(900, this, &GazeClient::startLockPluginRescan);
        } else {
            finishLockActivation(
                false,
                QStringLiteral("Face ID couldn’t be added to the lock screen. Try again."));
        }
    };
    connect(process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [complete](int, QProcess::ExitStatus) { complete(); },
            Qt::SingleShotConnection);
    connect(process, &QProcess::errorOccurred, this,
            [complete](QProcess::ProcessError) { complete(); },
            Qt::SingleShotConnection);
    process->start(m_lockPluginEnableCommand, {QString::fromLatin1(pluginId)});
}

void GazeClient::abandonProcess(QProcess *&process)
{
    if (!process)
        return;
    QProcess *orphan = process;
    process = nullptr;
    disconnect(orphan, nullptr, this, nullptr);
    if (orphan->state() == QProcess::NotRunning) {
        orphan->deleteLater();
        return;
    }
    orphan->setParent(nullptr);
    connect(orphan,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            orphan, &QObject::deleteLater,
            Qt::SingleShotConnection);
    orphan->kill();
}

void GazeClient::finishLockActivation(bool success, const QString &error)
{
    if (m_lockActivationPhase == LockActivationPhase::Idle)
        return;

    m_lockActivationDeadline.stop();
    abandonProcess(m_lockIntegrationProcess);
    abandonProcess(m_lockPluginEnableProcess);
    if (m_lockIntegrationPamFile) {
        delete m_lockIntegrationPamFile;
        m_lockIntegrationPamFile = nullptr;
    }
    m_lockPluginEnableCommand.clear();
    m_lockPluginRescanCommand.clear();
    m_lockPluginDiscoveryPasses = 0;
    m_lockActivationPhase = LockActivationPhase::Idle;
    m_lockIntegrationInstalling = false;
    refreshLockIntegrationStatus();
    m_lockIntegrationError = success && m_lockIntegrationInstalled
        ? QString() : error;
    m_diagnostics.record(
        QStringLiteral("lock.activation"),
        QStringLiteral("finished"),
        success && m_lockIntegrationInstalled
            ? DiagnosticLog::Level::Info : DiagnosticLog::Level::Error,
        {{QStringLiteral("success"), success && m_lockIntegrationInstalled},
         {QStringLiteral("installed"), m_lockIntegrationInstalled}});
    emit lockIntegrationChanged();
}

void GazeClient::onEnrollStatus(const QString &,
                                uint progress,
                                uint maximum,
                                bool done,
                                const QString &prompt,
                                double timeRemaining)
{
    m_diagnostics.record(
        QStringLiteral("enrollment.workflow"),
        QStringLiteral("status_changed"),
        done && prompt != QStringLiteral("completed")
            ? DiagnosticLog::Level::Error : DiagnosticLog::Level::Info,
        {{QStringLiteral("step"), static_cast<qint64>(progress)},
         {QStringLiteral("steps"), static_cast<qint64>(maximum)},
         {QStringLiteral("done"), done},
         {QStringLiteral("prompt"), prompt},
         {QStringLiteral("seconds_remaining"), timeRemaining}});
    const bool wasComplete = m_enrollmentComplete;
    m_enrollmentProgress = static_cast<int>(progress);
    m_enrollmentMaximum = static_cast<int>(maximum);
    m_enrollmentPrompt = prompt;
    if (timeRemaining > 0.0)
        m_enrollmentPrompt += QStringLiteral(" · %1s").arg(timeRemaining, 0, 'f', 1);

    if (done) {
        m_enrolling = false;
        m_enrollmentComplete = prompt == QStringLiteral("completed");
        if (m_enrollmentComplete) {
            recordEnrollmentOwnership(m_enrollmentFaceName);
            if (!wasComplete)
                playDing();
        }
        stopParallelPreview();
        releaseClaim();
        emit enrollingChanged();
    }
    emit enrollmentChanged();
}

void GazeClient::playDing()
{
    if (!m_dingFile) {
        const QByteArray contents = resourceContents(QStringLiteral(":/assets/ding.mp3"));
        if (contents.isEmpty())
            return;

        m_dingFile = new QTemporaryFile(
            QDir::tempPath() + QStringLiteral("/omarchy-face-id-ding.XXXXXX.mp3"),
            this);
        if (!m_dingFile->open()
            || m_dingFile->write(contents) != contents.size()
            || !m_dingFile->flush()) {
            delete m_dingFile;
            m_dingFile = nullptr;
            return;
        }
        m_dingFile->close();
    }

    QString player = QStandardPaths::findExecutable(QStringLiteral("pw-play"));
    QStringList arguments{m_dingFile->fileName()};
    if (player.isEmpty())
        player = QStandardPaths::findExecutable(QStringLiteral("paplay"));
    if (player.isEmpty()) {
        player = QStandardPaths::findExecutable(QStringLiteral("mpv"));
        arguments.prepend(QStringLiteral("--no-terminal"));
        arguments.prepend(QStringLiteral("--really-quiet"));
        arguments.prepend(QStringLiteral("--no-video"));
    }
    if (!player.isEmpty())
        QProcess::startDetached(player, arguments);
}

void GazeClient::onFaceStatus(const QString &status)
{
    m_diagnostics.record(
        QStringLiteral("enrollment.camera"),
        QStringLiteral("face_status_changed"),
        DiagnosticLog::Level::Debug,
        {{QStringLiteral("status"), status}});
    m_faceStatus = status;
    emit enrollmentChanged();
}

void GazeClient::onPreviewFrame(const QByteArray &jpeg)
{
    ++m_remotePreviewFrames;
    if (m_remotePreviewFrames == 1) {
        m_diagnostics.record(
            QStringLiteral("enrollment.preview"),
            QStringLiteral("first_sample_received"),
            DiagnosticLog::Level::Info,
            {{QStringLiteral("source"), QStringLiteral("gaze_dbus")},
             {QStringLiteral("bytes"), static_cast<qint64>(jpeg.size())}});
    }
    m_previewDataUrl = QStringLiteral("data:image/jpeg;base64,")
        + QString::fromLatin1(jpeg.toBase64());
    emit previewChanged();
}

void GazeClient::onParallelPreviewFrame(const QByteArray &jpeg)
{
    ++m_parallelPreviewFrames;
    if (m_parallelPreviewFrames == 1) {
        m_diagnostics.record(
            QStringLiteral("enrollment.preview"),
            QStringLiteral("first_sample_received"),
            DiagnosticLog::Level::Info,
            {{QStringLiteral("source"), QStringLiteral("pipewire_shared")},
             {QStringLiteral("bytes"), static_cast<qint64>(jpeg.size())}});
    }
    m_previewDataUrl = QStringLiteral("data:image/jpeg;base64,")
        + QString::fromLatin1(jpeg.toBase64());
    emit previewChanged();
}

bool GazeClient::startParallelPreview()
{
    m_diagnostics.record(QStringLiteral("enrollment.preview"),
                         QStringLiteral("shared_start_requested"));
    stopParallelPreview(true);
    m_lastPreviewFrameUsec.store(0, std::memory_order_relaxed);

    gst_init(nullptr, nullptr);
    GError *error = nullptr;
    m_parallelPreviewPipeline = gst_parse_launch(
        "pipewiresrc do-timestamp=true ! "
        "video/x-raw,pixel-aspect-ratio=1/1; image/jpeg ! "
        "decodebin ! "
        "videoconvert ! "
        "videoscale ! "
        "jpegenc quality=82 ! "
        "appsink name=preview-sink max-buffers=1 drop=true sync=false",
        &error);
    if (!m_parallelPreviewPipeline) {
        m_diagnostics.record(
            QStringLiteral("enrollment.preview"),
            QStringLiteral("shared_pipeline_create_failed"),
            DiagnosticLog::Level::Error);
        qWarning("Could not create shared PipeWire preview: %s",
                 error ? error->message : "unknown GStreamer error");
        g_clear_error(&error);
        return false;
    }

    GstElement *sinkElement = gst_bin_get_by_name(
        GST_BIN(m_parallelPreviewPipeline), "preview-sink");
    if (!sinkElement) {
        m_diagnostics.record(
            QStringLiteral("enrollment.preview"),
            QStringLiteral("shared_sink_missing"),
            DiagnosticLog::Level::Error);
        qWarning("Shared PipeWire preview has no frame sink");
        stopParallelPreview();
        return false;
    }

    GstAppSinkCallbacks callbacks{};
    callbacks.new_sample = [](GstAppSink *sink, gpointer userData) -> GstFlowReturn {
        auto *client = static_cast<GazeClient *>(userData);
        GstSample *sample = gst_app_sink_pull_sample(sink);
        if (!sample)
            return GST_FLOW_EOS;

        const qint64 now = g_get_monotonic_time();
        const qint64 last = client->m_lastPreviewFrameUsec.load(
            std::memory_order_relaxed);
        if (last > 0 && now - last < 80'000) {
            gst_sample_unref(sample);
            return GST_FLOW_OK;
        }
        client->m_lastPreviewFrameUsec.store(now, std::memory_order_relaxed);

        GstBuffer *buffer = gst_sample_get_buffer(sample);
        GstMapInfo map{};
        QByteArray jpeg;
        if (buffer && gst_buffer_map(buffer, &map, GST_MAP_READ)) {
            jpeg = QByteArray(reinterpret_cast<const char *>(map.data),
                              static_cast<qsizetype>(map.size));
            gst_buffer_unmap(buffer, &map);
        }
        gst_sample_unref(sample);

        if (!jpeg.isEmpty()) {
            QMetaObject::invokeMethod(
                client,
                [client, jpeg = std::move(jpeg)] {
                    if (client->m_parallelPreviewPipeline)
                        client->onParallelPreviewFrame(jpeg);
                },
                Qt::QueuedConnection);
        }
        return GST_FLOW_OK;
    };
    gst_app_sink_set_callbacks(GST_APP_SINK(sinkElement), &callbacks, this, nullptr);
    gst_object_unref(sinkElement);

    const GstStateChangeReturn stateChange = gst_element_set_state(
        m_parallelPreviewPipeline, GST_STATE_PLAYING);
    if (stateChange == GST_STATE_CHANGE_FAILURE) {
        m_diagnostics.record(
            QStringLiteral("enrollment.preview"),
            QStringLiteral("shared_start_failed"),
            DiagnosticLog::Level::Error,
            {{QStringLiteral("state_result"), static_cast<int>(stateChange)}});
        qWarning("Could not start shared PipeWire preview");
        stopParallelPreview();
        return false;
    }
    m_diagnostics.record(
        QStringLiteral("enrollment.preview"),
        QStringLiteral("shared_start_finished"),
        DiagnosticLog::Level::Info,
        {{QStringLiteral("state_result"), static_cast<int>(stateChange)}});
    return true;
}

void GazeClient::stopParallelPreview(bool clearFrame)
{
    if (m_parallelPreviewPipeline) {
        m_diagnostics.record(
            QStringLiteral("enrollment.preview"),
            QStringLiteral("shared_stopped"),
            DiagnosticLog::Level::Debug,
            {{QStringLiteral("samples"), m_parallelPreviewFrames}});
        gst_element_set_state(m_parallelPreviewPipeline, GST_STATE_NULL);
        gst_object_unref(m_parallelPreviewPipeline);
        m_parallelPreviewPipeline = nullptr;
    }
    if (clearFrame && !m_previewDataUrl.isEmpty()) {
        m_previewDataUrl.clear();
        emit previewChanged();
    }
}

void GazeClient::releaseClaim()
{
    if (!m_claimed)
        return;
    if (m_serviceAvailable) {
        auto iface = gazeInterface();
        iface.call(QDBus::NoBlock, QStringLiteral("Release"));
    }
    m_claimed = false;
}

void GazeClient::setError(const QString &message)
{
    if (m_errorMessage == message)
        return;
    m_errorMessage = message;
    emit errorChanged();
}

void GazeClient::scheduleThemeReload()
{
    m_themeReloadTimer.start();
}

void GazeClient::reloadTheme()
{
    const QString themeDirectory = m_themeRoot + QStringLiteral("/theme");
    const QString colorsPath = themeDirectory + QStringLiteral("/colors.toml");
    const QString themeNamePath = m_themeRoot + QStringLiteral("/theme.name");

    QFile colorsFile(colorsPath);
    if (!colorsFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        scheduleThemeReload();
        return;
    }

    const QString contents = QTextStream(&colorsFile).readAll();
    const QRegularExpression entry(
        QStringLiteral("(?m)^\\s*([A-Za-z0-9_-]+)\\s*=\\s*[\\\"']?(#[0-9A-Fa-f]{6,8})"));
    QHash<QString, QColor> colors;
    auto matchIterator = entry.globalMatch(contents);
    while (matchIterator.hasNext()) {
        const auto match = matchIterator.next();
        const QColor color(match.captured(2));
        if (color.isValid())
            colors.insert(match.captured(1), color);
    }

    bool changed = false;
    const auto apply = [&colors, &changed](const QString &key, QColor &target) {
        const auto candidate = colors.constFind(key);
        if (candidate != colors.cend() && candidate.value() != target) {
            target = candidate.value();
            changed = true;
        }
    };
    apply(QStringLiteral("background"), m_themeBackground);
    apply(QStringLiteral("dark_background"), m_themeDarkBackground);
    apply(QStringLiteral("darker_background"), m_themeDarkerBackground);
    apply(QStringLiteral("lighter_background"), m_themeLighterBackground);
    apply(QStringLiteral("foreground"), m_themeForeground);
    apply(QStringLiteral("muted"), m_themeMuted);
    apply(QStringLiteral("accent"), m_themeAccent);
    apply(QStringLiteral("orange"), m_themeOrange);
    apply(QStringLiteral("green"), m_themeGreen);
    apply(QStringLiteral("red"), m_themeRed);

    const auto watchedFiles = m_themeWatcher.files();
    if (!watchedFiles.isEmpty())
        m_themeWatcher.removePaths(watchedFiles);
    const auto watchedDirectories = m_themeWatcher.directories();
    if (!watchedDirectories.isEmpty())
        m_themeWatcher.removePaths(watchedDirectories);
    for (const auto &path : {m_themeRoot, themeDirectory}) {
        if (QFileInfo(path).isDir())
            m_themeWatcher.addPath(path);
    }
    for (const auto &path : {colorsPath, themeNamePath}) {
        if (QFileInfo(path).isFile())
            m_themeWatcher.addPath(path);
    }

    std::fprintf(stderr, "Omarchy theme loaded: %s\n",
                 m_themeAccent.name().toUtf8().constData());
    std::fflush(stderr);
    if (changed)
        emit themeChanged();
}
