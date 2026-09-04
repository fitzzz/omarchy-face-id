// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "DiagnosticLog.h"
#include "OmarchyTheme.h"

#include <QColor>
#include <QElapsedTimer>
#include <QObject>
#include <QTimer>

#include <atomic>

class QProcess;
class QTemporaryFile;
struct _GstElement;

class GazeClient final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool installed READ installed NOTIFY availabilityChanged)
    Q_PROPERTY(bool serviceAvailable READ serviceAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(bool cameraAvailable READ cameraAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(bool cameraSupportAvailable READ cameraSupportAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(bool systemIntegrationReady READ systemIntegrationReady NOTIFY availabilityChanged)
    Q_PROPERTY(bool existingEnrollment READ existingEnrollment NOTIFY upgradeChanged)
    Q_PROPERTY(bool upgradeAvailable READ upgradeAvailable NOTIFY upgradeChanged)
    Q_PROPERTY(bool parallelPreviewAvailable READ parallelPreviewAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(bool faceSetupInstalling READ faceSetupInstalling NOTIFY faceSetupChanged)
    Q_PROPERTY(QString faceSetupError READ faceSetupError NOTIFY faceSetupChanged)
    Q_PROPERTY(bool enrolling READ enrolling NOTIFY enrollingChanged)
    Q_PROPERTY(bool enrollmentComplete READ enrollmentComplete NOTIFY enrollmentChanged)
    Q_PROPERTY(int enrollmentProgress READ enrollmentProgress NOTIFY enrollmentChanged)
    Q_PROPERTY(int enrollmentMaximum READ enrollmentMaximum NOTIFY enrollmentChanged)
    Q_PROPERTY(QString enrollmentPrompt READ enrollmentPrompt NOTIFY enrollmentChanged)
    Q_PROPERTY(QString faceStatus READ faceStatus NOTIFY enrollmentChanged)
    Q_PROPERTY(QString previewDataUrl READ previewDataUrl NOTIFY previewChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorChanged)
    Q_PROPERTY(bool lockIntegrationInstalled READ lockIntegrationInstalled NOTIFY lockIntegrationChanged)
    Q_PROPERTY(bool lockIntegrationActive READ lockIntegrationActive NOTIFY lockIntegrationChanged)
    Q_PROPERTY(bool lockIntegrationInstalling READ lockIntegrationInstalling NOTIFY lockIntegrationChanged)
    Q_PROPERTY(QString lockIntegrationStatus READ lockIntegrationStatus NOTIFY lockIntegrationChanged)
    Q_PROPERTY(QString lockIntegrationError READ lockIntegrationError NOTIFY lockIntegrationChanged)
    Q_PROPERTY(QColor themeBackground READ themeBackground NOTIFY themeChanged)
    Q_PROPERTY(QColor themeDarkBackground READ themeDarkBackground NOTIFY themeChanged)
    Q_PROPERTY(QColor themeDarkerBackground READ themeDarkerBackground NOTIFY themeChanged)
    Q_PROPERTY(QColor themeLighterBackground READ themeLighterBackground NOTIFY themeChanged)
    Q_PROPERTY(QColor themeForeground READ themeForeground NOTIFY themeChanged)
    Q_PROPERTY(QColor themeMuted READ themeMuted NOTIFY themeChanged)
    Q_PROPERTY(QColor themeAccent READ themeAccent NOTIFY themeChanged)
    Q_PROPERTY(QColor themeOrange READ themeOrange NOTIFY themeChanged)
    Q_PROPERTY(QColor themeGreen READ themeGreen NOTIFY themeChanged)
    Q_PROPERTY(QColor themeRed READ themeRed NOTIFY themeChanged)

public:
    explicit GazeClient(QObject *parent = nullptr);
    ~GazeClient() override;

    bool installed() const;
    bool serviceAvailable() const;
    bool cameraAvailable() const;
    bool cameraSupportAvailable() const;
    bool systemIntegrationReady() const;
    bool existingEnrollment() const;
    bool upgradeAvailable() const;
    bool parallelPreviewAvailable() const;
    bool faceSetupInstalling() const;
    QString faceSetupError() const;
    bool enrolling() const;
    bool enrollmentComplete() const;
    int enrollmentProgress() const;
    int enrollmentMaximum() const;
    QString enrollmentPrompt() const;
    QString faceStatus() const;
    QString previewDataUrl() const;
    QString errorMessage() const;
    bool lockIntegrationInstalled() const;
    bool lockIntegrationActive() const;
    bool lockIntegrationInstalling() const;
    QString lockIntegrationStatus() const;
    QString lockIntegrationError() const;
    QColor themeBackground() const;
    QColor themeDarkBackground() const;
    QColor themeDarkerBackground() const;
    QColor themeLighterBackground() const;
    QColor themeForeground() const;
    QColor themeMuted() const;
    QColor themeAccent() const;
    QColor themeOrange() const;
    QColor themeGreen() const;
    QColor themeRed() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void installFaceSetup();
    Q_INVOKABLE void installFaceSetupQuietly();
    Q_INVOKABLE void beginEnrollment(const QString &faceName);
    Q_INVOKABLE void cancelEnrollment();
    Q_INVOKABLE void enableLockIntegration();

signals:
    void availabilityChanged();
    void upgradeChanged();
    void faceSetupChanged();
    void enrollingChanged();
    void enrollmentChanged();
    void previewChanged();
    void errorChanged();
    void lockIntegrationChanged();
    void lockIntegrationActivationFinished(bool filesInstalled, bool liveActive);
    void themeChanged();

private slots:
    void onEnrollStatus(const QString &faceName,
                        uint progress,
                        uint maximum,
                        bool done,
                        const QString &prompt,
                        double timeRemaining);
    void onFaceStatus(const QString &status);
    void onPreviewFrame(const QByteArray &jpeg);

private:
    enum class LockActivationPhase {
        Idle,
        Authorizing,
        Rescanning,
        Enabling,
        Reloading,
        Verifying,
    };

    void releaseClaim();
    void setError(const QString &message);
    void startFaceSetup(bool quiet);
    void ensureUserConfig();
    void refreshLockIntegrationStatus();
    bool lockIntegrationStateMatches() const;
    void recordEnrollmentOwnership(const QString &faceName);
    bool stageAndActivateUserPlugin(QString *error);
    void commitUserPluginActivation();
    void rollbackUserPluginActivation();
    void continueLockIntegrationInstall();
    void startLockPluginRescan();
    void startLockPluginEnable();
    void startLockShellRestart();
    void startLockShellVerification();
    void finishLockActivation(bool success, const QString &error = {});
    void abandonProcess(QProcess *&process);
    void armProcessDeadline(QProcess *process, const QString &command, int timeoutMs);
    void recordActivationPhase(const QString &event,
                               DiagnosticLog::Level level,
                               const QJsonObject &fields = {});
    void finishFaceSetup(bool success, const QString &error = {});
    void playDing();
    void onParallelPreviewFrame(const QByteArray &jpeg);
    bool startParallelPreview();
    void stopParallelPreview(bool clearFrame = false);

    bool m_installed = false;
    bool m_serviceAvailable = false;
    bool m_cameraAvailable = false;
    bool m_cameraSupportAvailable = false;
    bool m_systemIntegrationReady = false;
    bool m_parallelPreviewAvailable = false;
    bool m_faceSetupInstalling = false;
    QString m_faceSetupError;
    bool m_claimed = false;
    bool m_enrolling = false;
    bool m_enrollmentComplete = false;
    int m_enrollmentProgress = 0;
    int m_enrollmentMaximum = 5;
    int m_enrollmentGeneration = 0;
    QString m_enrollmentPrompt = QStringLiteral("Ready to begin");
    QString m_enrollmentFaceName = QStringLiteral("default");
    QString m_faceStatus;
    QString m_previewDataUrl;
    int m_remotePreviewFrames = 0;
    int m_parallelPreviewFrames = 0;
    QString m_errorMessage;
    bool m_lockIntegrationInstalled = false;
    bool m_lockIntegrationActive = false;
    bool m_lockIntegrationInstalling = false;
    QString m_lockIntegrationError;
    LockActivationPhase m_lockActivationPhase = LockActivationPhase::Idle;
    QProcess *m_lockIntegrationProcess = nullptr;
    QTemporaryFile *m_lockIntegrationPamFile = nullptr;
    QProcess *m_lockPluginEnableProcess = nullptr;
    QString m_lockPluginEnableCommand;
    QString m_lockPluginRescanCommand;
    QString m_lockShellRestartCommand;
    bool m_lockRestartAttempted = false;
    QString m_lockPluginRoot;
    QString m_lockPluginBackupRoot;
    QElapsedTimer m_lockActivationElapsed;
    QElapsedTimer m_lockPhaseElapsed;
    QElapsedTimer m_lockRestartVerificationElapsed;
    QTimer m_lockActivationDeadline;
    QTemporaryFile *m_dingFile = nullptr;
    _GstElement *m_parallelPreviewPipeline = nullptr;
    std::atomic<qint64> m_lastPreviewFrameUsec{0};
    QTimer m_faceSetupPollTimer;
    QProcess *m_faceSetupProcess = nullptr;
    int m_faceSetupPollCount = 0;
    QString m_faceSetupStatusPath;
    OmarchyTheme m_theme;
    DiagnosticLog m_diagnostics;
};
