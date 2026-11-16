// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "applicationlauncherstate.h"

#include "kdockw.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QUuid>

#include <algorithm>

namespace kdockw
{

namespace
{
QString normalizedStyle(const QString &style)
{
    if (style == QLatin1String("start") || style == QLatin1String("hierarchical")) {
        return style;
    }
    return QStringLiteral("launchpad");
}

QVariantList decodeFolders(const QString &encoded)
{
    const QJsonDocument document = QJsonDocument::fromJson(encoded.toUtf8());
    if (!document.isArray()) {
        return {};
    }

    QVariantList result;
    QSet<QString> seenApplications;
    QSet<QString> seenFolderIds;
    for (const QJsonValue &value : document.array()) {
        if (!value.isObject()) {
            continue;
        }
        const QJsonObject object = value.toObject();
        QString id = object.value(QStringLiteral("id")).toString();
        const QString name = object.value(QStringLiteral("name")).toString().trimmed();
        if (id.isEmpty() || name.isEmpty() || seenFolderIds.contains(id)) {
            continue;
        }
        if (!id.startsWith(QLatin1String("folder:"))) {
            id.prepend(QStringLiteral("folder:"));
        }
        seenFolderIds.insert(id);
        QStringList applicationIds;
        for (const QJsonValue &application : object.value(QStringLiteral("applicationIds")).toArray()) {
            const QString applicationId = application.toString();
            if (!applicationId.isEmpty() && !seenApplications.contains(applicationId)) {
                seenApplications.insert(applicationId);
                applicationIds.append(applicationId);
            }
        }
        result.append(QVariantMap{
            {QStringLiteral("id"), id},
            {QStringLiteral("type"), QStringLiteral("folder")},
            {QStringLiteral("name"), name},
            {QStringLiteral("applicationIds"), applicationIds},
        });
    }
    return result;
}

QString encodeFolders(const QVariantList &folders)
{
    QJsonArray result;
    for (const QVariant &value : folders) {
        const QVariantMap folder = value.toMap();
        QJsonArray applicationIds;
        for (const QString &applicationId : folder.value(QStringLiteral("applicationIds")).toStringList()) {
            applicationIds.append(applicationId);
        }
        result.append(QJsonObject{
            {QStringLiteral("id"), folder.value(QStringLiteral("id")).toString()},
            {QStringLiteral("name"), folder.value(QStringLiteral("name")).toString()},
            {QStringLiteral("applicationIds"), applicationIds},
        });
    }
    return QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact));
}

QStringList uniqueNonEmpty(const QStringList &values)
{
    QStringList result;
    QSet<QString> seen;
    for (const QString &value : values) {
        if (!value.isEmpty() && !seen.contains(value)) {
            seen.insert(value);
            result.append(value);
        }
    }
    return result;
}
}

ApplicationLauncherState::ApplicationLauncherState(KDockWSettings *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
{
    if (m_settings) {
        m_style = normalizedStyle(m_settings->applicationLauncherStyle());
        m_pinnedApplicationIds = m_settings->startPinnedApplications();
        m_startFavoritesImportAttempted = m_settings->startFavoritesImportAttempted();
        m_startFavoritesImportStatus = m_settings->startFavoritesImportStatus();
        m_launchpadFolders = decodeFolders(m_settings->launchpadFolders());
        m_launchpadItemOrder = uniqueNonEmpty(m_settings->launchpadItemOrder());
        connect(m_settings, &KDockWSettings::ApplicationLauncherStyleChanged, this, [this] {
            const QString style = normalizedStyle(m_settings->applicationLauncherStyle());
            if (m_style != style) {
                m_style = style;
                Q_EMIT styleChanged();
            }
        });
        connect(m_settings, &KDockWSettings::StartPinnedApplicationsChanged, this, [this] {
            if (m_pinnedApplicationIds != m_settings->startPinnedApplications()) {
                m_pinnedApplicationIds = m_settings->startPinnedApplications();
                Q_EMIT pinnedApplicationIdsChanged();
            }
        });
    } else {
        m_style = QStringLiteral("launchpad");
    }
}

QString ApplicationLauncherState::style() const
{
    return m_style;
}

void ApplicationLauncherState::setStyle(const QString &style)
{
    const QString normalized = normalizedStyle(style);
    if (m_style == normalized) {
        return;
    }
    m_style = normalized;
    if (m_settings) {
        m_settings->setApplicationLauncherStyle(m_style);
    }
    Q_EMIT styleChanged();
}

QStringList ApplicationLauncherState::pinnedApplicationIds() const
{
    return m_pinnedApplicationIds;
}

QVariantList ApplicationLauncherState::launchpadFolders() const
{
    return m_launchpadFolders;
}

QStringList ApplicationLauncherState::launchpadItemOrder() const
{
    return m_launchpadItemOrder;
}

bool ApplicationLauncherState::startFavoritesImportAttempted() const
{
    return m_startFavoritesImportAttempted;
}

QString ApplicationLauncherState::startFavoritesImportStatus() const
{
    return m_startFavoritesImportStatus;
}

bool ApplicationLauncherState::importPlasmaFavorites(const QStringList &favoriteIds,
                                                      const QStringList &availableApplicationIds,
                                                      bool sourceAvailable,
                                                      bool sourceReady)
{
    const bool retryLegacyPreservedPins = m_startFavoritesImportAttempted
        && m_startFavoritesImportStatus == QLatin1String("existingPinsPreserved")
        && !m_pinnedApplicationIds.isEmpty();
    if (m_startFavoritesImportAttempted && !retryLegacyPreservedPins) {
        return false;
    }

    if (!sourceReady) {
        return false;
    }

    QString status;
    if (!sourceAvailable) {
        status = QStringLiteral("unavailable");
    } else {
        QSet<QString> available;
        for (const QString &id : availableApplicationIds) {
            available.insert(id);
        }
        QSet<QString> seen;
        for (const QString &id : m_pinnedApplicationIds) {
            seen.insert(id);
        }
        QStringList imported;
        for (QString id : favoriteIds) {
            if (id.startsWith(QLatin1String("applications:"))) {
                id.remove(0, QStringLiteral("applications:").size());
            }
            if (id.isEmpty() || !available.contains(id) || seen.contains(id)) {
                continue;
            }
            seen.insert(id);
            imported.append(id);
        }
        if (!imported.isEmpty()) {
            m_pinnedApplicationIds.append(imported);
            status = retryLegacyPreservedPins
                ? QStringLiteral("existingPinsPlusPlasmaFavorites")
                : QStringLiteral("imported");
            Q_EMIT pinnedApplicationIdsChanged();
            if (m_settings) {
                m_settings->setStartPinnedApplications(m_pinnedApplicationIds);
            }
        } else if (!m_pinnedApplicationIds.isEmpty()) {
            status = retryLegacyPreservedPins
                ? QStringLiteral("existingPinsChecked")
                : QStringLiteral("existingPinsPreserved");
        } else if (favoriteIds.isEmpty()) {
            status = QStringLiteral("noFavorites");
        } else {
            status = QStringLiteral("noMatchingApps");
        }
    }
    m_startFavoritesImportAttempted = sourceAvailable;
    if (m_startFavoritesImportStatus != status) {
        m_startFavoritesImportStatus = status;
        Q_EMIT startFavoritesImportStatusChanged();
    }
    if (m_settings) {
        m_settings->setStartFavoritesImportAttempted(m_startFavoritesImportAttempted);
        m_settings->setStartFavoritesImportStatus(m_startFavoritesImportStatus);
    }
    return status == QLatin1String("imported")
        || status == QLatin1String("existingPinsPlusPlasmaFavorites");
}

bool ApplicationLauncherState::isPinned(const QString &serviceId) const
{
    return m_pinnedApplicationIds.contains(serviceId);
}

void ApplicationLauncherState::togglePinned(const QString &serviceId)
{
    if (serviceId.isEmpty()) {
        return;
    }
    if (m_pinnedApplicationIds.removeAll(serviceId) == 0) {
        m_pinnedApplicationIds.append(serviceId);
    }
    if (m_settings) {
        m_settings->setStartPinnedApplications(m_pinnedApplicationIds);
    }
    Q_EMIT pinnedApplicationIdsChanged();
}

bool ApplicationLauncherState::movePinned(int fromIndex, int toIndex)
{
    if (fromIndex < 0 || fromIndex >= m_pinnedApplicationIds.size()
        || toIndex < 0 || toIndex >= m_pinnedApplicationIds.size() || fromIndex == toIndex) {
        return false;
    }
    m_pinnedApplicationIds.move(fromIndex, toIndex);
    if (m_settings) {
        m_settings->setStartPinnedApplications(m_pinnedApplicationIds);
    }
    Q_EMIT pinnedApplicationIdsChanged();
    return true;
}

void ApplicationLauncherState::setLaunchpadItemOrder(const QStringList &itemIds)
{
    const QStringList normalized = uniqueNonEmpty(itemIds);
    if (m_launchpadItemOrder == normalized) {
        return;
    }
    m_launchpadItemOrder = normalized;
    if (m_settings) {
        m_settings->setLaunchpadItemOrder(m_launchpadItemOrder);
    }
    Q_EMIT launchpadItemOrderChanged();
}

QString ApplicationLauncherState::createLaunchpadFolder(const QString &name,
                                                          const QStringList &applicationIds,
                                                          const QStringList &currentRootOrder)
{
    const QString normalizedName = name.trimmed();
    const QStringList members = uniqueNonEmpty(applicationIds);
    if (normalizedName.isEmpty() || members.isEmpty()) {
        return {};
    }

    QStringList order = uniqueNonEmpty(currentRootOrder);
    if (order.isEmpty()) {
        order = m_launchpadItemOrder;
    }
    int insertionIndex = order.size();
    for (const QString &applicationId : members) {
        const int index = order.indexOf(applicationId);
        if (index >= 0) {
            insertionIndex = std::min(insertionIndex, index);
        }
    }

    QSet<QString> memberSet;
    for (const QString &member : members) {
        memberSet.insert(member);
    }
    for (int index = 0; index < m_launchpadFolders.size(); ++index) {
        QVariantMap folder = m_launchpadFolders[index].toMap();
        QStringList ids = folder.value(QStringLiteral("applicationIds")).toStringList();
        ids.erase(std::remove_if(ids.begin(), ids.end(), [&memberSet](const QString &id) {
            return memberSet.contains(id);
        }), ids.end());
        folder.insert(QStringLiteral("applicationIds"), ids);
        m_launchpadFolders[index] = folder;
    }

    order.erase(std::remove_if(order.begin(), order.end(), [&memberSet](const QString &id) {
        return memberSet.contains(id);
    }), order.end());
    const QString folderId = QStringLiteral("folder:") + QUuid::createUuid().toString(QUuid::WithoutBraces);
    order.insert(std::clamp(insertionIndex, 0, static_cast<int>(order.size())), folderId);
    m_launchpadItemOrder = uniqueNonEmpty(order);
    m_launchpadFolders.append(QVariantMap{
        {QStringLiteral("id"), folderId},
        {QStringLiteral("type"), QStringLiteral("folder")},
        {QStringLiteral("name"), normalizedName},
        {QStringLiteral("applicationIds"), members},
    });
    persistLaunchpadModel();
    return folderId;
}

bool ApplicationLauncherState::renameLaunchpadFolder(const QString &folderId, const QString &name)
{
    const QString normalizedName = name.trimmed();
    if (normalizedName.isEmpty()) {
        return false;
    }
    for (int index = 0; index < m_launchpadFolders.size(); ++index) {
        QVariantMap folder = m_launchpadFolders[index].toMap();
        if (folder.value(QStringLiteral("id")).toString() != folderId) {
            continue;
        }
        if (folder.value(QStringLiteral("name")).toString() == normalizedName) {
            return false;
        }
        folder.insert(QStringLiteral("name"), normalizedName);
        m_launchpadFolders[index] = folder;
        persistLaunchpadModel();
        return true;
    }
    return false;
}

bool ApplicationLauncherState::addApplicationToLaunchpadFolder(const QString &folderId,
                                                                const QString &applicationId)
{
    if (applicationId.isEmpty()) {
        return false;
    }
    int targetIndex = -1;
    for (int index = 0; index < m_launchpadFolders.size(); ++index) {
        if (m_launchpadFolders[index].toMap().value(QStringLiteral("id")).toString() == folderId) {
            targetIndex = index;
            break;
        }
    }
    if (targetIndex < 0) {
        return false;
    }

    bool changed = false;
    for (int index = 0; index < m_launchpadFolders.size(); ++index) {
        QVariantMap folder = m_launchpadFolders[index].toMap();
        QStringList ids = folder.value(QStringLiteral("applicationIds")).toStringList();
        const int removed = ids.removeAll(applicationId);
        if (index == targetIndex) {
            ids.append(applicationId);
        }
        if (removed > 0 || index == targetIndex) {
            folder.insert(QStringLiteral("applicationIds"), uniqueNonEmpty(ids));
            m_launchpadFolders[index] = folder;
            changed = changed || removed > 0 || index == targetIndex;
        }
    }
    const int rootIndex = m_launchpadItemOrder.indexOf(applicationId);
    if (rootIndex >= 0) {
        m_launchpadItemOrder.removeAll(applicationId);
        changed = true;
    }
    if (changed) {
        persistLaunchpadModel();
    }
    return changed;
}

bool ApplicationLauncherState::removeApplicationFromLaunchpadFolder(const QString &folderId,
                                                                     const QString &applicationId)
{
    for (int index = 0; index < m_launchpadFolders.size(); ++index) {
        QVariantMap folder = m_launchpadFolders[index].toMap();
        if (folder.value(QStringLiteral("id")).toString() != folderId) {
            continue;
        }
        QStringList ids = folder.value(QStringLiteral("applicationIds")).toStringList();
        if (!ids.removeOne(applicationId)) {
            return false;
        }
        folder.insert(QStringLiteral("applicationIds"), ids);
        m_launchpadFolders[index] = folder;
        const int folderPosition = m_launchpadItemOrder.indexOf(folderId);
        if (folderPosition >= 0 && !m_launchpadItemOrder.contains(applicationId)) {
            m_launchpadItemOrder.insert(folderPosition + 1, applicationId);
        } else if (folderPosition < 0 && !m_launchpadItemOrder.contains(applicationId)) {
            m_launchpadItemOrder.append(applicationId);
        }
        m_launchpadItemOrder = uniqueNonEmpty(m_launchpadItemOrder);
        persistLaunchpadModel();
        return true;
    }
    return false;
}

bool ApplicationLauncherState::deleteLaunchpadFolder(const QString &folderId)
{
    for (int index = 0; index < m_launchpadFolders.size(); ++index) {
        const QVariantMap folder = m_launchpadFolders[index].toMap();
        if (folder.value(QStringLiteral("id")).toString() != folderId) {
            continue;
        }
        const QStringList applicationIds = folder.value(QStringLiteral("applicationIds")).toStringList();
        const int position = m_launchpadItemOrder.indexOf(folderId);
        m_launchpadItemOrder.removeAll(folderId);
        if (position >= 0) {
            int offset = 0;
            for (const QString &applicationId : applicationIds) {
                if (!m_launchpadItemOrder.contains(applicationId)) {
                    m_launchpadItemOrder.insert(std::min(position + offset,
                        static_cast<int>(m_launchpadItemOrder.size())), applicationId);
                    ++offset;
                }
            }
        } else {
            for (const QString &applicationId : applicationIds) {
                if (!m_launchpadItemOrder.contains(applicationId)) {
                    m_launchpadItemOrder.append(applicationId);
                }
            }
        }
        m_launchpadItemOrder = uniqueNonEmpty(m_launchpadItemOrder);
        m_launchpadFolders.removeAt(index);
        persistLaunchpadModel();
        return true;
    }
    return false;
}

void ApplicationLauncherState::persistLaunchpadModel()
{
    if (m_settings) {
        m_settings->setLaunchpadFolders(encodeFolders(m_launchpadFolders));
        m_settings->setLaunchpadItemOrder(m_launchpadItemOrder);
    }
    Q_EMIT launchpadFoldersChanged();
    Q_EMIT launchpadItemOrderChanged();
}

} // namespace kdockw
