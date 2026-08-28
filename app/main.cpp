// SPDX-License-Identifier: GPL-3.0-or-later

#include "GazeClient.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QGuiApplication>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTemporaryFile>
#include <QTimer>

#include <cstring>

namespace {
int runUninstaller(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    const qsizetype uninstallArgument = app.arguments().indexOf(
        QStringLiteral("--uninstall"));

    QFile uninstallResource(QStringLiteral(":/scripts/uninstall.sh"));
    QTemporaryFile uninstallScript(
        QDir::tempPath() + QStringLiteral("/omarchy-face-id-uninstall.XXXXXX"));
    if (!uninstallResource.open(QIODevice::ReadOnly)
        || !uninstallScript.open()
        || uninstallScript.write(uninstallResource.readAll()) < 1
        || !uninstallScript.flush())
        return 1;

    QFile::setPermissions(
        uninstallScript.fileName(),
        QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    QStringList arguments = app.arguments().mid(uninstallArgument + 1);
    arguments.prepend(uninstallScript.fileName());
    return QProcess::execute(QStringLiteral("/usr/bin/bash"), arguments);
}
}

int main(int argc, char *argv[])
{
    for (int index = 1; index < argc; ++index) {
        if (std::strcmp(argv[index], "--uninstall") == 0)
            return runUninstaller(argc, argv);
    }

    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("Omarchy Face ID"));
    QCoreApplication::setApplicationVersion(QStringLiteral("0.3.0"));
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
    engine.loadFromModule(QStringLiteral("FaceId"), QStringLiteral("Main"));
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
