// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "applicationlauncherstate.h"

#include "kdockw.h"

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
