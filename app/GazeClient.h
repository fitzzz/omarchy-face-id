// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QColor>
#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>

class GazeClient final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool installed READ installed NOTIFY availabilityChanged)
    Q_PROPERTY(bool serviceAvailable READ serviceAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(bool cameraAvailable READ cameraAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(bool enrolling READ enrolling NOTIFY enrollingChanged)
    Q_PROPERTY(bool enrollmentComplete READ enrollmentComplete NOTIFY enrollmentChanged)
    Q_PROPERTY(int enrollmentProgress READ enrollmentProgress NOTIFY enrollmentChanged)
    Q_PROPERTY(int enrollmentMaximum READ enrollmentMaximum NOTIFY enrollmentChanged)
    Q_PROPERTY(QString enrollmentPrompt READ enrollmentPrompt NOTIFY enrollmentChanged)
    Q_PROPERTY(QString faceStatus READ faceStatus NOTIFY enrollmentChanged)
    Q_PROPERTY(QString previewDataUrl READ previewDataUrl NOTIFY previewChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorChanged)
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
    bool enrolling() const;
    bool enrollmentComplete() const;
    int enrollmentProgress() const;
    int enrollmentMaximum() const;
    QString enrollmentPrompt() const;
    QString faceStatus() const;
    QString previewDataUrl() const;
    QString errorMessage() const;
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
    Q_INVOKABLE void beginEnrollment(const QString &faceName);
    Q_INVOKABLE void cancelEnrollment();

signals:
    void availabilityChanged();
    void enrollingChanged();
    void enrollmentChanged();
    void previewChanged();
    void errorChanged();
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
    void releaseClaim();
    void setError(const QString &message);
    void scheduleThemeReload();
    void reloadTheme();

    bool m_installed = false;
    bool m_serviceAvailable = false;
    bool m_cameraAvailable = false;
    bool m_claimed = false;
    bool m_enrolling = false;
    bool m_enrollmentComplete = false;
    int m_enrollmentProgress = 0;
    int m_enrollmentMaximum = 5;
    QString m_enrollmentPrompt = QStringLiteral("Ready to begin");
    QString m_faceStatus;
    QString m_previewDataUrl;
    QString m_errorMessage;
    QFileSystemWatcher m_themeWatcher;
    QTimer m_themeReloadTimer;
    QString m_themeRoot;
    QColor m_themeBackground = QColor(QStringLiteral("#111c18"));
    QColor m_themeDarkBackground = QColor(QStringLiteral("#0c1512"));
    QColor m_themeDarkerBackground = QColor(QStringLiteral("#090f0d"));
    QColor m_themeLighterBackground = QColor(QStringLiteral("#23372b"));
    QColor m_themeForeground = QColor(QStringLiteral("#c1c497"));
    QColor m_themeMuted = QColor(QStringLiteral("#53685b"));
    QColor m_themeAccent = QColor(QStringLiteral("#509475"));
    QColor m_themeOrange = QColor(QStringLiteral("#a2734b"));
    QColor m_themeGreen = QColor(QStringLiteral("#549e6a"));
    QColor m_themeRed = QColor(QStringLiteral("#ff5345"));
};
