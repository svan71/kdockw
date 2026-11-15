// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "kdockw.h"
#include "models/applicationcatalog.h"
#include "models/applicationlauncherstate.h"
#include "models/taskiconprovider.h"

#include <catch2/catch_test_macros.hpp>

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QIcon>
#include <QTemporaryDir>
#include <QTest>

#include <cstdio>
#include <functional>

namespace
{
class ScopedConfigHome
{
public:
    ScopedConfigHome()
        : m_previous(qgetenv("XDG_CONFIG_HOME"))
        , m_hadPrevious(qEnvironmentVariableIsSet("XDG_CONFIG_HOME"))
    {
        qputenv("XDG_CONFIG_HOME", m_dir.path().toLocal8Bit());
    }
    ~ScopedConfigHome()
    {
        if (m_hadPrevious) qputenv("XDG_CONFIG_HOME", m_previous);
        else qunsetenv("XDG_CONFIG_HOME");
    }
    QString filePath() const { return m_dir.filePath(QStringLiteral("kdockwrc")); }

private:
    QTemporaryDir m_dir;
    QByteArray m_previous;
    bool m_hadPrevious;
};

bool writeDesktopFile(const QString &path, const QString &extra = {})
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) return false;
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) return false;
    const QString desktop = QStringLiteral(
        "[Desktop Entry]\nType=Application\nName=KDE Discover\nGenericName=Software Center\n"
        "Comment=Browse software\nExec=/usr/bin/true\nIcon=system-software-install\n"
        "Categories=System;PackageManager;\nKeywords=Install;Browse;Software;\n")
                                      .append(extra)
                                      .append(QStringLiteral(
        "Actions=NewWindow;\n"
        "[Desktop Action NewWindow]\nName=Open a new window\nExec=/usr/bin/true\nIcon=window-new\n"));
    const QByteArray content = desktop.toUtf8();
    return file.write(content) == content.size();
}

} // namespace

TEST_CASE("Application catalog records localized metadata and desktop actions", "[application-launcher][catalog]")
{
    QTemporaryDir dir;
    REQUIRE(dir.isValid());
    const QString desktopPath = dir.filePath(QStringLiteral("org.example.discover.desktop"));
    REQUIRE(writeDesktopFile(desktopPath));
    const KService::Ptr service(new KService(desktopPath));
    REQUIRE(service->isValid());

    const QVariantMap app = kdockw::ApplicationCatalog::recordForService(service);
    CHECK(app.value(QStringLiteral("type")).toString() == QStringLiteral("application"));
    CHECK(app.value(QStringLiteral("name")).toString() == QStringLiteral("KDE Discover"));
    CHECK(app.value(QStringLiteral("genericName")).toString() == QStringLiteral("Software Center"));
    CHECK(app.value(QStringLiteral("icon")).toString() == QStringLiteral("system-software-install"));
    CHECK(app.value(QStringLiteral("categories")).toStringList().contains(QStringLiteral("PackageManager")));
    CHECK(app.value(QStringLiteral("keywords")).toStringList().contains(QStringLiteral("Install")));
    const QVariantList actions = app.value(QStringLiteral("actions")).toList();
    REQUIRE(actions.size() == 1);
    CHECK(actions.first().toMap().value(QStringLiteral("name")).toString() == QStringLiteral("NewWindow"));
    CHECK(actions.first().toMap().value(QStringLiteral("text")).toString() == QStringLiteral("Open a new window"));
}

TEST_CASE("Application catalog deduplicates entry paths and searches metadata", "[application-launcher][catalog]")
{
    QTemporaryDir dir;
    REQUIRE(dir.isValid());
    const QString pathA = dir.filePath(QStringLiteral("first/org.example.discover.desktop"));
    const QString pathB = dir.filePath(QStringLiteral("second/org.example.discover.desktop"));
    REQUIRE(writeDesktopFile(pathA));
    REQUIRE(writeDesktopFile(pathB));
    const KService::Ptr first(new KService(pathA));
    const KService::Ptr duplicate(new KService(pathB));
    REQUIRE(first->isValid());
    REQUIRE(duplicate->isValid());
    CHECK(kdockw::ApplicationCatalog::stableId(first) == kdockw::ApplicationCatalog::stableId(duplicate));

    const QVariantMap app = kdockw::ApplicationCatalog::recordForService(first);
    CHECK(kdockw::ApplicationCatalog::matchesQuery(QStringLiteral("kdi"), app));
    CHECK(kdockw::ApplicationCatalog::matchesQuery(QStringLiteral("software install"), app));
    CHECK(kdockw::ApplicationCatalog::matchesQuery(QStringLiteral("packman"), app));
    CHECK_FALSE(kdockw::ApplicationCatalog::matchesQuery(QStringLiteral("unrelated query"), app));
}

TEST_CASE("Application catalog filters Hidden NoDisplay OnlyShowIn and missing TryExec", "[application-launcher][catalog]")
{
    QTemporaryDir dir;
    REQUIRE(dir.isValid());
    const QByteArray previousDesktop = qgetenv("XDG_CURRENT_DESKTOP");
    const bool hadDesktop = qEnvironmentVariableIsSet("XDG_CURRENT_DESKTOP");
    qputenv("XDG_CURRENT_DESKTOP", "KDE");

    const auto load = [&dir](const QString &name, const QString &extra = {}) {
        const QString path = dir.filePath(name + QStringLiteral(".desktop"));
        if (!writeDesktopFile(path, extra)) return KService::Ptr{};
        return KService::Ptr(new KService(path));
    };
    const KService::Ptr visible = load(QStringLiteral("visible"));
    const KService::Ptr hidden = load(QStringLiteral("hidden"), QStringLiteral("Hidden=true\n"));
    const KService::Ptr noDisplay = load(QStringLiteral("nodisplay"), QStringLiteral("NoDisplay=true\n"));
    const KService::Ptr wrongDesktop = load(QStringLiteral("desktop"), QStringLiteral("OnlyShowIn=GNOME;\n"));
    const KService::Ptr missingTryExec = load(QStringLiteral("tryexec"), QStringLiteral("TryExec=kdockw-missing-command-xyz\n"));

    REQUIRE(visible);
    REQUIRE(hidden);
    REQUIRE(noDisplay);
    REQUIRE(wrongDesktop);
    REQUIRE(missingTryExec);
    CHECK(kdockw::ApplicationCatalog::isDisplayable(visible));
    CHECK_FALSE(kdockw::ApplicationCatalog::isDisplayable(hidden));
    CHECK_FALSE(kdockw::ApplicationCatalog::isDisplayable(noDisplay));
    CHECK_FALSE(kdockw::ApplicationCatalog::isDisplayable(wrongDesktop));
    CHECK_FALSE(kdockw::ApplicationCatalog::isDisplayable(missingTryExec));

    if (hadDesktop) qputenv("XDG_CURRENT_DESKTOP", previousDesktop);
    else qunsetenv("XDG_CURRENT_DESKTOP");
}

TEST_CASE("Refreshing the application catalog replaces data without growing its QObject graph", "[application-launcher][catalog][lifecycle]")
{
    QObject owner;
    kdockw::ApplicationCatalog catalog(&owner);
    catalog.ensureLoaded();
    QTRY_VERIFY_WITH_TIMEOUT(catalog.ready(), 5000);
    REQUIRE(catalog.ready());

    const QVariantList initialApplications = catalog.applications();
    const QVariantList initialMenuTree = catalog.menuTree();
    REQUIRE_FALSE(initialApplications.isEmpty());
    REQUIRE(owner.children().size() == 1);

    for (int refresh = 0; refresh < 20; ++refresh) {
        catalog.refresh();
        CHECK(catalog.ready());
        CHECK(catalog.applications() == initialApplications);
        CHECK(catalog.menuTree() == initialMenuTree);
        CHECK(owner.children().size() == 1);
    }
}

TEST_CASE("Synchronous catalog refresh cancels a pending asynchronous first load", "[application-launcher][catalog][refresh]")
{
    kdockw::ApplicationCatalog catalog;
    int catalogChanges = 0;
    QObject::connect(&catalog, &kdockw::ApplicationCatalog::catalogChanged, &catalog, [&catalogChanges] {
        ++catalogChanges;
    });

    catalog.ensureLoaded();
    REQUIRE(catalog.loading());
    catalog.refresh();
    REQUIRE(catalog.ready());
    REQUIRE_FALSE(catalog.loading());
    REQUIRE(catalogChanges == 1);

    QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
    CHECK(catalogChanges == 1);
}

TEST_CASE("Application catalog warm-open and search cost is measurable", "[application-launcher][catalog][performance]")
{
    kdockw::ApplicationCatalog catalog;
    int catalogChanges = 0;
    QObject::connect(&catalog, &kdockw::ApplicationCatalog::catalogChanged, &catalog, [&catalogChanges] {
        ++catalogChanges;
    });

    QElapsedTimer timer;
    timer.start();
    catalog.ensureLoaded();
    const qint64 initialRequestMs = timer.elapsed();
    for (int i = 0; i < 40; ++i) {
        catalog.ensureLoaded();
    }
    CHECK(catalog.loading());
    CHECK(catalogChanges == 0);
    QTRY_VERIFY_WITH_TIMEOUT(catalog.ready(), 5000);
    const qint64 initialReadyMs = timer.elapsed();
    REQUIRE(catalog.ready());
    const int applicationCount = catalog.applications().size();
    REQUIRE(applicationCount > 0);
    REQUIRE(catalogChanges >= 1);
    const int stableChangeCount = catalogChanges;

    timer.restart();
    for (int i = 0; i < 40; ++i) {
        catalog.ensureLoaded();
    }
    const qint64 repeatedOpenMs = timer.elapsed();
    CHECK(catalogChanges == stableChangeCount);

    const QStringList queries{QStringLiteral("browser"), QStringLiteral("system"), QStringLiteral("editor"), QStringLiteral("settings")};
    timer.restart();
    int resultCount = 0;
    for (int i = 0; i < 80; ++i) {
        resultCount += catalog.search(queries.at(i % queries.size())).size();
    }
    const qint64 searchMs = timer.elapsed();
    CHECK(resultCount >= 0);

    std::fprintf(stderr,
                 "[launcher-perf] applications=%d initial-request-ms=%lld initial-ready-ms=%lld ensure-loaded-40-ms=%lld search-80-ms=%lld\n",
                 applicationCount,
                 static_cast<long long>(initialRequestMs),
                 static_cast<long long>(initialReadyMs),
                 static_cast<long long>(repeatedOpenMs),
                 static_cast<long long>(searchMs));
}

TEST_CASE("Application and KDE category icons resolve through the active icon theme", "[application-launcher][catalog][icons]")
{
    kdockw::ApplicationCatalog catalog;
    catalog.ensureLoaded();
    QTRY_VERIFY_WITH_TIMEOUT(catalog.ready(), 5000);
    REQUIRE(catalog.ready());

    kdockw::TaskIconProvider provider(false);
    int checked = 0;
    int themeMisses = 0;
    const auto verifyIcon = [&checked, &themeMisses, &provider](const QString &iconName) {
        REQUIRE_FALSE(iconName.isEmpty());
        if (QIcon::fromTheme(iconName).isNull() && QIcon(iconName).isNull()) {
            ++themeMisses;
        }
        QSize resolvedSize;
        const QPixmap pixmap = provider.requestPixmap(iconName, &resolvedSize, QSize(48, 48));
        REQUIRE_FALSE(pixmap.isNull());
        ++checked;
    };
    std::function<void(const QVariantList &)> verifyTree = [&](const QVariantList &items) {
        for (const QVariant &value : items) {
            const QVariantMap item = value.toMap();
            verifyIcon(item.value(QStringLiteral("icon")).toString());
            if (item.value(QStringLiteral("type")).toString() == QLatin1String("folder")) {
                verifyTree(item.value(QStringLiteral("children")).toList());
            }
        }
    };

    verifyTree(catalog.menuTree());
    for (const QVariant &value : catalog.applications()) {
        verifyIcon(value.toMap().value(QStringLiteral("icon")).toString());
    }
    CHECK(checked >= catalog.applications().size());
    std::fprintf(stderr, "[launcher-icons] rendered=%d themed-or-file-misses=%d via-fallback-provider\n",
                 checked, themeMisses);
}

TEST_CASE("Application launcher style and Windows Start pin order persist", "[application-launcher][state]")
{
    const ScopedConfigHome home;
    {
        KDockWSettings settings;
        settings.load();
        kdockw::ApplicationLauncherState state(&settings);
        state.setStyle(QStringLiteral("start"));
        state.togglePinned(QStringLiteral("org.example.one.desktop"));
        state.togglePinned(QStringLiteral("org.example.two.desktop"));
        REQUIRE(state.movePinned(1, 0));
        settings.save();
    }
    KDockWSettings restoredSettings;
    restoredSettings.load();
    kdockw::ApplicationLauncherState restored(&restoredSettings);
    CHECK(restored.style() == QStringLiteral("start"));
    CHECK(restored.pinnedApplicationIds() == QStringList{
        QStringLiteral("org.example.two.desktop"), QStringLiteral("org.example.one.desktop")});
    CHECK(restored.isPinned(QStringLiteral("org.example.two.desktop")));
    CHECK(restored.pinnedApplicationIds().contains(QStringLiteral("org.example.two.desktop")));
}
