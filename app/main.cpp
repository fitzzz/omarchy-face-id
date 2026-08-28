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
    const bool integrationInstallTest = app.arguments().contains(
        QStringLiteral("--integration-install-test"));
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

    if (integrationInstallTest) {
        QObject::connect(&gazeClient, &GazeClient::lockIntegrationChanged, &app,
                         [&app, &gazeClient]() {
            if (gazeClient.lockIntegrationInstalling())
                return;
            if (gazeClient.lockIntegrationInstalled())
                app.exit(0);
            else if (!gazeClient.lockIntegrationError().isEmpty())
                app.exit(1);
        });
        QTimer::singleShot(0, &gazeClient, &GazeClient::enableLockIntegration);
        QTimer::singleShot(5000, &app, [&app]() { app.exit(2); });
    }

    return app.exec();
}
