// SPDX-License-Identifier: GPL-3.0-or-later

#include "OmarchyTheme.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <utility>

namespace {
QHash<QString, QColor> parseColors(const QString &contents)
{
    QHash<QString, QColor> colors;
    const QRegularExpression entry(QStringLiteral(
        "(?m)^\\s*([A-Za-z0-9_-]+)\\s*=\\s*[\\\"']?(#[0-9A-Fa-f]{6,8})"));
    auto matches = entry.globalMatch(contents);
    while (matches.hasNext()) {
        const auto match = matches.next();
        const QColor color(match.captured(2));
        if (color.isValid())
            colors.insert(match.captured(1).toLower(), color);
    }
    return colors;
}

QHash<QString, QString> parseShell(const QString &contents)
{
    QHash<QString, QString> values;
    QString section;
    const QRegularExpression sectionEntry(
        QStringLiteral("^\\[([A-Za-z0-9_-]+)\\]\\s*(?:#.*)?$"));
    const QRegularExpression valueEntry(QStringLiteral(
        "^([A-Za-z0-9_-]+)\\s*=\\s*(?:[\\\"']([^\\\"']+)[\\\"']|([^#]+?))\\s*(?:#.*)?$"));
    const QStringList lines = contents.split(QLatin1Char('\n'));
    for (const QString &rawLine : lines) {
        const QString line = rawLine.trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        const auto sectionMatch = sectionEntry.match(line);
        if (sectionMatch.hasMatch()) {
            section = sectionMatch.captured(1).toLower();
            continue;
        }
        const auto valueMatch = valueEntry.match(line);
        if (!section.isEmpty() && valueMatch.hasMatch()) {
            const QString value = (valueMatch.captured(1).isEmpty()
                                       ? QString()
                                       : (valueMatch.captured(2).isEmpty()
                                              ? valueMatch.captured(3)
                                              : valueMatch.captured(2)))
                                      .trimmed();
            if (!value.isEmpty())
                values.insert(section + QLatin1Char('.')
                                  + valueMatch.captured(1).toLower(), value);
        }
    }
    return values;
}

QString readTextFile(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly | QIODevice::Text)
        ? QTextStream(&file).readAll() : QString();
}

QColor withAlpha(QColor color, qreal alpha)
{
    color.setAlphaF(std::clamp(alpha, 0.0, 1.0) * color.alphaF());
    return color;
}

QString firstColorToken(const QString &value)
{
    static const QRegularExpression angle(
        QStringLiteral("^-?[0-9]+(?:\\.[0-9]+)?deg$"),
        QRegularExpression::CaseInsensitiveOption);
    const QStringList tokens = value.trimmed().split(
        QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    for (const QString &token : tokens) {
        if (!angle.match(token).hasMatch())
            return token;
    }
    return value.trimmed();
}

QColor parsedShellColor(const QString &token)
{
    QColor color(token);
    if (color.isValid())
        return color;

    // Hyprland themes also use rgba(RRGGBBAA) and rgb(RRGGBB) tokens.
    static const QRegularExpression hyprlandColor(
        QStringLiteral("^rgba?\\(([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?\\)$"));
    const auto match = hyprlandColor.match(token);
    if (!match.hasMatch())
        return {};
    return QColor(QStringLiteral("#") + match.captured(1) + match.captured(2));
}
}

OmarchyTheme::OmarchyTheme(QObject *parent)
    : QObject(parent)
{
    m_themeRoot = qEnvironmentVariable(
        "OMARCHY_FACE_ID_THEME_ROOT",
        QDir::homePath() + QStringLiteral("/.local/state/omarchy/current"));
    const QString configRoot = QStandardPaths::writableLocation(
        QStandardPaths::GenericConfigLocation);
    m_userShellPath = qEnvironmentVariable(
        "OMARCHY_FACE_ID_SHELL_OVERRIDE",
        configRoot + QStringLiteral("/omarchy/shell.toml"));
    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(40);
    connect(&m_reloadTimer, &QTimer::timeout, this, &OmarchyTheme::reload);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged,
            this, &OmarchyTheme::scheduleReload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &OmarchyTheme::scheduleReload);
    reload();
}

void OmarchyTheme::scheduleReload()
{
    m_reloadTimer.start();
}

void OmarchyTheme::reload()
{
    const QString themeDirectory = m_themeRoot + QStringLiteral("/theme");
    const QString colorsPath = themeDirectory + QStringLiteral("/colors.toml");
    const QString shellPath = themeDirectory + QStringLiteral("/shell.toml");
    const QString themeNamePath = m_themeRoot + QStringLiteral("/theme.name");

    const auto colors = parseColors(readTextFile(colorsPath));
    bool paletteChanged = false;
    const auto apply = [&colors, &paletteChanged](const QString &key, QColor &target) {
        const auto candidate = colors.constFind(key);
        if (candidate != colors.cend() && candidate.value() != target) {
            target = candidate.value();
            paletteChanged = true;
        }
    };
    apply(QStringLiteral("background"), m_background);
    apply(QStringLiteral("dark_background"), m_darkBackground);
    apply(QStringLiteral("darker_background"), m_darkerBackground);
    apply(QStringLiteral("lighter_background"), m_lighterBackground);
    apply(QStringLiteral("foreground"), m_foreground);
    apply(QStringLiteral("muted"), m_muted);
    apply(QStringLiteral("accent"), m_accent);
    apply(QStringLiteral("orange"), m_orange);
    apply(QStringLiteral("green"), m_green);
    apply(QStringLiteral("red"), m_red);

    QHash<QString, QString> merged = parseShell(readTextFile(shellPath));
    const auto userValues = parseShell(readTextFile(m_userShellPath));
    for (auto entry = userValues.cbegin(); entry != userValues.cend(); ++entry)
        merged.insert(entry.key(), entry.value());
    const bool shellChanged = merged != m_shellValues;
    m_shellValues = std::move(merged);

    resetWatchPaths({colorsPath, shellPath, themeNamePath, m_userShellPath},
                    {m_themeRoot, themeDirectory,
                     QFileInfo(m_userShellPath).absolutePath()});
    if (!colors.isEmpty()
        && qEnvironmentVariableIsSet("OMARCHY_FACE_ID_THEME_DEBUG")) {
        std::fprintf(stderr, "Omarchy theme loaded: %s\n",
                     m_accent.name().toUtf8().constData());
        std::fflush(stderr);
    }
    if (paletteChanged || shellChanged)
        emit changed();
}

void OmarchyTheme::resetWatchPaths(const QStringList &files,
                                   const QStringList &directories)
{
    if (!m_watcher.files().isEmpty())
        m_watcher.removePaths(m_watcher.files());
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());
    for (const QString &path : directories) {
        if (QFileInfo(path).isDir() && !m_watcher.directories().contains(path))
            m_watcher.addPath(path);
    }
    for (const QString &path : files) {
        if (QFileInfo(path).isFile())
            m_watcher.addPath(path);
    }
}

QColor OmarchyTheme::shellColor(const QString &key, const QColor &fallback) const
{
    QString value = m_shellValues.value(key).trimmed();
    for (int depth = 0; depth < 5; ++depth) {
        const QString firstToken = firstColorToken(value);
        const QString role = firstToken.toLower();
        if (role == QStringLiteral("foreground") || role == QStringLiteral("text"))
            return m_foreground;
        if (role == QStringLiteral("background"))
            return m_background;
        if (role == QStringLiteral("transparent"))
            return QColor(Qt::transparent);
        if (role == QStringLiteral("accent"))
            return m_accent;
        if (role == QStringLiteral("urgent"))
            return m_red;
        if (role == QStringLiteral("muted"))
            return m_muted;
        const auto reference = m_shellValues.constFind(role);
        if (reference == m_shellValues.cend()) {
            const QColor color = parsedShellColor(firstToken);
            return color.isValid() ? color : fallback;
        }
        value = reference.value().trimmed();
    }
    return fallback;
}

qreal OmarchyTheme::shellNumber(const QString &key, qreal fallback) const
{
    bool valid = false;
    const qreal result = m_shellValues.value(key).toDouble(&valid);
    return valid ? result : fallback;
}

QColor OmarchyTheme::composedShellColor(const QString &key,
                                        const QString &alphaKey,
                                        const QColor &fallback,
                                        qreal fallbackAlpha) const
{
    return withAlpha(shellColor(key, fallback),
                     shellNumber(alphaKey, fallbackAlpha));
}

QColor OmarchyTheme::polkitBackground() const
{
    return composedShellColor(QStringLiteral("polkit.background"),
                              QStringLiteral("polkit.background-alpha"),
                              m_background, 1.0);
}
QColor OmarchyTheme::polkitText() const
{
    return shellColor(QStringLiteral("polkit.text"), m_foreground);
}
QColor OmarchyTheme::polkitBorder() const
{
    return composedShellColor(QStringLiteral("polkit.border"),
                              QStringLiteral("polkit.border-alpha"),
                              m_accent, 1.0);
}
QColor OmarchyTheme::polkitAccent() const
{
    return shellColor(QStringLiteral("polkit.accent"), m_accent);
}
QColor OmarchyTheme::polkitScrim() const
{
    return composedShellColor(QStringLiteral("polkit.scrim"),
                              QStringLiteral("polkit.scrim-alpha"),
                              m_background, 0.5);
}
QColor OmarchyTheme::controlSurface() const
{
    return withAlpha(shellColor(QStringLiteral("controls.normal-color"),
                                m_foreground),
                     shellNumber(QStringLiteral("controls.normal-fill-alpha"), 0.04));
}
QColor OmarchyTheme::controlHover() const
{
    return withAlpha(shellColor(QStringLiteral("controls.hover-cursor-color"),
                                m_foreground),
                     shellNumber(QStringLiteral("controls.hover-cursor-fill-alpha"), 0.08));
}
QColor OmarchyTheme::controlBorder() const
{
    return withAlpha(shellColor(QStringLiteral("controls.normal-border"),
                                m_foreground),
                     shellNumber(QStringLiteral("controls.normal-border-alpha"), 0.4));
}

int OmarchyTheme::fontSize(const QString &key, qreal multiplier) const
{
    const qreal base = std::max<qreal>(1, shellNumber(QStringLiteral("font.base-size"), 12));
    return std::max(1, qRound(shellNumber(QStringLiteral("font.") + key,
                                         base * multiplier)));
}
int OmarchyTheme::fontCaption() const { return fontSize(QStringLiteral("caption"), 0.833); }
int OmarchyTheme::fontBody() const { return fontSize(QStringLiteral("body"), 1.0); }
int OmarchyTheme::fontTitle() const { return fontSize(QStringLiteral("title"), 1.167); }

int OmarchyTheme::scaledSpacing(const QString &key, int fallback) const
{
    const qreal base = std::max<qreal>(1, shellNumber(QStringLiteral("font.base-size"), 12));
    const qreal scale = std::max<qreal>(0, shellNumber(QStringLiteral("spacing.scale"), 1));
    const QString scaleWithFont = m_shellValues.value(
        QStringLiteral("spacing.scale-with-font"), QStringLiteral("true")).toLower();
    const qreal fontScale = (scaleWithFont == QStringLiteral("false") || scaleWithFont == QStringLiteral("0"))
        ? 1.0 : base / 12.0;
    return std::max(0, qRound(shellNumber(QStringLiteral("spacing.") + key,
                                         fallback * scale * fontScale)));
}
int OmarchyTheme::panelGap() const { return scaledSpacing(QStringLiteral("panel-gap"), 14); }
int OmarchyTheme::panelPadding() const { return scaledSpacing(QStringLiteral("panel-padding"), 18); }
int OmarchyTheme::controlGap() const { return scaledSpacing(QStringLiteral("control-gap"), 8); }
int OmarchyTheme::controlPaddingX() const { return scaledSpacing(QStringLiteral("control-padding-x"), 10); }
int OmarchyTheme::controlPaddingY() const { return scaledSpacing(QStringLiteral("control-padding-y"), 6); }
int OmarchyTheme::controlHeight() const { return scaledSpacing(QStringLiteral("control-height"), 28); }
