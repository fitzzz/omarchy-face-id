// SPDX-License-Identifier: GPL-3.0-or-later

#include "DiagnosticLog.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUuid>

namespace {
constexpr qint64 maximumLogBytes = 1024 * 1024;
constexpr int retainedLogFiles = 3;

bool isSensitiveKey(const QString &key)
{
    static const QRegularExpression sensitive(
        QStringLiteral("(^|_)(user|username|name|path|device|command|output|message|"
                       "frame|image|jpeg|embedding|biometric|token|password|secret|email|"
                       "hostname|address|ip)($|_)"),
        QRegularExpression::CaseInsensitiveOption);
    return sensitive.match(key).hasMatch();
}

bool isSafeIdentifier(const QString &value)
{
    static const QRegularExpression identifier(
        QStringLiteral("^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$"));
    return identifier.match(value).hasMatch();
}
}

DiagnosticLog::DiagnosticLog()
{
    QString stateRoot = QStandardPaths::writableLocation(
        QStandardPaths::GenericStateLocation);
    if (stateRoot.isEmpty()) {
        stateRoot = qEnvironmentVariable("XDG_STATE_HOME");
        if (stateRoot.isEmpty())
            stateRoot = QDir::homePath() + QStringLiteral("/.local/state");
    }

    const QString directory = stateRoot + QStringLiteral("/omarchy-face-id");
    QDir().mkpath(directory);
    QFile::setPermissions(directory,
                          QFileDevice::ReadOwner | QFileDevice::WriteOwner
                              | QFileDevice::ExeOwner);
    m_path = directory + QStringLiteral("/diagnostics.jsonl");
    m_sessionId = QUuid::createUuid().toString(QUuid::WithoutBraces);
}

QString DiagnosticLog::path() const { return m_path; }
QString DiagnosticLog::sessionId() const { return m_sessionId; }

QString DiagnosticLog::levelName(Level level)
{
    switch (level) {
    case Level::Debug: return QStringLiteral("debug");
    case Level::Info: return QStringLiteral("info");
    case Level::Warning: return QStringLiteral("warning");
    case Level::Error: return QStringLiteral("error");
    }
    return QStringLiteral("info");
}

QJsonObject DiagnosticLog::sanitizedAttributes(const QJsonObject &attributes)
{
    QJsonObject safe;
    static const QRegularExpression keyFormat(
        QStringLiteral("^[a-z][a-z0-9_]{0,47}$"));
    for (auto entry = attributes.constBegin(); entry != attributes.constEnd(); ++entry) {
        const QString key = entry.key();
        if (!keyFormat.match(key).hasMatch() || isSensitiveKey(key))
            continue;

        const QJsonValue value = entry.value();
        if (value.isBool() || value.isDouble() || value.isNull())
            safe.insert(key, value);
        else if (value.isString() && isSafeIdentifier(value.toString()))
            safe.insert(key, value);
    }
    return safe;
}

void DiagnosticLog::rotateIfNeeded()
{
    if (QFileInfo(m_path).size() < maximumLogBytes)
        return;

    QFile::remove(m_path + QStringLiteral(".%1").arg(retainedLogFiles));
    for (int index = retainedLogFiles - 1; index >= 1; --index) {
        const QString source = m_path + QStringLiteral(".%1").arg(index);
        const QString target = m_path + QStringLiteral(".%1").arg(index + 1);
        if (QFileInfo::exists(source))
            QFile::rename(source, target);
    }
    QFile::rename(m_path, m_path + QStringLiteral(".1"));
}

void DiagnosticLog::record(const QString &component,
                           const QString &event,
                           Level level,
                           const QJsonObject &attributes)
{
    if (!isSafeIdentifier(component) || !isSafeIdentifier(event))
        return;

    QMutexLocker locker(&m_mutex);
    rotateIfNeeded();

    QJsonObject record{
        {QStringLiteral("schema"), QStringLiteral("omarchy.face-id.diagnostics.event")},
        {QStringLiteral("schema_version"), 1},
        {QStringLiteral("timestamp_utc"),
         QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
        {QStringLiteral("session_id"), m_sessionId},
        {QStringLiteral("sequence"), static_cast<qint64>(++m_sequence)},
        {QStringLiteral("level"), levelName(level)},
        {QStringLiteral("component"), component},
        {QStringLiteral("event"), event},
        {QStringLiteral("attributes"), sanitizedAttributes(attributes)},
    };

    QFile file(m_path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
        return;
    file.write(QJsonDocument(record).toJson(QJsonDocument::Compact));
    file.write("\n");
    file.flush();
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
}
