// SPDX-License-Identifier: GPL-3.0-or-later

#include "GazeClient.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTimer>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("Omarchy Face Unlock"));
    QCoreApplication::setApplicationVersion(QStringLiteral("0.2.0"));
    QCoreApplication::setOrganizationName(QStringLiteral("Omarchy Community"));
    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    const bool smokeTest = app.arguments().contains(QStringLiteral("--smoke-test"));
    GazeClient gazeClient;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("gazeClient"), &gazeClient);

    bool loaded = false;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app,
                     [&loaded](QObject *object, const QUrl &) { loaded = object != nullptr; });
    engine.loadFromModule(QStringLiteral("FaceUnlock"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty())
        return 1;

    if (smokeTest)
        QTimer::singleShot(250, &app, [&app, &loaded]() { app.exit(loaded ? 0 : 1); });

    return app.exec();
}
