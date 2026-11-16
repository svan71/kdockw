// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantMap>

namespace kdockw
{

/** Reads Kickoff's existing favorites without changing Plasma configuration. */
class PlasmaFavoritesReader : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY snapshotChanged)
    Q_PROPERTY(bool available READ available NOTIFY snapshotChanged)
    Q_PROPERTY(QStringList favoriteIds READ favoriteIds NOTIFY snapshotChanged)

public:
    explicit PlasmaFavoritesReader(QObject *parent = nullptr);

    [[nodiscard]] bool ready() const;
    [[nodiscard]] bool available() const;
    [[nodiscard]] QStringList favoriteIds() const;

    Q_INVOKABLE void requestSnapshot();
    [[nodiscard]] static QVariantMap readSnapshot(const QString &configHome, const QString &activityId);

Q_SIGNALS:
    void snapshotChanged();

private:
    void setSnapshot(const QVariantMap &snapshot);

    QStringList m_favoriteIds;
    bool m_ready = false;
    bool m_available = false;
    bool m_requestStarted = false;
};

} // namespace kdockw
