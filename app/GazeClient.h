// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>

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

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void beginEnrollment(const QString &faceName);
    Q_INVOKABLE void cancelEnrollment();

signals:
    void availabilityChanged();
    void enrollingChanged();
    void enrollmentChanged();
    void previewChanged();
    void errorChanged();

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
};
