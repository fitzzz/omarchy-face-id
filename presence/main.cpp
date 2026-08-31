// SPDX-License-Identifier: GPL-3.0-or-later

#include "DiagnosticLog.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>

#include <gst/app/gstappsink.h>
#include <gst/gst.h>

#include <fcntl.h>
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <cmath>
#include <utility>

namespace {
constexpr int frameWidth = 160;
constexpr int frameHeight = 120;
constexpr int ignoredWarmupFrames = 3;

struct PresenceConfig {
    QString rgbSelection = QStringLiteral("primary");
    QString sensitivity = QStringLiteral("medium");
};

struct Thresholds {
    double meanDifference;
    double changedRatio;
};

PresenceConfig readConfig(const QString &path)
{
    PresenceConfig config;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return config;

    QString section;
    QTextStream stream(&file);
    while (!stream.atEnd()) {
        const QString line = stream.readLine().trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        const auto sectionMatch = QRegularExpression(
            QStringLiteral("^\\[([a-z_]+)\\]$")).match(line);
        if (sectionMatch.hasMatch()) {
            section = sectionMatch.captured(1);
            continue;
        }
        const auto valueMatch = QRegularExpression(
            QStringLiteral("^([a-z_]+)\\s*=\\s*[\"']([^\"']+)[\"']"))
                                    .match(line);
        if (!valueMatch.hasMatch())
            continue;
        if (section == QStringLiteral("lock_screen")
            && valueMatch.captured(1) == QStringLiteral("motion_sensitivity")) {
            const QString value = valueMatch.captured(2);
            if (value == QStringLiteral("low") || value == QStringLiteral("medium")
                || value == QStringLiteral("high"))
                config.sensitivity = value;
        } else if (section == QStringLiteral("cameras")
                   && valueMatch.captured(1) == QStringLiteral("rgb")) {
            config.rgbSelection = valueMatch.captured(2);
        }
    }

    // Gaze owns camera selection. Its config is separate from this app's
    // behavior config, so read it after the local settings.
    QFile gaze(qEnvironmentVariable(
        "OMARCHY_FACE_ID_GAZE_CONFIG", QStringLiteral("/etc/gaze/config.toml")));
    if (gaze.open(QIODevice::ReadOnly | QIODevice::Text)) {
        section.clear();
        QTextStream gazeStream(&gaze);
        while (!gazeStream.atEnd()) {
            const QString line = gazeStream.readLine().trimmed();
            const auto sectionMatch = QRegularExpression(
                QStringLiteral("^\\[([a-z_]+)\\]$")).match(line);
            if (sectionMatch.hasMatch()) {
                section = sectionMatch.captured(1);
                continue;
            }
            if (section != QStringLiteral("cameras"))
                continue;
            const auto rgbMatch = QRegularExpression(
                QStringLiteral("^rgb\\s*=\\s*[\"']([^\"']+)[\"']"))
                                      .match(line);
            if (rgbMatch.hasMatch()) {
                config.rgbSelection = rgbMatch.captured(1);
                break;
            }
        }
    }
    return config;
}

Thresholds thresholdsFor(const QString &sensitivity)
{
    if (sensitivity == QStringLiteral("high")) return {5.0, 0.03};
    if (sensitivity == QStringLiteral("low")) return {12.0, 0.12};
    return {8.0, 0.06};
}

bool captureCapable(const QString &node)
{
    const QByteArray encoded = QFile::encodeName(node);
    const int descriptor = open(encoded.constData(), O_RDONLY | O_NONBLOCK);
    if (descriptor < 0)
        return false;
    v4l2_capability capability{};
    const bool queried = ioctl(descriptor, VIDIOC_QUERYCAP, &capability) == 0;
    close(descriptor);
    if (!queried)
        return false;
    const quint32 mask = capability.device_caps != 0
        ? capability.device_caps : capability.capabilities;
    return (mask & V4L2_CAP_VIDEO_CAPTURE) != 0
        || (mask & V4L2_CAP_VIDEO_CAPTURE_MPLANE) != 0;
}

QString firstCaptureNode()
{
    QDir devices(QStringLiteral("/dev"));
    const QStringList nodes = devices.entryList(
        {QStringLiteral("video*")}, QDir::System | QDir::Files, QDir::Name);
    for (const QString &node : nodes) {
        const QString path = devices.filePath(node);
        if (captureCapable(path))
            return path;
    }
    return {};
}

QString usbCaptureNode(const QString &selection)
{
    const auto match = QRegularExpression(
        QStringLiteral("^usb:([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})$"))
                           .match(selection);
    if (!match.hasMatch())
        return {};

    QDir videoClass(QStringLiteral("/sys/class/video4linux"));
    const QStringList nodes = videoClass.entryList(
        {QStringLiteral("video*")}, QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &node : nodes) {
        QDir parent(QFileInfo(videoClass.filePath(node)).canonicalFilePath());
        QString vendor;
        QString product;
        for (int depth = 0; depth < 8; ++depth) {
            QFile vendorFile(parent.filePath(QStringLiteral("idVendor")));
            if (vendor.isEmpty() && vendorFile.open(QIODevice::ReadOnly))
                vendor = QString::fromLatin1(vendorFile.readAll()).trimmed();
            QFile productFile(parent.filePath(QStringLiteral("idProduct")));
            if (product.isEmpty() && productFile.open(QIODevice::ReadOnly))
                product = QString::fromLatin1(productFile.readAll()).trimmed();
            if (!vendor.isEmpty() && !product.isEmpty()) break;
            if (!parent.cdUp()) break;
        }
        if (vendor.compare(match.captured(1), Qt::CaseInsensitive) == 0
            && product.compare(match.captured(2), Qt::CaseInsensitive) == 0) {
            const QString path = QStringLiteral("/dev/") + node;
            if (captureCapable(path))
                return path;
        }
    }
    return {};
}

QString sourceFor(const QString &selection)
{
    const QString testSource = qEnvironmentVariable(
        "OMARCHY_FACE_ID_PRESENCE_TEST_SOURCE");
    if (!testSource.isEmpty())
        return testSource;
    if (selection == QStringLiteral("primary"))
        return QStringLiteral("pipewiresrc");
    if (QRegularExpression(QStringLiteral("^/dev/video[0-9]+$"))
            .match(selection).hasMatch()) {
        return QStringLiteral("v4l2src device=%1").arg(selection);
    }
    if (selection.startsWith(QStringLiteral("usb:"))) {
        const QString node = usbCaptureNode(selection);
        return node.isEmpty() ? QString() : QStringLiteral("v4l2src device=%1").arg(node);
    }
    if (QRegularExpression(
            QStringLiteral("^pipewiresrc(?:\\s+[A-Za-z-]+=[A-Za-z0-9_.:-]+)*$"))
            .match(selection).hasMatch()) {
        return selection;
    }
    return {};
}

int watchSource(const QString &source,
                const Thresholds &thresholds,
                int timeoutMs,
                DiagnosticLog &log,
                const QString &sourceMode)
{
    const QString pipelineDescription = source
        + QStringLiteral(
            " ! video/x-raw; image/jpeg ! decodebin ! videoconvert ! videoscale ! "
            "videorate ! video/x-raw,format=GRAY8,width=160,height=120,framerate=2/1 ! "
            "appsink name=presence-sink max-buffers=1 drop=true sync=false");
    GError *error = nullptr;
    GstElement *pipeline = gst_parse_launch(pipelineDescription.toUtf8().constData(), &error);
    if (!pipeline) {
        g_clear_error(&error);
        log.record(QStringLiteral("presence.watcher"),
                   QStringLiteral("pipeline_create_failed"),
                   DiagnosticLog::Level::Error,
                   {{QStringLiteral("source_mode"), sourceMode}});
        return 3;
    }

    GstElement *sinkElement = gst_bin_get_by_name(GST_BIN(pipeline), "presence-sink");
    if (!sinkElement) {
        gst_object_unref(pipeline);
        return 3;
    }
    auto *sink = GST_APP_SINK(sinkElement);
    const GstStateChangeReturn state = gst_element_set_state(pipeline, GST_STATE_PLAYING);
    if (state == GST_STATE_CHANGE_FAILURE) {
        gst_element_set_state(pipeline, GST_STATE_NULL);
        gst_object_unref(sinkElement);
        gst_object_unref(pipeline);
        log.record(QStringLiteral("presence.watcher"),
                   QStringLiteral("camera_start_failed"),
                   DiagnosticLog::Level::Error,
                   {{QStringLiteral("source_mode"), sourceMode}});
        return 3;
    }

    log.record(QStringLiteral("presence.watcher"),
               QStringLiteral("started"),
               DiagnosticLog::Level::Info,
               {{QStringLiteral("source_mode"), sourceMode},
                {QStringLiteral("width"), frameWidth},
                {QStringLiteral("height"), frameHeight},
                {QStringLiteral("samples_per_second"), 2}});

    QElapsedTimer elapsed;
    elapsed.start();
    QByteArray previous;
    int receivedFrames = 0;
    int motionStreak = 0;
    int emptyPolls = 0;
    int result = 3;

    while (timeoutMs <= 0 || elapsed.elapsed() < timeoutMs) {
        GstSample *sample = gst_app_sink_try_pull_sample(sink, 2 * GST_SECOND);
        if (!sample) {
            ++emptyPolls;
            if (gst_app_sink_is_eos(sink)) {
                result = 5;
                break;
            }
            if (emptyPolls >= 3) {
                result = 3;
                break;
            }
            continue;
        }
        emptyPolls = 0;
        GstBuffer *buffer = gst_sample_get_buffer(sample);
        GstMapInfo map{};
        QByteArray current;
        if (buffer && gst_buffer_map(buffer, &map, GST_MAP_READ)) {
            current = QByteArray(reinterpret_cast<const char *>(map.data),
                                 static_cast<qsizetype>(map.size));
            gst_buffer_unmap(buffer, &map);
        }
        gst_sample_unref(sample);
        if (current.size() < frameWidth * frameHeight)
            continue;

        ++receivedFrames;
        if (!previous.isEmpty() && receivedFrames > ignoredWarmupFrames) {
            quint64 totalDifference = 0;
            qsizetype changed = 0;
            const qsizetype pixels = frameWidth * frameHeight;
            for (qsizetype index = 0; index < pixels; ++index) {
                const int difference = std::abs(
                    static_cast<int>(static_cast<uchar>(current.at(index)))
                    - static_cast<int>(static_cast<uchar>(previous.at(index))));
                totalDifference += static_cast<quint64>(difference);
                if (difference >= 18)
                    ++changed;
            }
            const double mean = static_cast<double>(totalDifference) / pixels;
            const double ratio = static_cast<double>(changed) / pixels;
            motionStreak = mean >= thresholds.meanDifference
                    && ratio >= thresholds.changedRatio
                ? motionStreak + 1 : 0;
            if (motionStreak >= 2) {
                log.record(QStringLiteral("presence.watcher"),
                           QStringLiteral("motion_detected"),
                           DiagnosticLog::Level::Info,
                           {{QStringLiteral("source_mode"), sourceMode},
                            {QStringLiteral("samples"), receivedFrames}});
                result = 0;
                break;
            }
        }
        previous = std::move(current);
    }

    if (timeoutMs > 0 && elapsed.elapsed() >= timeoutMs && result == 3)
        result = 4;
    gst_element_set_state(pipeline, GST_STATE_NULL);
    gst_object_unref(sinkElement);
    gst_object_unref(pipeline);
    log.record(QStringLiteral("presence.watcher"),
               QStringLiteral("stopped"),
               result == 0 ? DiagnosticLog::Level::Info
                           : DiagnosticLog::Level::Warning,
               {{QStringLiteral("source_mode"), sourceMode},
                {QStringLiteral("result_code"), result},
                {QStringLiteral("samples"), receivedFrames}});
    return result;
}
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    gst_init(&argc, &argv);

    QString configPath = QStandardPaths::writableLocation(
        QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/omarchy-face-id/config.toml");
    int timeoutMs = 0;
    const QStringList arguments = app.arguments();
    for (int index = 1; index < arguments.size(); ++index) {
        if (arguments.at(index) == QStringLiteral("--config")
            && index + 1 < arguments.size()) {
            configPath = arguments.at(++index);
        } else if (arguments.at(index) == QStringLiteral("--timeout-ms")
                   && index + 1 < arguments.size()) {
            timeoutMs = arguments.at(++index).toInt();
        }
    }

    DiagnosticLog log;
    const PresenceConfig config = readConfig(configPath);
    const Thresholds thresholds = thresholdsFor(config.sensitivity);
    const QString source = sourceFor(config.rgbSelection);
    if (source.isEmpty()) {
        log.record(QStringLiteral("presence.watcher"),
                   QStringLiteral("camera_selection_unavailable"),
                   DiagnosticLog::Level::Error);
        return 3;
    }

    const QString sourceMode = !qEnvironmentVariable(
                                   "OMARCHY_FACE_ID_PRESENCE_TEST_SOURCE").isEmpty()
        ? QStringLiteral("synthetic_test")
        : config.rgbSelection == QStringLiteral("primary")
        ? QStringLiteral("pipewire_primary")
        : config.rgbSelection.startsWith(QStringLiteral("/dev/video"))
            ? QStringLiteral("v4l2_configured")
            : config.rgbSelection.startsWith(QStringLiteral("usb:"))
                ? QStringLiteral("usb_configured") : QStringLiteral("pipewire_configured");
    int result = watchSource(source, thresholds, timeoutMs, log, sourceMode);
    if (result == 3 && config.rgbSelection == QStringLiteral("primary")
        && qEnvironmentVariable("OMARCHY_FACE_ID_PRESENCE_TEST_SOURCE").isEmpty()) {
        const QString fallback = firstCaptureNode();
        if (!fallback.isEmpty()) {
            log.record(QStringLiteral("presence.watcher"),
                       QStringLiteral("fallback_started"),
                       DiagnosticLog::Level::Warning,
                       {{QStringLiteral("source_mode"), QStringLiteral("v4l2_fallback")}});
            result = watchSource(QStringLiteral("v4l2src device=%1").arg(fallback),
                                 thresholds, timeoutMs, log,
                                 QStringLiteral("v4l2_fallback"));
            if (result == 0)
                return 10;
        }
    }
    return result;
}
