// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QColor>
#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QTimer>

class OmarchyTheme final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QColor background READ background NOTIFY changed)
    Q_PROPERTY(QColor darkBackground READ darkBackground NOTIFY changed)
    Q_PROPERTY(QColor darkerBackground READ darkerBackground NOTIFY changed)
    Q_PROPERTY(QColor lighterBackground READ lighterBackground NOTIFY changed)
    Q_PROPERTY(QColor foreground READ foreground NOTIFY changed)
    Q_PROPERTY(QColor muted READ muted NOTIFY changed)
    Q_PROPERTY(QColor accent READ accent NOTIFY changed)
    Q_PROPERTY(QColor orange READ orange NOTIFY changed)
    Q_PROPERTY(QColor green READ green NOTIFY changed)
    Q_PROPERTY(QColor red READ red NOTIFY changed)
    Q_PROPERTY(QColor polkitBackground READ polkitBackground NOTIFY changed)
    Q_PROPERTY(QColor polkitText READ polkitText NOTIFY changed)
    Q_PROPERTY(QColor polkitBorder READ polkitBorder NOTIFY changed)
    Q_PROPERTY(QColor polkitAccent READ polkitAccent NOTIFY changed)
    Q_PROPERTY(QColor polkitScrim READ polkitScrim NOTIFY changed)
    Q_PROPERTY(QColor controlSurface READ controlSurface NOTIFY changed)
    Q_PROPERTY(QColor controlHover READ controlHover NOTIFY changed)
    Q_PROPERTY(QColor controlBorder READ controlBorder NOTIFY changed)
    Q_PROPERTY(QString fontFamily READ fontFamily CONSTANT)
    Q_PROPERTY(int fontCaption READ fontCaption NOTIFY changed)
    Q_PROPERTY(int fontBody READ fontBody NOTIFY changed)
    Q_PROPERTY(int fontTitle READ fontTitle NOTIFY changed)
    Q_PROPERTY(int panelGap READ panelGap NOTIFY changed)
    Q_PROPERTY(int panelPadding READ panelPadding NOTIFY changed)
    Q_PROPERTY(int controlGap READ controlGap NOTIFY changed)
    Q_PROPERTY(int controlPaddingX READ controlPaddingX NOTIFY changed)
    Q_PROPERTY(int controlPaddingY READ controlPaddingY NOTIFY changed)
    Q_PROPERTY(int controlHeight READ controlHeight NOTIFY changed)

public:
    explicit OmarchyTheme(QObject *parent = nullptr);

    QColor background() const { return m_background; }
    QColor darkBackground() const { return m_darkBackground; }
    QColor darkerBackground() const { return m_darkerBackground; }
    QColor lighterBackground() const { return m_lighterBackground; }
    QColor foreground() const { return m_foreground; }
    QColor muted() const { return m_muted; }
    QColor accent() const { return m_accent; }
    QColor orange() const { return m_orange; }
    QColor green() const { return m_green; }
    QColor red() const { return m_red; }
    QColor polkitBackground() const;
    QColor polkitText() const;
    QColor polkitBorder() const;
    QColor polkitAccent() const;
    QColor polkitScrim() const;
    QColor controlSurface() const;
    QColor controlHover() const;
    QColor controlBorder() const;
    QString fontFamily() const { return QStringLiteral("monospace"); }
    int fontCaption() const;
    int fontBody() const;
    int fontTitle() const;
    int panelGap() const;
    int panelPadding() const;
    int controlGap() const;
    int controlPaddingX() const;
    int controlPaddingY() const;
    int controlHeight() const;

signals:
    void changed();

private:
    void scheduleReload();
    void reload();
    void resetWatchPaths(const QStringList &files, const QStringList &directories);
    QColor shellColor(const QString &key, const QColor &fallback) const;
    QColor composedShellColor(const QString &key, const QString &alphaKey,
                              const QColor &fallback, qreal fallbackAlpha) const;
    qreal shellNumber(const QString &key, qreal fallback) const;
    int scaledSpacing(const QString &key, int fallback) const;
    int fontSize(const QString &key, qreal multiplier) const;

    QFileSystemWatcher m_watcher;
    QTimer m_reloadTimer;
    QString m_themeRoot;
    QString m_userShellPath;
    QHash<QString, QString> m_shellValues;
    QColor m_background{QStringLiteral("#111c18")};
    QColor m_darkBackground{QStringLiteral("#0c1512")};
    QColor m_darkerBackground{QStringLiteral("#090f0d")};
    QColor m_lighterBackground{QStringLiteral("#23372b")};
    QColor m_foreground{QStringLiteral("#c1c497")};
    QColor m_muted{QStringLiteral("#53685b")};
    QColor m_accent{QStringLiteral("#509475")};
    QColor m_orange{QStringLiteral("#a2734b")};
    QColor m_green{QStringLiteral("#549e6a")};
    QColor m_red{QStringLiteral("#ff5345")};
};
