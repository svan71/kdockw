// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "applicationlauncherstate.h"

#include "kdockw.h"

#include <QSet>

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
                                                      bool sourceAvailable)
{
    if (m_startFavoritesImportAttempted) {
        return false;
    }

    m_startFavoritesImportAttempted = true;
    QString status = QStringLiteral("noMatchingApps");
    if (!sourceAvailable) {
        status = QStringLiteral("unavailable");
    } else if (!m_pinnedApplicationIds.isEmpty()) {
        status = QStringLiteral("existingPinsPreserved");
    } else {
        QSet<QString> available;
        for (const QString &id : availableApplicationIds) {
            available.insert(id);
        }
        QSet<QString> seen;
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
            m_pinnedApplicationIds = imported;
            status = QStringLiteral("imported");
            Q_EMIT pinnedApplicationIdsChanged();
            if (m_settings) {
                m_settings->setStartPinnedApplications(m_pinnedApplicationIds);
            }
        } else if (favoriteIds.isEmpty()) {
            status = QStringLiteral("noFavorites");
        }
    }
    if (m_startFavoritesImportStatus != status) {
        m_startFavoritesImportStatus = status;
        Q_EMIT startFavoritesImportStatusChanged();
    }
    if (m_settings) {
        m_settings->setStartFavoritesImportAttempted(true);
        m_settings->setStartFavoritesImportStatus(m_startFavoritesImportStatus);
    }
    return status == QLatin1String("imported");
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

} // namespace kdockw
