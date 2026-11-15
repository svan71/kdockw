// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include <QObject>
#include <QHash>
#include <QSet>
#include <QVariantList>
#include <QVariantMap>

#include <KService>
#include <KServiceGroup>

namespace kdockw
{

/** Read-only, in-memory view of the current KDE application menu/catalog. */
class ApplicationCatalog final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QVariantList applications READ applications NOTIFY catalogChanged)
    Q_PROPERTY(QVariantList menuTree READ menuTree NOTIFY catalogChanged)

public:
    explicit ApplicationCatalog(QObject *parent = nullptr);

    [[nodiscard]] bool ready() const;
    [[nodiscard]] bool loading() const;
    [[nodiscard]] QVariantList applications() const;
    [[nodiscard]] QVariantList menuTree() const;

    Q_INVOKABLE void ensureLoaded();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariantList search(const QString &query) const;
    Q_INVOKABLE QVariantMap application(const QString &serviceId) const;
    Q_INVOKABLE bool launch(const QString &serviceId);
    Q_INVOKABLE bool launchAction(const QString &serviceId, const QString &actionName);

    [[nodiscard]] static QString stableId(const KService::Ptr &service);
    [[nodiscard]] static QVariantMap recordForService(const KService::Ptr &service);
    [[nodiscard]] static bool matchesQuery(const QString &query, const QVariantMap &record);
    [[nodiscard]] static bool isDisplayable(const KService::Ptr &service);

Q_SIGNALS:
    void readyChanged();
    void loadingChanged();
    void catalogChanged();
    void launchFinished(const QString &serviceId, bool success);

private:
    QVariantList readGroup(const KServiceGroup::Ptr &group, QSet<QString> &seen);
    void prepareRefresh();
    void processRootEntry(const KServiceGroup::SPtr &entry);
    void finishRefresh(bool wasReady);
    void processAsyncRefreshBatch();
    bool launchService(const QString &serviceId, const KService::Ptr &service);

    QHash<QString, KService::Ptr> m_services;
    QHash<QString, QVariantMap> m_records;
    QVariantList m_applications;
    QVariantList m_menuTree;
    KServiceGroup::List m_refreshEntries;
    QSet<QString> m_refreshSeen;
    int m_refreshEntryIndex = 0;
    bool m_ready = false;
    bool m_loading = false;
    bool m_refreshScheduled = false;
};

} // namespace kdockw
