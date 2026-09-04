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
#include <QStorageInfo>
#include <QTextStream>
#include <QTimer>

#include <cstdio>
#include <cstring>
#include <functional>

namespace {
int runUninstaller(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    const qsizetype uninstallArgument = app.arguments().indexOf(
        QStringLiteral("--uninstall"));

    const QString overridePath = qEnvironmentVariable(
        "OMARCHY_FACE_ID_UNINSTALLER_PATH");
    const QString uninstallPath = overridePath.isEmpty()
        ? QDir::cleanPath(QCoreApplication::applicationDirPath()
                          + QStringLiteral(
                              "/../share/omarchy-face-id/uninstall.sh"))
        : overridePath;
    QFile uninstallResource(QStringLiteral(":/scripts/uninstall.sh"));
    QFile uninstallScript(uninstallPath);
    if (!uninstallResource.open(QIODevice::ReadOnly)
        || !uninstallScript.open(QIODevice::ReadOnly)
        || uninstallResource.readAll() != uninstallScript.readAll())
        return 1;

    const QFileInfo scriptInfo(uninstallPath);
    const QStorageInfo scriptStorage(scriptInfo.absolutePath());
    const bool testSource = qEnvironmentVariableIsSet(
        "OMARCHY_FACE_ID_UNINSTALLER_TEST_MODE");
    const bool trustedSource = scriptInfo.isFile() && !scriptInfo.isSymLink()
        && scriptInfo.isExecutable()
        && (testSource
            || (scriptStorage.isValid() && scriptStorage.isReady()
                && scriptStorage.isReadOnly())
            || (scriptInfo.ownerId() == 0
                && !(scriptInfo.permissions()
                     & (QFileDevice::WriteGroup | QFileDevice::WriteOther))));
    if (!trustedSource)
        return 1;

    QStringList arguments = app.arguments().mid(uninstallArgument + 1);
    arguments.prepend(uninstallPath);

    QProcess uninstallProcess;
    uninstallProcess.setInputChannelMode(QProcess::ForwardedInputChannel);
    uninstallProcess.setProcessChannelMode(QProcess::ForwardedChannels);
    uninstallProcess.start(QStringLiteral("/usr/bin/bash"), arguments);
    if (!uninstallProcess.waitForStarted())
        return 1;
    if (!uninstallProcess.waitForFinished(-1)
        || uninstallProcess.exitStatus() != QProcess::NormalExit)
        return 1;
    return uninstallProcess.exitCode();
}

int runQuietUpgrade(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("Omarchy Face ID"));
    QCoreApplication::setApplicationVersion(
        QStringLiteral(OMARCHY_FACE_ID_VERSION));
    QCoreApplication::setOrganizationName(QStringLiteral("Omarchy Community"));

    GazeClient gazeClient;
    QTextStream output(stdout);
    QTextStream error(stderr);
    if (!gazeClient.existingEnrollment()) {
        error << "--upgrade-quietly is only available after Face ID has been "
                 "set up.\n";
        return 2;
    }

    bool activationStarted = false;
    std::function<void()> startActivation = [&] {
        if (activationStarted)
            return;
        activationStarted = true;
        output << "Updating the Omarchy Face ID integration…" << Qt::endl;
        gazeClient.enableLockIntegration();
        if (!gazeClient.lockIntegrationInstalling()
            && !gazeClient.lockIntegrationError().isEmpty()) {
            error << gazeClient.lockIntegrationError() << Qt::endl;
            app.exit(1);
        }
    };

    QObject::connect(&gazeClient, &GazeClient::faceSetupChanged, &app, [&] {
        if (gazeClient.faceSetupInstalling())
            return;
        if (!gazeClient.faceSetupError().isEmpty()) {
            error << gazeClient.faceSetupError() << Qt::endl;
            app.exit(1);
            return;
        }
        if (!gazeClient.systemIntegrationReady()) {
            error << "Face ID system integration did not validate." << Qt::endl;
            app.exit(1);
            return;
        }
        startActivation();
    });
    QObject::connect(
        &gazeClient, &GazeClient::lockIntegrationActivationFinished, &app,
        [&](bool filesInstalled, bool liveActive) {
            if (filesInstalled && liveActive) {
                output << "Face ID upgraded to " << OMARCHY_FACE_ID_VERSION
                       << "." << Qt::endl;
                app.exit(0);
                return;
            }
            const QString message = gazeClient.lockIntegrationError();
            error << (message.isEmpty()
                          ? QStringLiteral("Face ID activation did not finish.")
                          : message)
                  << Qt::endl;
            app.exit(1);
        });

    QTimer::singleShot(0, &app, [&] {
        output << "Quietly upgrading Face ID to " << OMARCHY_FACE_ID_VERSION
               << "…" << Qt::endl;
        if (gazeClient.systemIntegrationReady()) {
            startActivation();
            return;
        }
        output << "Updating Face ID system integration…" << Qt::endl;
        gazeClient.installFaceSetupQuietly();
        if (!gazeClient.faceSetupInstalling()
            && !gazeClient.faceSetupError().isEmpty()) {
            error << gazeClient.faceSetupError() << Qt::endl;
            app.exit(1);
        }
    });
    return app.exec();
}
}

int main(int argc, char *argv[])
{
    bool allowDowngrade = false;
    bool quietUpgrade = false;
    for (int index = 1; index < argc; ++index) {
        if (std::strcmp(argv[index], "--version") == 0) {
            std::printf("Omarchy Face ID %s\n", OMARCHY_FACE_ID_VERSION);
            return 0;
        }
        if (std::strcmp(argv[index], "--uninstall") == 0)
            return runUninstaller(argc, argv);
        if (std::strcmp(argv[index], "--allow-downgrade") == 0)
            allowDowngrade = true;
        if (std::strcmp(argv[index], "--upgrade-quietly") == 0)
            quietUpgrade = true;
    }

    if (allowDowngrade)
        qputenv("OMARCHY_FACE_ID_ALLOW_DOWNGRADE", "1");
    if (quietUpgrade)
        return runQuietUpgrade(argc, argv);

    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("Omarchy Face ID"));
    QCoreApplication::setApplicationVersion(
        QStringLiteral(OMARCHY_FACE_ID_VERSION));
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
        QObject::connect(&gazeClient,
                         &GazeClient::lockIntegrationActivationFinished,
                         &app,
                         [&app](bool, bool liveActive) {
                             app.exit(liveActive ? 0 : 1);
                         });
        QTimer::singleShot(0, &gazeClient, &GazeClient::enableLockIntegration);
        const int configuredTimeout = qEnvironmentVariableIntValue(
            "OMARCHY_FACE_ID_ACTIVATION_TIMEOUT_MS");
        QTimer::singleShot((configuredTimeout > 0 ? configuredTimeout : 15000) + 1000,
                           &app, [&app]() { app.exit(2); });
    }

    return app.exec();
}
