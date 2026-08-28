// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QJsonObject>
#include <QMutex>
#include <QString>

class DiagnosticLog final
{
public:
    enum class Level { Debug, Info, Warning, Error };

    DiagnosticLog();

    QString path() const;
    QString sessionId() const;
    void record(const QString &component,
                const QString &event,
                Level level = Level::Info,
                const QJsonObject &attributes = {});

private:
    static QString levelName(Level level);
    static QJsonObject sanitizedAttributes(const QJsonObject &attributes);
    void rotateIfNeeded();

    QString m_path;
    QString m_sessionId;
    quint64 m_sequence = 0;
    QMutex m_mutex;
};
