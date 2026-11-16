// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "applicationcatalog.h"

#include <KApplicationTrader>
#include <KConfigGroup>
#include <KDesktopFile>
#include <KIO/ApplicationLauncherJob>
#include <KJobUiDelegate>
#include <KNotificationJobUiDelegate>
#include <KServiceGroup>
#include <KSycoca>

#include <QCollator>
#include <QElapsedTimer>
#include <QStandardPaths>
#include <QTimer>

#include <algorithm>
#include <functional>

namespace kdockw
{
namespace
{
QString iconNameOrFallback(const QString &requested, const QString &fallback)
{
    return requested.isEmpty() ? fallback : requested;
}

QVariantList previewApplications(const QVariantList &items, qsizetype maximum = 4)
{
    QVariantList previews;
    previews.reserve(maximum);
    std::function<void(const QVariantList &)> append = [&](const QVariantList &entries) {
        for (const QVariant &value : entries) {
            if (previews.size() >= maximum) {
                return;
            }
            const QVariantMap item = value.toMap();
            if (item.value(QStringLiteral("type")).toString() == QLatin1String("folder")) {
                append(item.value(QStringLiteral("children")).toList());
            } else if (!item.value(QStringLiteral("id")).toString().isEmpty()) {
                previews.append(QVariantMap{
                    {QStringLiteral("id"), item.value(QStringLiteral("id"))},
                    {QStringLiteral("name"), item.value(QStringLiteral("name"))},
                    {QStringLiteral("icon"), item.value(QStringLiteral("icon"))},
                });
            }
            if (previews.size() >= maximum) {
                return;
            }
        }
    };
    append(items);
    return previews;
}

QVariantMap folderRecord(const KServiceGroup *group, const QVariantList &children)
{
    return {
        {QStringLiteral("id"), QStringLiteral("group:%1").arg(group->relPath())},
        {QStringLiteral("type"), QStringLiteral("folder")},
        {QStringLiteral("name"), group->caption()},
        {QStringLiteral("icon"), iconNameOrFallback(group->icon(), QStringLiteral("folder"))},
        {QStringLiteral("children"), children},
        {QStringLiteral("previewIcons"), previewApplications(children)},
    };
}
}

ApplicationCatalog::ApplicationCatalog(QObject *parent)
    : QObject(parent)
{
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, [this] {
        if (!m_ready || m_refreshScheduled) {
            return;
        }
        m_refreshScheduled = true;
        const quint64 generation = ++m_refreshGeneration;
        QTimer::singleShot(0, this, [this, generation] {
            if (!m_refreshScheduled || generation != m_refreshGeneration) {
                return;
            }
            m_refreshScheduled = false;
            refresh();
        });
    });
}

bool ApplicationCatalog::ready() const
{
    return m_ready;
}

bool ApplicationCatalog::loading() const
{
    return m_loading;
}

QVariantList ApplicationCatalog::applications() const
{
    return m_applications;
}

QVariantList ApplicationCatalog::menuTree() const
{
    return m_menuTree;
}

void ApplicationCatalog::ensureLoaded()
{
    if (!m_ready && !m_loading) {
        prepareRefresh();
        m_loading = true;
        Q_EMIT loadingChanged();
        QTimer::singleShot(0, this, &ApplicationCatalog::processAsyncRefreshBatch);
    }
}

void ApplicationCatalog::refresh()
{
    // An explicit refresh supersedes any queued Sycoca notification. Its
    // cache snapshot already includes that change, so a second full rebuild
    // would only duplicate work and catalogChanged.
    m_refreshScheduled = false;
    ++m_refreshGeneration;

    const bool wasReady = m_ready;
    const bool wasLoading = m_loading;
    prepareRefresh();
    m_loading = false;
    if (wasLoading) {
        Q_EMIT loadingChanged();
    }
    while (m_refreshEntryIndex < m_refreshEntries.size()) {
        processRootEntry(m_refreshEntries.at(m_refreshEntryIndex++));
    }
    finishRefresh(wasReady);
}

void ApplicationCatalog::prepareRefresh()
{
    m_services.clear();
    m_records.clear();
    m_applications.clear();
    m_menuTree.clear();
    m_refreshSeen.clear();
    m_refreshEntryIndex = 0;
    m_refreshEntries.clear();

    const KServiceGroup::Ptr root = KServiceGroup::root();
    if (root && root->isValid()) {
        m_refreshEntries = root->entries(false, true, true);
    }
}

void ApplicationCatalog::processRootEntry(const KServiceGroup::SPtr &entry)
{
    if (!entry) {
        return;
    }
    if (entry->isType(KST_KServiceGroup)) {
        auto *childGroup = static_cast<KServiceGroup *>(entry.data());
        const QVariantList nested = readGroup(KServiceGroup::Ptr(childGroup), m_refreshSeen);
        if (nested.isEmpty() && !childGroup->showEmptyMenu()) {
            return;
        }
        m_menuTree.append(folderRecord(childGroup, nested));
        return;
    }
    if (!entry->isType(KST_KService)) {
        return;
    }

    auto *rawService = static_cast<KService *>(entry.data());
    const KService::Ptr service(rawService);
    if (!isDisplayable(service)) {
        return;
    }
    const QString id = stableId(service);
    if (id.isEmpty() || m_refreshSeen.contains(id)) {
        return;
    }
    m_refreshSeen.insert(id);
    const QVariantMap app = recordForService(service);
    m_services.insert(id, service);
    m_records.insert(id, app);
    m_applications.append(app);
    m_menuTree.append(app);
}

void ApplicationCatalog::finishRefresh(bool wasReady)
{
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::stable_sort(m_applications.begin(), m_applications.end(), [&collator](const QVariant &left, const QVariant &right) {
        return collator.compare(left.toMap().value(QStringLiteral("name")).toString(),
                                right.toMap().value(QStringLiteral("name")).toString()) < 0;
    });

    m_ready = true;
    m_loading = false;
    if (!wasReady) {
        Q_EMIT readyChanged();
    }
    Q_EMIT loadingChanged();
    Q_EMIT catalogChanged();
}

void ApplicationCatalog::processAsyncRefreshBatch()
{
    if (!m_loading) {
        return;
    }
    QElapsedTimer batchTimer;
    batchTimer.start();
    int processed = 0;
    while (m_refreshEntryIndex < m_refreshEntries.size() && processed < 2 && batchTimer.elapsed() < 4) {
        processRootEntry(m_refreshEntries.at(m_refreshEntryIndex++));
        ++processed;
    }
    if (m_refreshEntryIndex < m_refreshEntries.size()) {
        QTimer::singleShot(0, this, &ApplicationCatalog::processAsyncRefreshBatch);
        return;
    }
    finishRefresh(false);
}

QVariantList ApplicationCatalog::readGroup(const KServiceGroup::Ptr &group, QSet<QString> &seen)
{
    QVariantList children;
    if (!group || !group->isValid() || group->noDisplay()) {
        return children;
    }

    const KServiceGroup::List entries = group->entries(false, true, true);
    for (const KServiceGroup::SPtr &entry : entries) {
        if (!entry) {
            continue;
        }
        if (entry->isType(KST_KServiceGroup)) {
            auto *childGroup = static_cast<KServiceGroup *>(entry.data());
            QVariantList nested = readGroup(KServiceGroup::Ptr(childGroup), seen);
            if (nested.isEmpty() && !childGroup->showEmptyMenu()) {
                continue;
            }
            children.append(folderRecord(childGroup, nested));
        } else if (entry->isType(KST_KService)) {
            auto *rawService = static_cast<KService *>(entry.data());
            const KService::Ptr service(rawService);
            if (!isDisplayable(service)) {
                continue;
            }
            const QString id = stableId(service);
            if (id.isEmpty() || seen.contains(id)) {
                continue;
            }
            seen.insert(id);
            const QVariantMap app = recordForService(service);
            m_services.insert(id, service);
            m_records.insert(id, app);
            m_applications.append(app);
            children.append(app);
        }
    }
    return children;
}

QVariantMap ApplicationCatalog::recordForService(const KService::Ptr &service)
{
    QVariantList actions;
    for (const KServiceAction &action : service->actions()) {
        if (action.isSeparator() || action.noDisplay()) {
            continue;
        }
        actions.append(QVariantMap{
            {QStringLiteral("name"), action.name()},
            {QStringLiteral("text"), action.text()},
            {QStringLiteral("icon"), action.icon()},
        });
    }
    return {
        {QStringLiteral("id"), stableId(service)},
        {QStringLiteral("type"), QStringLiteral("application")},
        {QStringLiteral("name"), service->name()},
        {QStringLiteral("genericName"), service->genericName()},
        {QStringLiteral("comment"), service->comment()},
        {QStringLiteral("icon"), iconNameOrFallback(service->icon(), QStringLiteral("application-x-executable"))},
        {QStringLiteral("menuId"), service->menuId()},
        {QStringLiteral("storageId"), service->storageId()},
        {QStringLiteral("categories"), service->categories()},
        {QStringLiteral("keywords"), service->keywords()},
        {QStringLiteral("actions"), actions},
    };
}

QString ApplicationCatalog::stableId(const KService::Ptr &service)
{
    if (!service) {
        return {};
    }
    if (!service->menuId().isEmpty()) {
        return service->menuId();
    }
    if (!service->desktopEntryName().isEmpty()) {
        return service->desktopEntryName();
    }
    return service->storageId();
}

bool ApplicationCatalog::isDisplayable(const KService::Ptr &service)
{
    if (!service || !service->isValid() || !service->isApplication() || service->noDisplay()
        || !service->showInCurrentDesktop() || !service->showOnCurrentPlatform()) {
        return false;
    }

    KDesktopFile desktopFile(QStandardPaths::ApplicationsLocation, service->entryPath());
    const KConfigGroup desktop = desktopFile.desktopGroup();
    if (desktop.readEntry(QStringLiteral("Hidden"), false)) {
        return false;
    }
    const QString tryExec = desktop.readEntry(QStringLiteral("TryExec"));
    return tryExec.isEmpty() || desktopFile.tryExec();
}

bool ApplicationCatalog::matchesQuery(const QString &query, const QVariantMap &app)
{
    const QStringList terms = query.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    if (terms.isEmpty()) {
        return true;
    }
    QStringList searchable{
        app.value(QStringLiteral("name")).toString(),
        app.value(QStringLiteral("genericName")).toString(),
        app.value(QStringLiteral("comment")).toString(),
    };
    searchable.append(app.value(QStringLiteral("categories")).toStringList());
    searchable.append(app.value(QStringLiteral("keywords")).toStringList());
    for (const QString &term : terms) {
        const bool matched = std::any_of(searchable.cbegin(), searchable.cend(), [&term](const QString &text) {
            return text.contains(term, Qt::CaseInsensitive)
                || KApplicationTrader::isSubsequence(term, text, Qt::CaseInsensitive);
        });
        if (!matched) {
            return false;
        }
    }
    return true;
}

QVariantList ApplicationCatalog::search(const QString &query) const
{
    const QString normalizedQuery = query.trimmed();
    if (!m_ready) {
        return {};
    }

    if (normalizedQuery.isEmpty()) {
        return m_applications;
    }

    // The catalog was already read from KService/KServiceGroup. Re-querying
    // KApplicationTrader for every debounced keystroke reparses the same
    // desktop metadata; filter the stable in-memory records instead.
    QVariantList results;
    results.reserve(m_applications.size());
    for (const QVariant &record : m_applications) {
        const QVariantMap app = record.toMap();
        if (matchesQuery(normalizedQuery, app)) {
            results.append(record);
        }
    }
    return results;
}

QVariantMap ApplicationCatalog::application(const QString &serviceId) const
{
    return m_records.value(serviceId);
}

bool ApplicationCatalog::launch(const QString &serviceId)
{
    ensureLoaded();
    return launchService(serviceId, m_services.value(serviceId));
}

bool ApplicationCatalog::launchAction(const QString &serviceId, const QString &actionName)
{
    ensureLoaded();
    const KService::Ptr service = m_services.value(serviceId);
    if (!service) {
        return false;
    }
    for (const KServiceAction &action : service->actions()) {
        if (!action.isSeparator() && !action.noDisplay() && action.name() == actionName) {
            auto *job = new KIO::ApplicationLauncherJob(action, this);
            job->setUiDelegate(new KNotificationJobUiDelegate(KJobUiDelegate::AutoErrorHandlingEnabled));
            connect(job, &KJob::result, this, [this, serviceId, job] {
                Q_EMIT launchFinished(serviceId, !job->error());
            });
            job->start();
            return true;
        }
    }
    return false;
}

bool ApplicationCatalog::launchService(const QString &serviceId, const KService::Ptr &service)
{
    if (!service || !m_records.contains(serviceId)) {
        return false;
    }
    auto *job = new KIO::ApplicationLauncherJob(service, this);
    job->setUiDelegate(new KNotificationJobUiDelegate(KJobUiDelegate::AutoErrorHandlingEnabled));
    connect(job, &KJob::result, this, [this, serviceId, job] {
        Q_EMIT launchFinished(serviceId, !job->error());
    });
    job->start();
    return true;
}

} // namespace kdockw
