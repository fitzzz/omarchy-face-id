#include <QCoreApplication>
#include <QFile>
#include <QJSValue>
#include <QRegularExpression>
#include <QQmlEngine>

#include <cstdlib>
#include <iostream>

namespace {

[[noreturn]] void fail(const QString &message)
{
    std::cerr << message.toStdString() << '\n';
    std::exit(EXIT_FAILURE);
}

QJSValue call(QQmlEngine &engine, const QString &name,
              const QJSValueList &arguments)
{
    QJSValue function = engine.globalObject().property(name);
    if (!function.isCallable())
        fail(QStringLiteral("LockState function is missing: %1").arg(name));

    QJSValue result = function.call(arguments);
    if (result.isError())
        fail(QStringLiteral("LockState function failed: %1: %2")
                 .arg(name, result.toString()));
    return result;
}

void expect(bool condition, const char *message)
{
    if (!condition)
        fail(QString::fromUtf8(message));
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (argc != 2)
        fail(QStringLiteral("usage: lock-state-harness PATH_TO_LockState.js"));

    QFile sourceFile(QString::fromLocal8Bit(argv[1]));
    if (!sourceFile.open(QIODevice::ReadOnly))
        fail(QStringLiteral("could not read LockState.js"));

    QString source = QString::fromUtf8(sourceFile.readAll());
    source.remove(QRegularExpression(QStringLiteral(
        R"(^\s*\.pragma\s+library\s*$)"),
        QRegularExpression::MultilineOption));

    QQmlEngine engine;
    const QJSValue evaluated = engine.evaluate(source, sourceFile.fileName());
    if (evaluated.isError())
        fail(QStringLiteral("LockState.js did not evaluate: %1").arg(evaluated.toString()));

    expect(call(engine, QStringLiteral("acceptsAttemptResult"), {4, 4, true}).toBool(),
           "current locked attempt result should be accepted");
    expect(!call(engine, QStringLiteral("acceptsAttemptResult"), {3, 4, true}).toBool(),
           "stale attempt result should be ignored");
    expect(!call(engine, QStringLiteral("acceptsAttemptResult"), {4, 4, false}).toBool(),
           "attempt result after unlock should be ignored");

    expect(call(engine, QStringLiteral("stateAfterAttempt"),
                {QStringLiteral("success"), QStringLiteral("low_power")}).toString()
               == QStringLiteral("success"),
           "successful face authentication should enter success");
    expect(call(engine, QStringLiteral("stateAfterAttempt"),
                {QStringLiteral("failed"), QStringLiteral("low_power")}).toString()
               == QStringLiteral("unauthorized"),
           "low-power rejection should enter the rejection hold");
    expect(call(engine, QStringLiteral("stateAfterAttempt"),
                {QStringLiteral("max_tries"), QStringLiteral("continuous")}).toString()
               == QStringLiteral("waiting"),
           "continuous rejection should schedule a retry");
    expect(call(engine, QStringLiteral("stateAfterAttempt"),
                {QStringLiteral("unavailable"), QStringLiteral("low_power")}).toString()
               == QStringLiteral("sleeping"),
           "camera or PAM failure should return to sleeping");

    expect(call(engine, QStringLiteral("canWake"),
                {QStringLiteral("sleeping"), true, false}).toBool(),
           "sleeping active lock should wake");
    expect(!call(engine, QStringLiteral("canWake"),
                 {QStringLiteral("checking"), true, false}).toBool(),
           "active scan should not start another wake");
    expect(!call(engine, QStringLiteral("canWake"),
                 {QStringLiteral("sleeping"), true, true}).toBool(),
           "password authentication should suppress face wake");

    expect(call(engine, QStringLiteral("canStartPresence"),
                {QStringLiteral("sleeping"), QStringLiteral("low_power"), true, false})
               .toBool(),
           "low-power sleeping state should start presence detection");
    expect(!call(engine, QStringLiteral("canStartPresence"),
                 {QStringLiteral("sleeping"), QStringLiteral("continuous"), true, false})
                .toBool(),
           "continuous mode should not start the low-power watcher");

    expect(call(engine, QStringLiteral("acceptsPresenceResult"),
                {QStringLiteral("sleeping"), QStringLiteral("low_power"), 2, 2})
               .toBool(),
           "current sleeping watcher result should be accepted");
    expect(!call(engine, QStringLiteral("acceptsPresenceResult"),
                 {QStringLiteral("waking"), QStringLiteral("low_power"), 2, 2})
                .toBool(),
           "watcher result after wake should be ignored");
    expect(!call(engine, QStringLiteral("acceptsPresenceResult"),
                 {QStringLiteral("sleeping"), QStringLiteral("low_power"), 1, 2})
                .toBool(),
           "stale watcher generation should be ignored");

    expect(call(engine, QStringLiteral("canFinishUnlock"),
                {7, 7, true, false, QStringLiteral("success")}).toBool(),
           "current success state should finish unlock");
    expect(!call(engine, QStringLiteral("canFinishUnlock"),
                 {6, 7, true, false, QStringLiteral("success")}).toBool(),
           "stale success must not finish unlock");
    expect(!call(engine, QStringLiteral("canFinishUnlock"),
                 {7, 7, true, true, QStringLiteral("success")}).toBool(),
           "password authentication remains authoritative");

    return EXIT_SUCCESS;
}
