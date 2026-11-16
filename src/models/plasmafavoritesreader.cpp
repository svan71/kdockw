// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "plasmafavoritesreader.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFileInfo>
#include <QProcessEnvironment>
#include <QSet>
#include <QStandardPaths>

#include <KConfig>
#include <KConfigGroup>

namespace kdockw
{

namespace
{
constexpr auto kickoffPlugin = "org.kde.plasma.kickoff";
constexpr auto kickoffFavoriteClientPrefix = "org.kde.plasma.kickoff.favorites.instance-";

QStringList kickoffAppletIds(const QString &appletsrcPath)
{
    if (!QFileInfo::exists(appletsrcPath)) {
        return {};
    }

    KConfig appletConfig(appletsrcPath, KConfig::SimpleConfig | KConfig::NoGlobals);
    const KConfigGroup containments = appletConfig.group(QStringLiteral("Containments"));
    QStringList ids;
    for (const QString &containmentId : containments.groupList()) {
        const KConfigGroup applets = containments.group(containmentId).group(QStringLiteral("Applets"));
        for (const QString &appletId : applets.groupList()) {
            if (applets.group(appletId).readEntry("plugin", QString()) == QLatin1String(kickoffPlugin)) {
                ids.append(appletId);
            }
        }
    }
    ids.removeDuplicates();
    return ids;
}

void appendOrderedFavorites(const KConfig &config, const QString &groupName,
                            QStringList &ids, QSet<QString> &seen, bool &foundGroup)
{
    if (!config.hasGroup(groupName)) {
        return;
    }
    foundGroup = true;
    const QStringList ordering = config.group(groupName).readEntry("ordering", QStringList{});
    for (const QString &id : ordering) {
        if (!id.isEmpty() && !seen.contains(id)) {
            seen.insert(id);
            ids.append(id);
        }
    }
}
}

PlasmaFavoritesReader::PlasmaFavoritesReader(QObject *parent)
    : QObject(parent)
{
}

bool PlasmaFavoritesReader::ready() const
{
    return m_ready;
}

bool PlasmaFavoritesReader::available() const
{
    return m_available;
}

QStringList PlasmaFavoritesReader::favoriteIds() const
{
    return m_favoriteIds;
}

void PlasmaFavoritesReader::requestSnapshot()
{
    if (m_requestStarted) {
        return;
    }
    m_requestStarted = true;

    const QDBusMessage request = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.ActivityManager"),
        QStringLiteral("/ActivityManager/Activities"),
        QStringLiteral("org.kde.ActivityManager.Activities"),
        QStringLiteral("CurrentActivity"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(request), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *finished) {
        const QDBusPendingReply<QString> reply = *finished;
        finished->deleteLater();
        if (reply.isError() || reply.value().isEmpty()) {
            setSnapshot({{QStringLiteral("available"), false}, {QStringLiteral("favoriteIds"), QStringList{}}});
            return;
        }

        QString configHome = QProcessEnvironment::systemEnvironment()
                                 .value(QStringLiteral("KDOCKW_PLASMA_CONFIG_HOME"));
        if (configHome.isEmpty()) {
            configHome = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
        }
        setSnapshot(readSnapshot(configHome, reply.value()));
    });
}

QVariantMap PlasmaFavoritesReader::readSnapshot(const QString &configHome, const QString &activityId)
{
    if (configHome.isEmpty() || activityId.isEmpty()) {
        return {{QStringLiteral("available"), false}, {QStringLiteral("favoriteIds"), QStringList{}}};
    }

    const QDir configDirectory(configHome);
    const QStringList appletIds = kickoffAppletIds(configDirectory.filePath(
        QStringLiteral("plasma-org.kde.plasma.desktop-appletsrc")));
    const QString statsPath = configDirectory.filePath(QStringLiteral("kactivitymanagerd-statsrc"));
    if (appletIds.isEmpty() || !QFileInfo::exists(statsPath)) {
        return {{QStringLiteral("available"), false}, {QStringLiteral("favoriteIds"), QStringList{}}};
    }

    KConfig stats(statsPath, KConfig::SimpleConfig | KConfig::NoGlobals);
    QStringList ids;
    QSet<QString> seen;
    bool foundGroup = false;
    for (const QString &appletId : appletIds) {
        const QString client = QString::fromLatin1(kickoffFavoriteClientPrefix) + appletId;
        appendOrderedFavorites(stats,
            QStringLiteral("Favorites-") + client + QLatin1Char('-') + activityId,
            ids, seen, foundGroup);
        appendOrderedFavorites(stats,
            QStringLiteral("Favorites-") + client + QStringLiteral("-global"),
            ids, seen, foundGroup);
    }

    return {{QStringLiteral("available"), foundGroup}, {QStringLiteral("favoriteIds"), ids}};
}

void PlasmaFavoritesReader::setSnapshot(const QVariantMap &snapshot)
{
    const bool available = snapshot.value(QStringLiteral("available")).toBool();
    const QStringList ids = snapshot.value(QStringLiteral("favoriteIds")).toStringList();
    const bool changed = !m_ready || m_available != available || m_favoriteIds != ids;
    m_ready = true;
    m_available = available;
    m_favoriteIds = ids;
    if (changed) {
        Q_EMIT snapshotChanged();
    }
}

} // namespace kdockw
