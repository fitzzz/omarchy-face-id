// SPDX-License-Identifier: GPL-3.0-or-later

#include "GazeClient.h"

#include "CameraInventory.h"

#include <QCoreApplication>
#include <QCryptographicHash>
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
#include <QPointer>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QTemporaryFile>
#include <QTextStream>
#include <QUuid>
#include <QVersionNumber>

#include <gst/app/gstappsink.h>
#include <gst/gst.h>

#include <pwd.h>
#include <cstdio>
#include <fcntl.h>
#include <linux/fs.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace {
constexpr auto serviceName = "com.gundulabs.Gaze";
constexpr auto objectPath = "/com/gundulabs/Gaze";
constexpr auto interfaceName = "com.gundulabs.Gaze";
constexpr auto facePamPath = "/etc/pam.d/omarchy-face-id-lock";
constexpr auto pluginId = "fitzzz.face-id";
constexpr auto pluginVersionFile = ".omarchy-face-id-version";
constexpr auto gazeOwnershipValue = "omarchy-face-id:gaze-aur:gaze-bin\n";
constexpr auto legacyGazeOwnershipValue = "omarchy-face-id:gaze:0.2.12-1\n";

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

bool fileContainsGazeAuthRule(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;

    static const QRegularExpression rule(
        QStringLiteral("^\\s*auth\\s+sufficient\\s+pam_gaze\\.so\\s*$"));
    QTextStream stream(&file);
    while (!stream.atEnd()) {
        if (rule.match(stream.readLine()).hasMatch())
            return true;
    }
    return false;
}

QString elevationHelperSourcePath();
QString consentModuleSourcePath();

bool systemIntegrationIsReady()
{
    const QString ownershipRoot = qEnvironmentVariable(
        "OMARCHY_FACE_ID_OWNERSHIP_DIR", QStringLiteral("/var/lib/omarchy-face-id"));
    const QString ownershipReceipt = ownershipRoot + QStringLiteral("/gaze-installed");
    const bool gazeOwned = fileMatches(ownershipReceipt, QByteArray(gazeOwnershipValue))
        || fileMatches(ownershipReceipt, QByteArray(legacyGazeOwnershipValue));

    const QString sudoPam = qEnvironmentVariable(
        "OMARCHY_FACE_ID_SUDO_PAM_PATH", QStringLiteral("/etc/pam.d/sudo"));
    const QString faceIdPam = qEnvironmentVariable(
        "OMARCHY_FACE_ID_SUDO_FACE_PAM_PATH",
        QStringLiteral("/etc/pam.d/omarchy-face-id"));
    const QString polkitPam = qEnvironmentVariable(
        "OMARCHY_FACE_ID_POLKIT_PAM_PATH", QStringLiteral("/etc/pam.d/polkit-1"));
    const QString elevationTarget = qEnvironmentVariable(
        "OMARCHY_FACE_ID_ELEVATION_TARGET",
        QStringLiteral("/usr/libexec/omarchy-face-id-elevation"));
    const QString consentTarget = qEnvironmentVariable(
        "OMARCHY_FACE_ID_CONSENT_TARGET",
        QStringLiteral("/usr/lib/security/pam_omarchy_face_id_consent.so"));
    const QString verifierPam = qEnvironmentVariable(
        "OMARCHY_FACE_ID_VERIFY_PAM_PATH",
        QStringLiteral("/usr/lib/omarchy-face-id/pam.d/sudo"));
    const QString elevationSource = elevationHelperSourcePath();
    const QByteArray helperContents = resourceContents(elevationSource);
    const QByteArray consentContents = resourceContents(consentModuleSourcePath());

    QFile sudoFile(sudoPam);
    const QByteArray sudoContents = sudoFile.open(QIODevice::ReadOnly)
        ? sudoFile.readAll() : QByteArray();
    QFile faceIdFile(faceIdPam);
    const QByteArray faceIdContents = faceIdFile.open(QIODevice::ReadOnly)
        ? faceIdFile.readAll() : QByteArray();
    const QByteArray target = elevationTarget.toUtf8();
    const QByteArray userReceipt = QByteArrayLiteral(
        "omarchy-face-id:registered-user:1\n");
    const QString registration = ownershipRoot + QStringLiteral("/users/")
        + QString::number(getuid());
    const QByteArray expectedFaceIdContents = QByteArrayLiteral(
        "# Omarchy Face ID sudo authentication. Managed by Omarchy Face ID.\n"
        "auth [success=done auth_err=die default=ignore] "
        "pam_omarchy_face_id_consent.so helper=")
        + target
        + QByteArrayLiteral("\n");
    const QByteArray expectedVerifierContents = QByteArrayLiteral(
        "# Omarchy Face ID private face verification. Managed by Omarchy Face ID.\n"
        "auth [success=done ignore=ignore default=bad] pam_gaze.so\n"
        "auth required pam_deny.so\n"
        "account required pam_permit.so\n");
    const bool sudoReady = !helperContents.isEmpty() && !consentContents.isEmpty()
        && fileMatches(elevationTarget, helperContents)
        && fileMatches(consentTarget, consentContents)
        && fileMatches(verifierPam, expectedVerifierContents)
        && fileMatches(registration, userReceipt)
        && sudoContents.contains("# BEGIN Omarchy Face ID sudo\n")
        && sudoContents.contains(
            "auth include omarchy-face-id\n")
        && sudoContents.contains("# END Omarchy Face ID sudo\n")
        && faceIdContents == expectedFaceIdContents;
    return sudoReady && (!gazeOwned || !fileContainsGazeAuthRule(polkitPam));
}

QString bundledHelperSourcePath(const char *overrideVariable, const QString &fileName)
{
    const QString overridePath = qEnvironmentVariable(overrideVariable);
    const QString applicationDirectory = QCoreApplication::applicationDirPath();
    const QStringList candidates = overridePath.isEmpty()
        ? QStringList{
              applicationDirectory + QLatin1Char('/') + fileName,
              QDir::cleanPath(applicationDirectory
                              + QStringLiteral("/../libexec/") + fileName)}
        : QStringList{overridePath};

    for (const QString &candidate : candidates) {
        const QFileInfo info(candidate);
        if (info.isFile() && info.isReadable() && info.isExecutable()
            && !info.isSymLink())
            return candidate;
    }
    return {};
}

QString presenceHelperSourcePath()
{
    return bundledHelperSourcePath("OMARCHY_FACE_ID_PRESENCE_HELPER_PATH",
                                   QStringLiteral("omarchy-face-id-presence"));
}

QString elevationHelperSourcePath()
{
    return bundledHelperSourcePath("OMARCHY_FACE_ID_ELEVATION_HELPER_PATH",
                                   QStringLiteral("omarchy-face-id-elevation"));
}

QString consentModuleSourcePath()
{
    const QString overridePath = qEnvironmentVariable(
        "OMARCHY_FACE_ID_CONSENT_MODULE_PATH");
    const QString applicationDirectory = QCoreApplication::applicationDirPath();
    const QString fileName = QStringLiteral("pam_omarchy_face_id_consent.so");
    const QStringList candidates = overridePath.isEmpty()
        ? QStringList{
              applicationDirectory + QLatin1Char('/') + fileName,
              QDir::cleanPath(applicationDirectory
                              + QStringLiteral("/../lib/security/") + fileName)}
        : QStringList{overridePath};

    for (const QString &candidate : candidates) {
        const QFileInfo info(candidate);
        if (info.isFile() && !info.isSymLink())
            return info.absoluteFilePath();
    }
    return {};
}

QString systemInstallerSourcePath()
{
    const QString overridePath = qEnvironmentVariable(
        "OMARCHY_FACE_ID_SYSTEM_INSTALLER_PATH");
    const QString applicationDirectory = QCoreApplication::applicationDirPath();
    const QStringList candidates = overridePath.isEmpty()
        ? QStringList{QDir::cleanPath(
              applicationDirectory
              + QStringLiteral("/../share/omarchy-face-id/install-gaze-arch.sh"))}
        : QStringList{overridePath};
    for (const QString &candidate : candidates) {
        const QFileInfo info(candidate);
        if (info.isFile() && !info.isSymLink() && info.isExecutable())
            return info.absoluteFilePath();
    }
    return {};
}

bool trustedSystemPayload(const QString &path)
{
    const QFileInfo info(path);
    if (!info.isFile() || info.isSymLink())
        return false;
    const QStorageInfo storage(info.absolutePath());
    if (storage.isValid() && storage.isReady() && storage.isReadOnly())
        return true;
    const auto permissions = info.permissions();
    return info.ownerId() == 0
        && !(permissions & (QFileDevice::WriteGroup | QFileDevice::WriteOther));
}

QByteArray fileSha256(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QCryptographicHash digest(QCryptographicHash::Sha256);
    if (!digest.addData(&file))
        return {};
    return digest.result().toHex();
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

QString installedPluginVersion(const QString &pluginRoot)
{
    QFile receipt(pluginRoot + QLatin1Char('/')
                  + QString::fromLatin1(pluginVersionFile));
    if (receipt.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString::fromUtf8(receipt.readAll()).trimmed();

    QFile manifest(pluginRoot + QStringLiteral("/manifest.json"));
    if (!manifest.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(manifest.readAll());
    return document.isObject()
        ? document.object().value(QStringLiteral("version")).toString().trimmed()
        : QString();
}

bool isSemanticDowngrade(const QString &installed, const QString &candidate)
{
    const QVersionNumber installedVersion = QVersionNumber::fromString(installed);
    const QVersionNumber candidateVersion = QVersionNumber::fromString(candidate);
    return !installedVersion.isNull() && !candidateVersion.isNull()
        && QVersionNumber::compare(candidateVersion, installedVersion) < 0;
}

bool exchangePaths(const QString &first, const QString &second)
{
    const QByteArray firstPath = QFile::encodeName(first);
    const QByteArray secondPath = QFile::encodeName(second);
    return ::syscall(SYS_renameat2, AT_FDCWD, firstPath.constData(),
                     AT_FDCWD, secondPath.constData(), RENAME_EXCHANGE) == 0;
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
    : QObject(parent), m_theme(this)
{
    m_diagnostics.record(
        QStringLiteral("app.lifecycle"),
        QStringLiteral("session_started"),
        DiagnosticLog::Level::Info,
        {{QStringLiteral("app_version"), QStringLiteral(OMARCHY_FACE_ID_VERSION)},
         {QStringLiteral("log_schema_version"), 1}});
    ensureUserConfig();
    connect(&m_theme, &OmarchyTheme::changed, this, &GazeClient::themeChanged);
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
                if (m_installed && m_serviceAvailable && m_cameraSupportAvailable
                    && m_systemIntegrationReady) {
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
        recordActivationPhase(
            QStringLiteral("activation_deadline_reached"),
            DiagnosticLog::Level::Error,
            {{QStringLiteral("budget_ms"), m_lockActivationDeadline.interval()}});
        rollbackUserPluginActivation();
        finishLockActivation(
            false,
            QStringLiteral("Face ID setup timed out. Nothing changed; try again."));
    });
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
bool GazeClient::systemIntegrationReady() const
{
    return m_systemIntegrationReady;
}
bool GazeClient::existingEnrollment() const
{
    return QFileInfo::exists(enrollmentReceiptPath());
}
bool GazeClient::upgradeAvailable() const
{
    return existingEnrollment()
        && (!m_systemIntegrationReady || !m_lockIntegrationInstalled);
}
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
bool GazeClient::lockIntegrationActive() const { return m_lockIntegrationActive; }
bool GazeClient::lockIntegrationInstalling() const { return m_lockIntegrationInstalling; }
QString GazeClient::lockIntegrationStatus() const
{
    switch (m_lockActivationPhase) {
    case LockActivationPhase::Authorizing:
        return QStringLiteral("Preparing Face ID…");
    case LockActivationPhase::Rescanning:
        return QStringLiteral("Registering Face ID…");
    case LockActivationPhase::Enabling:
        return QStringLiteral("Enabling Face ID…");
    case LockActivationPhase::Reloading:
        return QStringLiteral("Reloading Omarchy Shell…");
    case LockActivationPhase::Verifying:
        return m_lockRestartAttempted
            ? QStringLiteral("Waiting for Omarchy Shell…")
            : QStringLiteral("Checking Face ID…");
    case LockActivationPhase::Idle:
        return QStringLiteral("Preparing update…");
    }
    return QStringLiteral("Preparing update…");
}
QString GazeClient::lockIntegrationError() const { return m_lockIntegrationError; }
QColor GazeClient::themeBackground() const { return m_theme.background(); }
QColor GazeClient::themeDarkBackground() const { return m_theme.darkBackground(); }
QColor GazeClient::themeDarkerBackground() const { return m_theme.darkerBackground(); }
QColor GazeClient::themeLighterBackground() const { return m_theme.lighterBackground(); }
QColor GazeClient::themeForeground() const { return m_theme.foreground(); }
QColor GazeClient::themeMuted() const { return m_theme.muted(); }
QColor GazeClient::themeAccent() const { return m_theme.accent(); }
QColor GazeClient::themeOrange() const { return m_theme.orange(); }
QColor GazeClient::themeGreen() const { return m_theme.green(); }
QColor GazeClient::themeRed() const { return m_theme.red(); }

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
    const bool wasSystemIntegrationReady = m_systemIntegrationReady;
    const bool wasParallelPreviewAvailable = m_parallelPreviewAvailable;

    m_installed = QFileInfo(qEnvironmentVariable(
        "OMARCHY_FACE_ID_GAZE_PATH", QStringLiteral("/usr/bin/gaze"))).isExecutable();
    m_cameraSupportAvailable = jpegDecoderAvailable();
    m_systemIntegrationReady = systemIntegrationIsReady();
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
        || wasSystemIntegrationReady != m_systemIntegrationReady
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
             {QStringLiteral("system_integration_ready"),
              m_systemIntegrationReady},
             {QStringLiteral("parallel_preview_eligible"),
              m_parallelPreviewAvailable}});
        emit availabilityChanged();
        emit upgradeChanged();
    }
}

void GazeClient::installFaceSetup()
{
    startFaceSetup(false);
}

void GazeClient::installFaceSetupQuietly()
{
    startFaceSetup(true);
}

void GazeClient::startFaceSetup(bool quiet)
{
    if (m_faceSetupInstalling)
        return;

    m_diagnostics.record(QStringLiteral("dependency.gaze"),
                         QStringLiteral("setup_requested"));

    refresh();
    if (m_installed && m_serviceAvailable && m_cameraSupportAvailable
        && m_systemIntegrationReady) {
        m_faceSetupError.clear();
        emit faceSetupChanged();
        return;
    }

    const QString terminalLauncher = quiet ? QString() : QStandardPaths::findExecutable(
        QStringLiteral("omarchy-launch-terminal"));
    const QString installerPath = systemInstallerSourcePath();
    const QString elevationHelper = elevationHelperSourcePath();
    const QString consentModule = consentModuleSourcePath();
    const QByteArray installerContents = resourceContents(
        QStringLiteral(":/scripts/install-gaze-arch.sh"));
    if ((!quiet && terminalLauncher.isEmpty()) || installerPath.isEmpty()
        || elevationHelper.isEmpty() || consentModule.isEmpty()
        || installerContents.isEmpty()
        || !fileMatches(installerPath, installerContents)) {
        m_faceSetupError = QStringLiteral(
            "The Face ID system installer is unavailable.");
        emit faceSetupChanged();
        return;
    }

    if (!trustedSystemPayload(installerPath)
        || !trustedSystemPayload(elevationHelper)
        || !trustedSystemPayload(consentModule)) {
        m_faceSetupError = QStringLiteral(
            "System setup must be run from the original Face ID AppImage.");
        emit faceSetupChanged();
        return;
    }

    const QByteArray helperSha256 = fileSha256(elevationHelper);
    const QByteArray consentSha256 = fileSha256(consentModule);
    if (helperSha256.isEmpty() || consentSha256.isEmpty()) {
        m_faceSetupError = QStringLiteral(
            "Could not verify the Face ID system installer.");
        emit faceSetupChanged();
        return;
    }

    QTemporaryFile status(
        QDir::tempPath() + QStringLiteral("/omarchy-face-id-install.XXXXXX"));
    status.setAutoRemove(false);
    if (!status.open()) {
        m_faceSetupError = QStringLiteral("Could not start Face ID system setup.");
        emit faceSetupChanged();
        return;
    }
    m_faceSetupStatusPath = status.fileName();
    status.close();
    QFile::remove(m_faceSetupStatusPath);

    QStringList installerArguments{
        installerPath,
        QStringLiteral("--elevation-helper"), elevationHelper,
        QStringLiteral("--elevation-sha256"),
        QString::fromLatin1(helperSha256),
        QStringLiteral("--consent-module"), consentModule,
        QStringLiteral("--consent-sha256"),
        QString::fromLatin1(consentSha256),
        QStringLiteral("--status-file"), m_faceSetupStatusPath};

    bool launched = false;
    if (quiet) {
        auto *process = new QProcess(this);
        process->setInputChannelMode(QProcess::ForwardedInputChannel);
        process->setProcessChannelMode(QProcess::ForwardedChannels);
        m_faceSetupProcess = process;
        connect(process, &QProcess::errorOccurred, this,
                [this, process](QProcess::ProcessError) {
                    if (m_faceSetupProcess != process)
                        return;
                    m_faceSetupProcess = nullptr;
                    process->deleteLater();
                    finishFaceSetup(
                        false,
                        QStringLiteral("Could not run Face ID system setup."));
                },
                Qt::SingleShotConnection);
        connect(process,
                qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                this,
                [this, process](int exitCode, QProcess::ExitStatus exitStatus) {
                    if (m_faceSetupProcess != process)
                        return;
                    m_faceSetupProcess = nullptr;
                    process->deleteLater();
                    if (exitStatus != QProcess::NormalExit || exitCode != 0) {
                        finishFaceSetup(
                            false,
                            QStringLiteral("Face ID system setup did not finish."));
                    }
                },
                Qt::SingleShotConnection);
        process->start(QStringLiteral("/usr/bin/bash"), installerArguments);
        launched = true;
    } else {
        installerArguments.insert(1, QStringLiteral("--wizard"));
        installerArguments.prepend(QStringLiteral("/usr/bin/bash"));
        qint64 installerPid = 0;
        launched = QProcess::startDetached(terminalLauncher,
                                           installerArguments,
                                           QString(), &installerPid);
    }
    if (!launched) {
        m_faceSetupStatusPath.clear();
        m_faceSetupError = QStringLiteral(
            "Could not open the Face ID system installer.");
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
    m_lockIntegrationActive = false;
    m_lockRestartAttempted = false;
    m_lockRestartVerificationElapsed.invalidate();
    m_lockPluginRoot.clear();
    m_lockPluginBackupRoot.clear();
    m_lockActivationElapsed.start();
    m_lockPhaseElapsed.start();

    const QString configRoot = qEnvironmentVariable(
        "OMARCHY_FACE_ID_CONFIG_ROOT",
        QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation));
    const QString pluginRoot = configRoot
        + QStringLiteral("/omarchy/plugins/") + QString::fromLatin1(pluginId);
    const QString installedVersion = installedPluginVersion(pluginRoot);
    const QString candidateVersion = QStringLiteral(OMARCHY_FACE_ID_VERSION);
    if (!qEnvironmentVariableIsSet("OMARCHY_FACE_ID_ALLOW_DOWNGRADE")
        && isSemanticDowngrade(installedVersion, candidateVersion)) {
        m_lockIntegrationError = QStringLiteral(
            "A newer Face ID version is already installed. It was left unchanged.");
        m_diagnostics.record(
            QStringLiteral("lock.activation"),
            QStringLiteral("downgrade_blocked"),
            DiagnosticLog::Level::Error,
            {{QStringLiteral("installed_version"), installedVersion},
             {QStringLiteral("candidate_version"), candidateVersion}});
        emit lockIntegrationChanged();
        emit lockIntegrationActivationFinished(lockIntegrationStateMatches(), false);
        return;
    }
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
        m_lockActivationDeadline.start(configuredTimeout > 0 ? configuredTimeout : 15000);
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
    m_lockActivationDeadline.start(configuredTimeout > 0 ? configuredTimeout : 15000);
    m_lockIntegrationInstalling = true;
    m_lockActivationPhase = LockActivationPhase::Authorizing;
    emit lockIntegrationChanged();

    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    m_lockIntegrationProcess = process;
    m_lockPhaseElapsed.restart();
    recordActivationPhase(QStringLiteral("pam_authorization_started"),
                          DiagnosticLog::Level::Debug);
    connect(process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this, process](int exitCode, QProcess::ExitStatus exitStatus) {
                if (m_lockIntegrationProcess != process
                    || m_lockActivationPhase != LockActivationPhase::Authorizing)
                    return;
                const QByteArray diagnostic = process->readAll();
                if (!diagnostic.isEmpty())
                    qWarning().noquote() << QString::fromLocal8Bit(diagnostic).trimmed();
                m_lockIntegrationProcess = nullptr;
                process->deleteLater();
                recordActivationPhase(
                    QStringLiteral("pam_authorization_finished"),
                    exitStatus == QProcess::NormalExit && exitCode == 0
                        ? DiagnosticLog::Level::Info : DiagnosticLog::Level::Error,
                    {{QStringLiteral("exit_code"), exitCode}});
                continueLockIntegrationInstall();
            },
            Qt::SingleShotConnection);
    connect(process, &QProcess::errorOccurred, this,
            [this, process](QProcess::ProcessError) {
                if (m_lockIntegrationProcess != process
                    || m_lockActivationPhase != LockActivationPhase::Authorizing)
                    return;
                abandonProcess(m_lockIntegrationProcess);
                recordActivationPhase(QStringLiteral("pam_authorization_finished"),
                                      DiagnosticLog::Level::Error,
                                      {{QStringLiteral("exit_code"), -1}});
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
    const int authorizationTimeout = qEnvironmentVariableIntValue(
        "OMARCHY_FACE_ID_AUTH_TIMEOUT_MS");
    const QPointer<QProcess> guarded(process);
    QTimer::singleShot(authorizationTimeout > 0 ? authorizationTimeout : 10000,
                       this, [this, guarded, authorizationTimeout] {
        if (!guarded || guarded != m_lockIntegrationProcess
            || guarded->state() == QProcess::NotRunning)
            return;
        recordActivationPhase(
            QStringLiteral("command_deadline_reached"),
            DiagnosticLog::Level::Error,
            {{QStringLiteral("command"), QStringLiteral("pam_authorization")},
             {QStringLiteral("timeout_ms"),
              authorizationTimeout > 0 ? authorizationTimeout : 10000}});
        guarded->kill();
    });
}

void GazeClient::refreshLockIntegrationStatus()
{
    const bool installed = lockIntegrationStateMatches();

    if (installed != m_lockIntegrationInstalled) {
        m_lockIntegrationInstalled = installed;
        emit lockIntegrationChanged();
        emit upgradeChanged();
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
            pluginRoot + QStringLiteral("/LockState.js"),
            resourceContents(QStringLiteral(":/integration/omarchy-plugin/LockState.js")))
        && fileMatches(
            pluginRoot + QStringLiteral("/FaceIdIndicator.qml"),
            resourceContents(QStringLiteral(
                ":/integration/omarchy-plugin/FaceIdIndicator.qml")))
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
        && fileMatches(pluginRoot + QLatin1Char('/')
                           + QString::fromLatin1(pluginVersionFile),
                       QByteArray(OMARCHY_FACE_ID_VERSION) + '\n')
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
        emit upgradeChanged();
    }
}

bool GazeClient::stageAndActivateUserPlugin(QString *error)
{
    const QString configRoot = qEnvironmentVariable(
        "OMARCHY_FACE_ID_CONFIG_ROOT",
        QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation));
    const QString pluginsRoot = configRoot + QStringLiteral("/omarchy/plugins");
    const QString transactionRoot = configRoot
        + QStringLiteral("/omarchy/.face-id-transactions");
    const QString pluginRoot = pluginsRoot + QLatin1Char('/')
        + QString::fromLatin1(pluginId);

    if (QFileInfo(pluginRoot).isSymLink()) {
        *error = QStringLiteral("The Face ID plugin folder is a symbolic link. It was left unchanged.");
        return false;
    }
    if (!QDir().mkpath(pluginsRoot) || !QDir().mkpath(transactionRoot)) {
        *error = QStringLiteral("Could not create the Omarchy plugin folder.");
        return false;
    }

    const QString suffix = QUuid::createUuid().toString(QUuid::Id128);
    const QString stagedRoot = transactionRoot + QStringLiteral("/stage-")
        + suffix;
    if (!QDir().mkpath(stagedRoot)) {
        *error = QStringLiteral("Could not stage the Omarchy Face ID plugin.");
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
    const QByteArray version = QByteArray(OMARCHY_FACE_ID_VERSION) + '\n';

    const bool staged = writeResource(
               QStringLiteral(":/integration/omarchy-plugin/Service.qml"),
               stagedRoot + QStringLiteral("/Service.qml"), readable)
        && writeResource(
            QStringLiteral(":/integration/omarchy-plugin/LockState.js"),
            stagedRoot + QStringLiteral("/LockState.js"), readable)
        && writeResource(
            QStringLiteral(":/integration/omarchy-plugin/FaceIdIndicator.qml"),
            stagedRoot + QStringLiteral("/FaceIdIndicator.qml"), readable)
        && writeResource(
            QStringLiteral(":/integration/omarchy-plugin/manifest.json"),
            stagedRoot + QStringLiteral("/manifest.json"), readable)
        && writeResource(
            QStringLiteral(":/assets/ding.mp3"),
            stagedRoot + QStringLiteral("/ding.mp3"), readable)
        && writeResource(
            QStringLiteral(":/integration/omarchy-plugin/log-event.sh"),
            stagedRoot + QStringLiteral("/log-event.sh"), executable)
        && writeContents(
            presenceHelper,
            stagedRoot + QStringLiteral("/presence-watcher"), executable)
        && writeContents(version,
                         stagedRoot + QLatin1Char('/')
                             + QString::fromLatin1(pluginVersionFile),
                         readable);
    if (!staged) {
        QDir(stagedRoot).removeRecursively();
        return false;
    }

    const bool validated = fileMatches(
            stagedRoot + QStringLiteral("/Service.qml"),
            resourceContents(QStringLiteral(":/integration/omarchy-plugin/Service.qml")))
        && fileMatches(stagedRoot + QStringLiteral("/LockState.js"),
                       resourceContents(QStringLiteral(":/integration/omarchy-plugin/LockState.js")))
        && fileMatches(
            stagedRoot + QStringLiteral("/FaceIdIndicator.qml"),
            resourceContents(QStringLiteral(
                ":/integration/omarchy-plugin/FaceIdIndicator.qml")))
        && fileMatches(stagedRoot + QStringLiteral("/manifest.json"),
                       resourceContents(QStringLiteral(":/integration/omarchy-plugin/manifest.json")))
        && fileMatches(stagedRoot + QStringLiteral("/ding.mp3"),
                       resourceContents(QStringLiteral(":/assets/ding.mp3")))
        && fileMatches(stagedRoot + QStringLiteral("/log-event.sh"),
                       resourceContents(QStringLiteral(":/integration/omarchy-plugin/log-event.sh")))
        && fileMatches(stagedRoot + QStringLiteral("/presence-watcher"), presenceHelper)
        && fileMatches(stagedRoot + QLatin1Char('/')
                           + QString::fromLatin1(pluginVersionFile), version);
    if (!validated) {
        QDir(stagedRoot).removeRecursively();
        *error = QStringLiteral("The staged Face ID plugin did not validate.");
        return false;
    }

    const bool replacingExisting = QFileInfo::exists(pluginRoot);
    const bool activated = replacingExisting
        ? exchangePaths(stagedRoot, pluginRoot)
        : QDir().rename(stagedRoot, pluginRoot);
    if (!activated) {
        QDir(stagedRoot).removeRecursively();
        *error = QStringLiteral("Could not activate the staged Face ID plugin.");
        return false;
    }

    m_lockPluginRoot = pluginRoot;
    // RENAME_EXCHANGE leaves the complete prior plugin at the staging path.
    m_lockPluginBackupRoot = replacingExisting ? stagedRoot : QString();
    recordActivationPhase(
        QStringLiteral("plugin_files_activated"), DiagnosticLog::Level::Info,
        {{QStringLiteral("backup_present"), !m_lockPluginBackupRoot.isEmpty()},
         {QStringLiteral("version"), QStringLiteral(OMARCHY_FACE_ID_VERSION)}});
    return true;
}

void GazeClient::commitUserPluginActivation()
{
    if (!m_lockPluginBackupRoot.isEmpty())
        QDir(m_lockPluginBackupRoot).removeRecursively();
    m_lockPluginBackupRoot.clear();
    m_lockPluginRoot.clear();
}

void GazeClient::rollbackUserPluginActivation()
{
    if (m_lockPluginRoot.isEmpty())
        return;
    const bool hadPrevious = !m_lockPluginBackupRoot.isEmpty();
    const bool restored = hadPrevious
        ? exchangePaths(m_lockPluginBackupRoot, m_lockPluginRoot)
        : QDir(m_lockPluginRoot).removeRecursively();
    if (restored && hadPrevious)
        QDir(m_lockPluginBackupRoot).removeRecursively();
    recordActivationPhase(
        QStringLiteral("plugin_files_rolled_back"),
        restored ? DiagnosticLog::Level::Info : DiagnosticLog::Level::Error,
        {{QStringLiteral("restored_previous"), restored && hadPrevious}});
    m_lockPluginBackupRoot.clear();
    m_lockPluginRoot.clear();
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

    // Build and validate a complete sibling directory, then cross the watched
    // activation boundary with one rename after authorization has finished.
    QString pluginError;
    if (!stageAndActivateUserPlugin(&pluginError)) {
        finishLockActivation(false, pluginError);
        return;
    }

    m_lockPluginRescanCommand = QStandardPaths::findExecutable(
        QStringLiteral("omarchy-shell"));
    m_lockPluginEnableCommand = QStandardPaths::findExecutable(
        QStringLiteral("omarchy-plugin-enable"));
    m_lockShellRestartCommand = QStandardPaths::findExecutable(
        QStringLiteral("omarchy-restart-shell"));
    if (m_lockPluginRescanCommand.isEmpty() || m_lockPluginEnableCommand.isEmpty()) {
        rollbackUserPluginActivation();
        finishLockActivation(
            false,
            QStringLiteral("Face ID couldn’t be added to the lock screen. Try again."));
        return;
    }

    m_lockPluginDiscoveryElapsed.start();
    startLockPluginRescan();
}

void GazeClient::startLockPluginRescan()
{
    if (!m_lockIntegrationInstalling || m_lockPluginRescanCommand.isEmpty()
        || m_lockPluginEnableProcess)
        return;

    m_lockActivationPhase = LockActivationPhase::Rescanning;
    m_lockPhaseElapsed.restart();
    emit lockIntegrationChanged();
    recordActivationPhase(QStringLiteral("plugin_rescan_started"),
                          DiagnosticLog::Level::Debug);
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    m_lockPluginEnableProcess = process;
    connect(process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this, process](int exitCode, QProcess::ExitStatus exitStatus) {
                if (m_lockPluginEnableProcess != process
                    || m_lockActivationPhase != LockActivationPhase::Rescanning)
                    return;
                m_lockPluginEnableProcess = nullptr;
                process->deleteLater();
                recordActivationPhase(
                    QStringLiteral("plugin_rescan_finished"),
                    exitStatus == QProcess::NormalExit && exitCode == 0
                        ? DiagnosticLog::Level::Info : DiagnosticLog::Level::Error,
                    {{QStringLiteral("exit_code"), exitCode}});
                startLockPluginEnable();
            },
            Qt::SingleShotConnection);
    connect(process, &QProcess::errorOccurred, this,
            [this, process](QProcess::ProcessError) {
                if (m_lockPluginEnableProcess != process
                    || m_lockActivationPhase != LockActivationPhase::Rescanning)
                    return;
                abandonProcess(m_lockPluginEnableProcess);
                recordActivationPhase(QStringLiteral("plugin_rescan_finished"),
                                      DiagnosticLog::Level::Error,
                                      {{QStringLiteral("exit_code"), -1}});
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
    m_lockPhaseElapsed.restart();
    emit lockIntegrationChanged();
    recordActivationPhase(QStringLiteral("plugin_enable_started"),
                          DiagnosticLog::Level::Debug);
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    m_lockPluginEnableProcess = process;
    const auto complete = [this, process](int exitCode,
                                          QProcess::ExitStatus exitStatus) {
        if (m_lockPluginEnableProcess != process
            || m_lockActivationPhase != LockActivationPhase::Enabling)
            return;
        const QByteArray diagnostic = process->readAll();
        if (!diagnostic.isEmpty())
            qWarning().noquote() << QString::fromLocal8Bit(diagnostic).trimmed();
        m_lockPluginEnableProcess = nullptr;
        process->deleteLater();
        recordActivationPhase(
            QStringLiteral("plugin_enable_finished"),
            exitStatus == QProcess::NormalExit && exitCode == 0
                ? DiagnosticLog::Level::Info : DiagnosticLog::Level::Error,
            {{QStringLiteral("exit_code"), exitCode}});
        // rescanPlugins acknowledges the request before the asynchronous
        // registry scan completes. Keep enabling until discovery catches up;
        // a restarted shell also needs the enable operation, not just status.
        if (exitStatus != QProcess::NormalExit || exitCode != 0) {
            const int configured = qEnvironmentVariableIntValue(
                m_lockRestartAttempted
                    ? "OMARCHY_FACE_ID_FALLBACK_VERIFY_TIMEOUT_MS"
                    : "OMARCHY_FACE_ID_DISCOVERY_TIMEOUT_MS");
            const int budget = configured > 0 ? configured
                : (m_lockRestartAttempted ? 30000 : 3000);
            const qint64 elapsed = m_lockRestartAttempted
                ? m_lockRestartVerificationElapsed.elapsed()
                : m_lockPluginDiscoveryElapsed.elapsed();
            if (elapsed < budget) {
                QTimer::singleShot(100, this, [this] {
                    if (m_lockIntegrationInstalling
                        && m_lockActivationPhase == LockActivationPhase::Enabling
                        && !m_lockPluginEnableProcess)
                        startLockPluginEnable();
                });
                return;
            }
        }
        startLockShellVerification();
    };
    connect(process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            complete,
            Qt::SingleShotConnection);
    connect(process, &QProcess::errorOccurred, this,
            [complete](QProcess::ProcessError) {
                complete(-1, QProcess::CrashExit);
            },
            Qt::SingleShotConnection);
    process->start(m_lockPluginEnableCommand, {QString::fromLatin1(pluginId)});
    armProcessDeadline(
        process, QStringLiteral("plugin_enable"),
        qEnvironmentVariableIntValue("OMARCHY_FACE_ID_COMMAND_TIMEOUT_MS") > 0
            ? qEnvironmentVariableIntValue("OMARCHY_FACE_ID_COMMAND_TIMEOUT_MS")
            : 1500);
}

void GazeClient::startLockShellRestart()
{
    if (!m_lockIntegrationInstalling || m_lockRestartAttempted
        || m_lockShellRestartCommand.isEmpty() || m_lockPluginEnableProcess)
        return;

    m_lockRestartAttempted = true;
    m_lockActivationPhase = LockActivationPhase::Reloading;
    m_lockPhaseElapsed.restart();
    m_lockRestartVerificationElapsed.start();
    emit lockIntegrationChanged();
    // A shell restart owns the desktop bar, workspace controls, notifications,
    // and lock screen. Once dispatched it must outlive this updater and must
    // never be killed by an application deadline.
    m_lockActivationDeadline.stop();
    recordActivationPhase(QStringLiteral("shell_restart_started"),
                          DiagnosticLog::Level::Debug);

    const bool dispatched = QProcess::startDetached(m_lockShellRestartCommand);
    recordActivationPhase(
        QStringLiteral("shell_restart_dispatched"),
        dispatched ? DiagnosticLog::Level::Info : DiagnosticLog::Level::Error,
        {{QStringLiteral("success"), dispatched}});
    if (!dispatched) {
        rollbackUserPluginActivation();
        finishLockActivation(
            false, QStringLiteral("Omarchy couldn’t restart. Nothing changed."));
        return;
    }

    QTimer::singleShot(200, this, [this] {
        if (m_lockIntegrationInstalling
            && m_lockActivationPhase == LockActivationPhase::Reloading)
            startLockPluginEnable();
    });
}

void GazeClient::startLockShellVerification()
{
    if (!m_lockIntegrationInstalling || m_lockPluginRescanCommand.isEmpty()
        || m_lockPluginEnableProcess)
        return;

    m_lockActivationPhase = LockActivationPhase::Verifying;
    m_lockPhaseElapsed.restart();
    emit lockIntegrationChanged();
    recordActivationPhase(
        QStringLiteral("shell_verification_started"),
        DiagnosticLog::Level::Debug,
        {{QStringLiteral("after_restart"), m_lockRestartAttempted}});

    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    m_lockPluginEnableProcess = process;
    const auto complete = [this, process](int exitCode,
                                          QProcess::ExitStatus exitStatus) {
        if (m_lockPluginEnableProcess != process
            || m_lockActivationPhase != LockActivationPhase::Verifying)
            return;
        const QJsonDocument response = QJsonDocument::fromJson(process->readAll());
        const QJsonObject status = response.object();
        const bool ready = exitStatus == QProcess::NormalExit
            && exitCode == 0 && response.isObject()
            && status.value(QStringLiteral("compatible")).toBool()
            && status.value(QStringLiteral("pamConfigured")).toBool();
        m_lockPluginEnableProcess = nullptr;
        process->deleteLater();
        recordActivationPhase(
            QStringLiteral("shell_verification_finished"),
            ready ? DiagnosticLog::Level::Info : DiagnosticLog::Level::Error,
            {{QStringLiteral("success"), ready},
             {QStringLiteral("exit_code"), exitCode},
             {QStringLiteral("after_restart"), m_lockRestartAttempted}});
        if (ready) {
            m_lockIntegrationActive = true;
            commitUserPluginActivation();
            finishLockActivation(true);
        } else if (!m_lockRestartAttempted
                   && !m_lockShellRestartCommand.isEmpty()) {
            startLockShellRestart();
        } else if (m_lockRestartVerificationElapsed.isValid()) {
            const int configured = qEnvironmentVariableIntValue(
                "OMARCHY_FACE_ID_FALLBACK_VERIFY_TIMEOUT_MS");
            const int readinessBudget = configured > 0 ? configured : 30000;
            if (m_lockRestartVerificationElapsed.elapsed() < readinessBudget) {
                QTimer::singleShot(200, this, [this] {
                    if (m_lockIntegrationInstalling
                        && m_lockActivationPhase
                            == LockActivationPhase::Verifying
                        && !m_lockPluginEnableProcess)
                        startLockShellVerification();
                });
                return;
            }
            rollbackUserPluginActivation();
            finishLockActivation(
                false,
                QStringLiteral("Update couldn’t finish. Omarchy is still running."));
        } else {
            rollbackUserPluginActivation();
            finishLockActivation(
                false,
                QStringLiteral("Update couldn’t finish. Try again."));
        }
    };
    connect(process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            complete,
            Qt::SingleShotConnection);
    connect(process, &QProcess::errorOccurred, this,
            [complete](QProcess::ProcessError) {
                complete(-1, QProcess::CrashExit);
            },
            Qt::SingleShotConnection);
    process->start(m_lockPluginRescanCommand,
                   {QStringLiteral("face-id"), QStringLiteral("status")});
    const int configured = qEnvironmentVariableIntValue(
        m_lockRestartAttempted ? "OMARCHY_FACE_ID_FALLBACK_VERIFY_TIMEOUT_MS"
                               : "OMARCHY_FACE_ID_VERIFY_TIMEOUT_MS");
    armProcessDeadline(process, QStringLiteral("shell_verification"),
                       configured > 0 ? configured
                                      : (m_lockRestartAttempted ? 4000 : 1800));
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

void GazeClient::armProcessDeadline(QProcess *process,
                                    const QString &command,
                                    int timeoutMs)
{
    const QPointer<QProcess> guarded(process);
    QTimer::singleShot(timeoutMs, this, [this, guarded, command, timeoutMs] {
        if (!guarded || guarded != m_lockPluginEnableProcess
            || guarded->state() == QProcess::NotRunning)
            return;
        recordActivationPhase(
            QStringLiteral("command_deadline_reached"),
            DiagnosticLog::Level::Error,
            {{QStringLiteral("command"), command},
             {QStringLiteral("timeout_ms"), timeoutMs}});
        guarded->kill();
    });
}

void GazeClient::recordActivationPhase(const QString &event,
                                       DiagnosticLog::Level level,
                                       const QJsonObject &fields)
{
    QJsonObject timedFields = fields;
    timedFields.insert(QStringLiteral("elapsed_ms"),
                       m_lockActivationElapsed.isValid()
                           ? m_lockActivationElapsed.elapsed() : 0);
    timedFields.insert(QStringLiteral("phase_ms"),
                       m_lockPhaseElapsed.isValid()
                           ? m_lockPhaseElapsed.elapsed() : 0);
    m_diagnostics.record(QStringLiteral("lock.activation"), event, level,
                         timedFields);
}

void GazeClient::finishLockActivation(bool success, const QString &error)
{
    if (m_lockActivationPhase == LockActivationPhase::Idle)
        return;

    m_lockActivationDeadline.stop();
    m_lockRestartVerificationElapsed.invalidate();
    abandonProcess(m_lockIntegrationProcess);
    abandonProcess(m_lockPluginEnableProcess);
    if (m_lockIntegrationPamFile) {
        delete m_lockIntegrationPamFile;
        m_lockIntegrationPamFile = nullptr;
    }
    m_lockPluginEnableCommand.clear();
    m_lockPluginRescanCommand.clear();
    m_lockShellRestartCommand.clear();
    if (!success)
        rollbackUserPluginActivation();
    m_lockActivationPhase = LockActivationPhase::Idle;
    m_lockIntegrationInstalling = false;
    refreshLockIntegrationStatus();
    const bool activated = success && m_lockIntegrationInstalled
        && m_lockIntegrationActive;
    m_lockIntegrationError = activated
        ? QString() : error;
    recordActivationPhase(
        QStringLiteral("finished"),
        activated
            ? DiagnosticLog::Level::Info : DiagnosticLog::Level::Error,
        {{QStringLiteral("success"), activated},
         {QStringLiteral("files_installed"), m_lockIntegrationInstalled},
         {QStringLiteral("live_active"), m_lockIntegrationActive},
         {QStringLiteral("used_restart_fallback"), m_lockRestartAttempted}});
    emit lockIntegrationChanged();
    emit lockIntegrationActivationFinished(m_lockIntegrationInstalled, activated);
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
