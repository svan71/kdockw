// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QImage>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QQuickPaintedItem>
#include <QUrl>

class QNetworkReply;

namespace kdockw
{

/** Bounded asynchronous MPRIS artwork view; accepts only file/http/https URLs. */
class MediaArtworkItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)

public:
    explicit MediaArtworkItem(QQuickItem *parent = nullptr);
    QUrl source() const;
    void setSource(const QUrl &source);
    bool ready() const;
    void paint(QPainter *painter) override;

Q_SIGNALS:
    void sourceChanged();
    void readyChanged();

private:
    void loadLocal(const QUrl &url);
    void loadReply(QNetworkReply *reply, const QUrl &requestedUrl);
    void setImage(QImage image);

    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    QUrl m_source;
    QImage m_image;
    quint64 m_generation = 0;
};

} // namespace kdockw
