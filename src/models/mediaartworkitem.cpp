// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "mediaartworkitem.h"

#include <QCache>
#include <QBuffer>
#include <QFileInfo>
#include <QImageReader>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPainter>
#include <QTimer>

namespace kdockw
{
namespace
{
constexpr qint64 kMaxBytes = 5 * 1024 * 1024;
constexpr qint64 kMaxPixels = 8 * 1024 * 1024;
constexpr int kMaxSide = 512;
QCache<QString, QImage> &artCache()
{
    static QCache<QString, QImage> cache(24 * 1024); // cost is KiB
    return cache;
}

QImage decodeArtwork(const QByteArray &bytes)
{
    if (bytes.size() > kMaxBytes) return {};
    QBuffer buffer;
    buffer.setData(bytes);
    if (!buffer.open(QIODevice::ReadOnly)) return {};
    QImageReader reader(&buffer);
    const QSize size = reader.size();
    if (!size.isValid() || size.width() <= 0 || size.height() <= 0
        || qint64(size.width()) * size.height() > kMaxPixels) return {};
    reader.setScaledSize(size.scaled(kMaxSide, kMaxSide, Qt::KeepAspectRatio));
    return reader.read();
}
} // namespace

MediaArtworkItem::MediaArtworkItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    setOpaquePainting(false);
}

QUrl MediaArtworkItem::source() const { return m_source; }
bool MediaArtworkItem::ready() const { return !m_image.isNull(); }

void MediaArtworkItem::setSource(const QUrl &source)
{
    if (m_source == source) return;
    if (m_reply) m_reply->abort();
    m_reply.clear();
    m_source = source;
    ++m_generation;
    const quint64 generation = m_generation;
    setImage({});
    Q_EMIT sourceChanged();
    if (!source.isValid() || source.isEmpty()) return;
    if (source.scheme() != QLatin1String("file") && source.scheme() != QLatin1String("http")
        && source.scheme() != QLatin1String("https")) return;
    const QString key = source.toString(QUrl::FullyEncoded);
    if (QImage *cached = artCache().object(key)) {
        setImage(*cached);
        return;
    }
    if (source.isLocalFile()) {
        loadLocal(source);
        return;
    }

    QNetworkRequest request(source);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setTransferTimeout(8000);
    QNetworkReply *reply = m_network.get(request);
    m_reply = reply;
    connect(reply, &QNetworkReply::downloadProgress, reply, [reply](qint64 received, qint64) {
        if (received > kMaxBytes) reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, source, generation] {
        if (m_reply == reply) m_reply.clear();
        if (generation != m_generation) { reply->deleteLater(); return; }
        loadReply(reply, source);
    });
}

void MediaArtworkItem::loadLocal(const QUrl &url)
{
    const QFileInfo info(url.toLocalFile());
    if (!info.isFile() || info.size() <= 0 || info.size() > kMaxBytes) return;
    QImageReader reader(info.filePath());
    const QSize size = reader.size();
    if (!size.isValid() || qint64(size.width()) * size.height() > kMaxPixels) return;
    reader.setScaledSize(size.scaled(kMaxSide, kMaxSide, Qt::KeepAspectRatio));
    QImage image = reader.read();
    if (!image.isNull()) {
        artCache().insert(url.toString(QUrl::FullyEncoded), new QImage(image), int(qMax<qint64>(1, image.sizeInBytes() / 1024)));
        setImage(std::move(image));
    }
}

void MediaArtworkItem::loadReply(QNetworkReply *reply, const QUrl &requestedUrl)
{
    const QUrl finalUrl = reply->url();
    const bool allowedFinalUrl = finalUrl.scheme() == QLatin1String("http") || finalUrl.scheme() == QLatin1String("https");
    const QByteArray bytes = allowedFinalUrl && reply->error() == QNetworkReply::NoError && reply->bytesAvailable() <= kMaxBytes
        ? reply->readAll() : QByteArray();
    reply->deleteLater();
    QImage image = decodeArtwork(bytes);
    if (!image.isNull()) {
        artCache().insert(requestedUrl.toString(QUrl::FullyEncoded), new QImage(image), int(qMax<qint64>(1, image.sizeInBytes() / 1024)));
        setImage(std::move(image));
    }
}

void MediaArtworkItem::setImage(QImage image)
{
    if (m_image.size() == image.size() && m_image.cacheKey() == image.cacheKey()) return;
    const bool wasReady = ready();
    m_image = std::move(image);
    update();
    if (wasReady != ready()) Q_EMIT readyChanged();
}

void MediaArtworkItem::paint(QPainter *painter)
{
    if (m_image.isNull() || width() <= 0 || height() <= 0) return;
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    painter->drawImage(QRectF(0, 0, width(), height()), m_image);
}

} // namespace kdockw
