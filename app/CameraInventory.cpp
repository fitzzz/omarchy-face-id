// SPDX-License-Identifier: GPL-3.0-or-later

#include "CameraInventory.h"

#include "DiagnosticLog.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QTextStream>

#include <algorithm>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace {
struct Selections {
    QString rgb;
    QString ir;
};

struct Capabilities {
    bool querySucceeded = false;
    bool captureCapable = false;
    bool supportsMjpeg = false;
    bool supportsYuyv = false;
    bool supportsNv12 = false;
    bool supportsGray = false;
    quint32 mask = 0;
    int formatCount = 0;
    quint32 maximumWidth = 0;
    quint32 maximumHeight = 0;
    QString driver;
};

QString readTrimmed(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    return QString::fromLatin1(file.readAll()).trimmed().toLower();
}

Selections readSelections(const QString &path)
{
    QFile config(path);
    if (!config.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};

    Selections selections;
    bool inCameras = false;
    const QRegularExpression entry(
        QStringLiteral("^\\s*(rgb|ir)\\s*=\\s*[\\\"']([^\\\"']*)"));
    QTextStream stream(&config);
    while (!stream.atEnd()) {
        const QString line = stream.readLine().trimmed();
        if (line.startsWith(QLatin1Char('['))) {
            inCameras = line == QStringLiteral("[cameras]");
            continue;
        }
        if (!inCameras)
            continue;
        const auto match = entry.match(line);
        if (!match.hasMatch())
            continue;
        if (match.captured(1) == QStringLiteral("rgb"))
            selections.rgb = match.captured(2).trimmed();
        else
            selections.ir = match.captured(2).trimmed();
    }
    return selections;
}

QString selectionMode(const QString &selection)
{
    if (selection.isEmpty()) return QStringLiteral("none");
    if (selection == QStringLiteral("primary")) return QStringLiteral("primary");
    if (selection.startsWith(QStringLiteral("pipewiresrc")))
        return QStringLiteral("pipewire");
    if (selection.startsWith(QStringLiteral("/dev/video")))
        return QStringLiteral("v4l2");
    if (selection.startsWith(QStringLiteral("usb:")))
        return QStringLiteral("usb");
    return QStringLiteral("custom");
}

bool selectionMatches(const QString &selection,
                      const QString &nodeName,
                      const QString &vendor,
                      const QString &product)
{
    if (selection.startsWith(QStringLiteral("/dev/video")))
        return QFileInfo(selection).fileName() == nodeName;

    const QRegularExpression usb(
        QStringLiteral("^usb:([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})$"));
    const auto match = usb.match(selection);
    return match.hasMatch()
        && match.captured(1).compare(vendor, Qt::CaseInsensitive) == 0
        && match.captured(2).compare(product, Qt::CaseInsensitive) == 0;
}

Capabilities queryCapabilities(const QString &node)
{
    Capabilities result;
    const QByteArray encoded = QFile::encodeName(node);
    const int descriptor = open(encoded.constData(), O_RDONLY | O_NONBLOCK);
    if (descriptor < 0)
        return result;

    v4l2_capability capability{};
    if (ioctl(descriptor, VIDIOC_QUERYCAP, &capability) == 0) {
        result.querySucceeded = true;
        result.mask = capability.device_caps != 0
            ? capability.device_caps : capability.capabilities;
        result.captureCapable = (result.mask & V4L2_CAP_VIDEO_CAPTURE) != 0
            || (result.mask & V4L2_CAP_VIDEO_CAPTURE_MPLANE) != 0;
        result.driver = QString::fromLatin1(
            reinterpret_cast<const char *>(capability.driver)).trimmed();

        for (const quint32 type : {quint32(V4L2_BUF_TYPE_VIDEO_CAPTURE),
                                  quint32(V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE)}) {
            v4l2_fmtdesc format{};
            format.type = type;
            for (format.index = 0; ioctl(descriptor, VIDIOC_ENUM_FMT, &format) == 0;
                 ++format.index) {
                ++result.formatCount;
                result.supportsMjpeg = result.supportsMjpeg
                    || format.pixelformat == V4L2_PIX_FMT_MJPEG
                    || format.pixelformat == V4L2_PIX_FMT_JPEG;
                result.supportsYuyv = result.supportsYuyv
                    || format.pixelformat == V4L2_PIX_FMT_YUYV;
                result.supportsNv12 = result.supportsNv12
                    || format.pixelformat == V4L2_PIX_FMT_NV12;
                result.supportsGray = result.supportsGray
                    || format.pixelformat == V4L2_PIX_FMT_GREY;

                v4l2_frmsizeenum size{};
                size.pixel_format = format.pixelformat;
                for (size.index = 0; ioctl(descriptor, VIDIOC_ENUM_FRAMESIZES, &size) == 0;
                     ++size.index) {
                    quint32 width = 0;
                    quint32 height = 0;
                    if (size.type == V4L2_FRMSIZE_TYPE_DISCRETE) {
                        width = size.discrete.width;
                        height = size.discrete.height;
                    } else if (size.type == V4L2_FRMSIZE_TYPE_STEPWISE
                               || size.type == V4L2_FRMSIZE_TYPE_CONTINUOUS) {
                        width = size.stepwise.max_width;
                        height = size.stepwise.max_height;
                    }
                    result.maximumWidth = std::max(result.maximumWidth, width);
                    result.maximumHeight = std::max(result.maximumHeight, height);
                }
            }
        }
    }
    close(descriptor);
    return result;
}

QString transportFor(const QString &canonicalPath)
{
    if (canonicalPath.contains(QStringLiteral("/usb"))) return QStringLiteral("usb");
    if (canonicalPath.contains(QStringLiteral("/pci"))) return QStringLiteral("pci");
    if (canonicalPath.contains(QStringLiteral("/virtual/"))) return QStringLiteral("virtual");
    return QStringLiteral("platform");
}
}

void CameraInventory::recordSnapshot(DiagnosticLog &log,
                                     const QString &gazeConfigPath,
                                     const QString &trigger)
{
    const Selections selections = readSelections(gazeConfigPath);
    QDir videoClass(QStringLiteral("/sys/class/video4linux"));
    const QStringList nodes = videoClass.entryList(
        {QStringLiteral("video*")}, QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);

    bool rgbResolved = false;
    bool irResolved = false;
    for (int index = 0; index < nodes.size(); ++index) {
        const QString nodeName = nodes.at(index);
        const QString sysfsPath = videoClass.filePath(nodeName);
        const QString canonicalPath = QFileInfo(sysfsPath).canonicalFilePath();

        QString vendor;
        QString product;
        QDir parent(canonicalPath);
        for (int depth = 0; depth < 8; ++depth) {
            if (vendor.isEmpty()) vendor = readTrimmed(parent.filePath("idVendor"));
            if (product.isEmpty()) product = readTrimmed(parent.filePath("idProduct"));
            if (!vendor.isEmpty() && !product.isEmpty()) break;
            if (!parent.cdUp()) break;
        }
        if (!QRegularExpression(QStringLiteral("^[0-9a-f]{4}$")).match(vendor).hasMatch())
            vendor = QStringLiteral("unknown");
        if (!QRegularExpression(QStringLiteral("^[0-9a-f]{4}$")).match(product).hasMatch())
            product = QStringLiteral("unknown");

        const bool configuredRgb = selectionMatches(
            selections.rgb, nodeName, vendor, product);
        const bool configuredIr = selectionMatches(
            selections.ir, nodeName, vendor, product);
        rgbResolved = rgbResolved || configuredRgb;
        irResolved = irResolved || configuredIr;
        const Capabilities capabilities = queryCapabilities(
            QStringLiteral("/dev/") + nodeName);

        log.record(
            QStringLiteral("camera.inventory"),
            QStringLiteral("node_observed"),
            DiagnosticLog::Level::Debug,
            {{QStringLiteral("trigger"), trigger},
             {QStringLiteral("camera_slot"), index},
             {QStringLiteral("transport"), transportFor(canonicalPath)},
             {QStringLiteral("vendor_id"), vendor},
             {QStringLiteral("product_id"), product},
             {QStringLiteral("query_success"), capabilities.querySucceeded},
             {QStringLiteral("driver"), capabilities.driver},
             {QStringLiteral("capture_capable"), capabilities.captureCapable},
             {QStringLiteral("format_count"), capabilities.formatCount},
             {QStringLiteral("maximum_width"), static_cast<qint64>(capabilities.maximumWidth)},
             {QStringLiteral("maximum_height"), static_cast<qint64>(capabilities.maximumHeight)},
             {QStringLiteral("supports_mjpeg"), capabilities.supportsMjpeg},
             {QStringLiteral("supports_yuyv"), capabilities.supportsYuyv},
             {QStringLiteral("supports_nv12"), capabilities.supportsNv12},
             {QStringLiteral("supports_gray"), capabilities.supportsGray},
             {QStringLiteral("configured_rgb"), configuredRgb},
             {QStringLiteral("configured_ir"), configuredIr},
             {QStringLiteral("caps_mask"),
              QStringLiteral("0x%1").arg(capabilities.mask, 0, 16)}});
    }

    log.record(
        QStringLiteral("camera.inventory"),
        QStringLiteral("selection_observed"),
        DiagnosticLog::Level::Info,
        {{QStringLiteral("trigger"), trigger},
         {QStringLiteral("node_count"), nodes.size()},
         {QStringLiteral("rgb_mode"), selectionMode(selections.rgb)},
         {QStringLiteral("ir_mode"), selectionMode(selections.ir)},
         {QStringLiteral("rgb_resolved"), rgbResolved},
         {QStringLiteral("ir_resolved"), irResolved}});
}
