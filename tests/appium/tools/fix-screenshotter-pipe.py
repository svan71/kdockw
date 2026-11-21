#!/usr/bin/env python3
"""Use a file-backed ScreenShot2 sink in the pinned test helper."""

from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: fix-screenshotter-pipe.py PATH/TO/screenshotter/main.cpp")

    path = Path(sys.argv[1])
    source = path.read_text(encoding="utf-8")
    if "memfd_create" in source:
        print("ScreenShot2 memfd patch already applied")
        return 0

    old_headers = "#include <chrono>\n#include <optional>"
    new_headers = """#include <cerrno>
#include <chrono>
#include <cstring>
#include <limits>
#include <linux/memfd.h>
#include <optional>
#include <sys/mman.h>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>"""
    if old_headers not in source:
        raise SystemExit("screenshotter patch: expected POSIX header block was not found")
    source = source.replace(old_headers, new_headers, 1)

    read_start = source.index("static QImage allocateImage(")
    read_end = source.index("\nint main(", read_start)
    read_image = r'''static QImage readImage(int fileDescriptor, const QVariantMap &metadata)
{
    bool ok = false;
    const int width = metadata.value(QStringLiteral("width")).toInt(&ok);
    if (!ok || width <= 0) {
        qWarning() << "invalid screenshot width";
        return {};
    }
    const int height = metadata.value(QStringLiteral("height")).toInt(&ok);
    if (!ok || height <= 0) {
        qWarning() << "invalid screenshot height";
        return {};
    }
    const int format = metadata.value(QStringLiteral("format")).toInt(&ok);
    if (!ok) {
        qWarning() << "invalid screenshot format";
        return {};
    }
    const int stride = metadata.value(QStringLiteral("stride")).toInt(&ok);
    if (!ok || stride <= 0) {
        qWarning() << "invalid screenshot stride";
        return {};
    }

    const qint64 expectedBytes = qint64(stride) * height;
    if (expectedBytes <= 0 || expectedBytes > std::numeric_limits<qsizetype>::max()) {
        qWarning() << "invalid screenshot byte count" << expectedBytes;
        return {};
    }

    struct stat info {};
    const auto deadline = std::chrono::steady_clock::now() + 25s;
    while (true) {
        if (fstat(fileDescriptor, &info) != 0) {
            qWarning() << "failed to inspect screenshot sink" << strerror(errno);
            return {};
        }
        if (info.st_size >= expectedBytes) {
            break;
        }
        if (std::chrono::steady_clock::now() >= deadline) {
            qWarning() << "incomplete screenshot frame" << info.st_size << "expected" << expectedBytes;
            return {};
        }
        std::this_thread::sleep_for(1ms);
    }
    if (info.st_size != expectedBytes) {
        qWarning() << "oversized screenshot frame" << info.st_size << "expected" << expectedBytes;
        return {};
    }

    QByteArray data(static_cast<qsizetype>(expectedBytes), Qt::Uninitialized);
    qint64 offset = 0;
    while (offset < expectedBytes) {
        const auto bytes = pread(fileDescriptor, data.data() + offset, static_cast<size_t>(expectedBytes - offset), offset);
        if (bytes > 0) {
            offset += bytes;
            continue;
        }
        if (bytes < 0 && errno == EINTR) {
            continue;
        }
        qWarning() << "failed to read screenshot sink" << strerror(bytes < 0 ? errno : EIO);
        return {};
    }

    QImage image(reinterpret_cast<const uchar *>(data.constData()), width, height, stride, QImage::Format(format));
    if (image.isNull()) {
        qWarning() << "failed to allocate image";
        return {};
    }
    return image.copy();
}
'''
    read_image = read_image.replace('\\"', '"')
    source = source[:read_start] + read_image + source[read_end:]

    request_start = source.index("    auto pipeFds = std::to_array<int>({0, 0});", source.index("int main("))
    request_end = source.index("    QBuffer buf;", request_start)
    request = r'''    const int screenshotFd = memfd_create("kdockw-screenshot", MFD_CLOEXEC);
    if (screenshotFd == -1) {
        qWarning() << "failed to create screenshot sink" << strerror(errno);
        return 1;
    }

    auto bus = QDBusConnection::sessionBus();
    QDBusMessage message = QDBusMessage::createMethodCall(service.value(),
                                                          QStringLiteral("/org/kde/KWin/ScreenShot2"),
                                                          QStringLiteral("org.kde.KWin.ScreenShot2"),
                                                          area ? QStringLiteral("CaptureArea") : QStringLiteral("CaptureActiveScreen"));
    if (area) {
        message << args.at(0).toInt() << args.at(1).toInt() << args.at(2).toUInt() << args.at(3).toUInt();
    }
    message << QVariantMap() << QVariant::fromValue(QDBusUnixFileDescriptor(screenshotFd));

    QDBusPendingCall msg = bus.asyncCall(message);
    msg.waitForFinished();
    QDBusReply<QVariantMap> reply = msg.reply();
    if (!reply.isValid()) {
        qWarning() << reply.error();
        ::close(screenshotFd);
        return 1;
    }

    const auto image = readImage(screenshotFd, reply.value());
    ::close(screenshotFd);
    if (image.isNull()) {
        return 1;
    }
'''
    request = request.replace('\\"', '"')
    source = source[:request_start] + request + source[request_end:]

    save_old = '    image.save(&buf, "PNG");'
    save_new = '''    if (!image.save(&buf, "PNG")) {
        qWarning() << "failed to encode screenshot as PNG";
        return 1;
    }'''
    if save_old not in source:
        raise SystemExit("screenshotter patch: expected PNG save call was not found")
    source = source.replace(save_old, save_new, 1)

    path.write_text(source, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
