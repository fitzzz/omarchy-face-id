// SPDX-License-Identifier: GPL-3.0-or-later

#include "GazeClient.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QTextStream>

#include <pwd.h>
#include <cstdio>
#include <unistd.h>

namespace {
constexpr auto serviceName = "com.gundulabs.Gaze";
constexpr auto objectPath = "/com/gundulabs/Gaze";
constexpr auto interfaceName = "com.gundulabs.Gaze";

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
    m_themeRoot = qEnvironmentVariable("OMARCHY_FACE_UNLOCK_THEME_ROOT",
                                       QDir::homePath()
                                           + QStringLiteral("/.local/state/omarchy/current"));
    m_themeReloadTimer.setSingleShot(true);
    m_themeReloadTimer.setInterval(40);
    connect(&m_themeReloadTimer, &QTimer::timeout, this, &GazeClient::reloadTheme);
    connect(&m_themeWatcher, &QFileSystemWatcher::fileChanged,
            this, &GazeClient::scheduleThemeReload);
    connect(&m_themeWatcher, &QFileSystemWatcher::directoryChanged,
            this, &GazeClient::scheduleThemeReload);
    reloadTheme();

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
}

GazeClient::~GazeClient()
{
    releaseClaim();
}

bool GazeClient::installed() const { return m_installed; }
bool GazeClient::serviceAvailable() const { return m_serviceAvailable; }
bool GazeClient::cameraAvailable() const { return m_cameraAvailable; }
bool GazeClient::enrolling() const { return m_enrolling; }
bool GazeClient::enrollmentComplete() const { return m_enrollmentComplete; }
int GazeClient::enrollmentProgress() const { return m_enrollmentProgress; }
int GazeClient::enrollmentMaximum() const { return m_enrollmentMaximum; }
QString GazeClient::enrollmentPrompt() const { return m_enrollmentPrompt; }
QString GazeClient::faceStatus() const { return m_faceStatus; }
QString GazeClient::previewDataUrl() const { return m_previewDataUrl; }
QString GazeClient::errorMessage() const { return m_errorMessage; }
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

void GazeClient::refresh()
{
    const bool wasInstalled = m_installed;
    const bool wasAvailable = m_serviceAvailable;
    const bool wasCameraAvailable = m_cameraAvailable;

    m_installed = QFileInfo(QStringLiteral("/usr/bin/gaze")).isExecutable();
    auto *busInterface = QDBusConnection::systemBus().interface();
    const QDBusReply<bool> registered = busInterface
        ? busInterface->isServiceRegistered(QString::fromLatin1(serviceName))
        : QDBusReply<bool>();
    m_serviceAvailable = registered.isValid() && registered.value();
    m_cameraAvailable = false;

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
        || wasCameraAvailable != m_cameraAvailable)
        emit availabilityChanged();
}

void GazeClient::beginEnrollment(const QString &faceName)
{
    if (m_enrolling)
        return;
    refresh();
    if (!m_serviceAvailable) {
        setError(QStringLiteral("The Gaze system service is not available."));
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
        setError(QStringLiteral("Could not determine the current user."));
        return;
    }

    auto iface = gazeInterface();
    QDBusReply<void> claimReply = iface.call(QStringLiteral("Claim"), username);
    if (!claimReply.isValid()) {
        setError(claimReply.error().message());
        return;
    }
    m_claimed = true;

    m_enrollmentProgress = 0;
    m_enrollmentMaximum = 5;
    m_enrollmentComplete = false;
    m_enrollmentPrompt = QStringLiteral("Starting enrollment…");
    m_faceStatus.clear();
    m_previewDataUrl.clear();
    m_enrolling = true;
    emit enrollingChanged();
    emit enrollmentChanged();
    emit previewChanged();

    QDBusReply<void> enrollReply = iface.call(QStringLiteral("EnrollStart"), resolvedName);
    if (!enrollReply.isValid()) {
        m_enrolling = false;
        emit enrollingChanged();
        releaseClaim();
        setError(enrollReply.error().message());
        return;
    }

    setError({});
}

void GazeClient::cancelEnrollment()
{
    if (m_serviceAvailable) {
        auto iface = gazeInterface();
        iface.call(QDBus::NoBlock, QStringLiteral("EnrollStop"));
    }
    releaseClaim();
    m_enrolling = false;
    m_enrollmentPrompt = QStringLiteral("Enrollment cancelled");
    emit enrollingChanged();
    emit enrollmentChanged();
}

void GazeClient::onEnrollStatus(const QString &,
                                uint progress,
                                uint maximum,
                                bool done,
                                const QString &prompt,
                                double timeRemaining)
{
    m_enrollmentProgress = static_cast<int>(progress);
    m_enrollmentMaximum = static_cast<int>(maximum);
    m_enrollmentPrompt = prompt;
    if (timeRemaining > 0.0)
        m_enrollmentPrompt += QStringLiteral(" · %1s").arg(timeRemaining, 0, 'f', 1);

    if (done) {
        m_enrolling = false;
        m_enrollmentComplete = prompt == QStringLiteral("completed");
        releaseClaim();
        emit enrollingChanged();
    }
    emit enrollmentChanged();
}

void GazeClient::onFaceStatus(const QString &status)
{
    m_faceStatus = status;
    emit enrollmentChanged();
}

void GazeClient::onPreviewFrame(const QByteArray &jpeg)
{
    m_previewDataUrl = QStringLiteral("data:image/jpeg;base64,")
        + QString::fromLatin1(jpeg.toBase64());
    emit previewChanged();
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
