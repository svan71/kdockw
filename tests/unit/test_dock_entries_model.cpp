// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "models/dockentriesmodel.h"

#include <catch2/catch_test_macros.hpp>

TEST_CASE("Dock entries model exposes typed roles and retains mixed order", "[dock-entries]")
{
    kdockw::DockEntriesModel model;
    const QUrl dolphin(QStringLiteral("applications:org.kde.dolphin.desktop"));
    const QUrl folder = QUrl::fromLocalFile(QStringLiteral("/tmp/Downloads"));
    const auto stack = kdockw::DockEntry::folderStack(folder);
    model.setEntries({kdockw::DockEntry::task(dolphin), stack});

    REQUIRE(model.rowCount() == 2);
    CHECK(model.data(model.index(0, 0), Qt::DisplayRole).toString() == dolphin.toString());
    CHECK(model.data(model.index(0, 0), kdockw::DockEntriesModel::EntryTypeRole).toString() == QStringLiteral("task"));
    CHECK(model.data(model.index(1, 0), kdockw::DockEntriesModel::EntryTypeRole).toString() == QStringLiteral("folderStack"));
    CHECK(model.data(model.index(1, 0), kdockw::DockEntriesModel::EntryIdRole).toString() == stack.id);
    CHECK(model.data(model.index(1, 0), kdockw::DockEntriesModel::EntryUrlRole).toUrl() == folder);
    CHECK(model.roleNames().value(kdockw::DockEntriesModel::EntryUrlRole) == QByteArray("entryUrl"));
}

TEST_CASE("Dock entries model syncs task order while preserving folder slots", "[dock-entries]")
{
    kdockw::DockEntriesModel model;
    const QUrl first(QStringLiteral("applications:org.kde.dolphin.desktop"));
    const QUrl second(QStringLiteral("applications:org.kde.kate.desktop"));
    const QUrl third(QStringLiteral("applications:org.kde.konsole.desktop"));
    const auto firstStack = kdockw::DockEntry::folderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/one")));
    const auto secondStack = kdockw::DockEntry::folderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/two")));
    model.setEntries({kdockw::DockEntry::task(first), firstStack, kdockw::DockEntry::task(second), secondStack});

    model.syncTaskOrder({third.toString(), first.toString()});

    const auto entries = model.entries();
    REQUIRE(entries.size() == 4);
    CHECK(entries.at(0).url == third);
    CHECK(entries.at(1).id == firstStack.id);
    CHECK(entries.at(2).url == first);
    CHECK(entries.at(3).id == secondStack.id);
}

TEST_CASE("Dock entries model appends, moves, and removes only folder stacks", "[dock-entries]")
{
    kdockw::DockEntriesModel model;
    const auto task = kdockw::DockEntry::task(QUrl(QStringLiteral("applications:org.kde.dolphin.desktop")));
    model.setEntries({task});

    CHECK_FALSE(model.appendFolderStack(QUrl(QStringLiteral("smb://server/share"))));
    REQUIRE(model.appendFolderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/Downloads"))));
    REQUIRE(model.appendFolderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/Pictures"))));

    const QString firstId = model.entries().at(1).id;
    REQUIRE(model.setFolderStackIcon(firstId, QStringLiteral("folder-development")));
    CHECK(model.data(model.index(1, 0), kdockw::DockEntriesModel::IconNameRole).toString()
          == QStringLiteral("folder-development"));
    REQUIRE(model.moveEntryById(firstId, model.entries().last().id));
    CHECK(model.entries().last().id == firstId);
    CHECK(model.data(model.index(2, 0), kdockw::DockEntriesModel::IconNameRole).toString()
          == QStringLiteral("folder-development"));
    REQUIRE(model.setFolderStackIcon(firstId, {}, QUrl::fromLocalFile(QStringLiteral("/tmp/folder.svg"))));
    CHECK(model.data(model.index(2, 0), kdockw::DockEntriesModel::IconUrlRole).toUrl()
          == QUrl::fromLocalFile(QStringLiteral("/tmp/folder.svg")));
    CHECK_FALSE(model.setFolderStackIcon(firstId, {}, QUrl(QStringLiteral("https://example.test/icon.png"))));
    CHECK(model.entries().last().iconUrl == QUrl::fromLocalFile(QStringLiteral("/tmp/folder.svg")));
    CHECK(model.rowCount() == 3);

    CHECK(model.moveEntry(2, 0));
    CHECK(model.entries().at(0).type == kdockw::DockEntryType::FolderStack);
    CHECK_FALSE(model.moveEntry(0, 0));
    CHECK_FALSE(model.removeFolderStack(task.id));
    CHECK(model.removeFolderStack(model.entries().at(0).id));
    CHECK(model.rowCount() == 2);
    CHECK(model.entries().at(1).type == kdockw::DockEntryType::FolderStack);
}

TEST_CASE("Dock entries model preserves widget slots while syncing TaskManager launchers", "[dock-entries][dock-widgets]")
{
    kdockw::DockEntriesModel model;
    CHECK(model.appendSeparator(QStringLiteral("invalid")).isEmpty());
    const QString startId = model.appendSeparator(QStringLiteral("start"));
    const QString endId = model.appendSeparator(QStringLiteral("end"));
    REQUIRE_FALSE(startId.isEmpty());
    REQUIRE_FALSE(endId.isEmpty());
    const auto start = model.entries().at(0);
    const auto end = model.entries().at(1);
    const auto folder = kdockw::DockEntry::folderStack(QUrl::fromLocalFile(QStringLiteral("/tmp/Downloads")));
    model.setEntries({kdockw::DockEntry::task(QUrl(QStringLiteral("applications:org.example.Old"))),
                      start, folder, end});
    model.syncTaskOrder({QStringLiteral("applications:org.example.New")});

    const auto entries = model.entries();
    REQUIRE(entries.size() == 4);
    CHECK(entries.at(0).type == kdockw::DockEntryType::Task);
    CHECK(entries.at(1).type == kdockw::DockEntryType::BuiltInWidget);
    CHECK(entries.at(1).id == start.id);
    CHECK(entries.at(1).slot == kdockw::DockWidgetSlot::Start);
    CHECK(entries.at(2).type == kdockw::DockEntryType::FolderStack);
    CHECK(entries.at(3).type == kdockw::DockEntryType::BuiltInWidget);
    CHECK(entries.at(3).id == end.id);
    CHECK(entries.at(3).slot == kdockw::DockWidgetSlot::End);
    CHECK(model.data(model.index(1, 0), kdockw::DockEntriesModel::PlacementSlotRole).toString()
          == QStringLiteral("start"));
    CHECK(model.data(model.index(3, 0), kdockw::DockEntriesModel::PlacementSlotRole).toString()
          == QStringLiteral("end"));
    CHECK(model.removeBuiltInWidget(start.id));
    CHECK_FALSE(model.removeBuiltInWidget(start.id));
}

TEST_CASE("Application Launcher entry persists its icon and can be configured", "[dock-entries][application-launcher]")
{
    kdockw::DockEntriesModel model;
    const QString id = model.appendApplicationLauncher(QStringLiteral("end"));
    REQUIRE_FALSE(id.isEmpty());
    REQUIRE(model.rowCount() == 1);
    CHECK(model.data(model.index(0, 0), kdockw::DockEntriesModel::WidgetKindRole).toString()
          == QStringLiteral("applicationLauncher"));
    CHECK(model.data(model.index(0, 0), kdockw::DockEntriesModel::PlacementSlotRole).toString()
          == QStringLiteral("end"));
    REQUIRE(model.setBuiltInWidgetIcon(id, QStringLiteral("start-here-kde")));
    CHECK(model.data(model.index(0, 0), kdockw::DockEntriesModel::IconNameRole).toString()
          == QStringLiteral("start-here-kde"));
    REQUIRE(model.setBuiltInWidgetSlot(id, QStringLiteral("start")));
    CHECK(model.setBuiltInWidgetVisible(id, false));

    const auto decoded = kdockw::DockEntriesCodec::decode(kdockw::DockEntriesCodec::encode(model.entries()));
    REQUIRE(decoded.validDocument);
    REQUIRE(decoded.entries.size() == 1);
    CHECK(decoded.entries.first().id == id);
    CHECK(decoded.entries.first().widgetKind == QStringLiteral("applicationLauncher"));
    CHECK(decoded.entries.first().iconName == QStringLiteral("start-here-kde"));
    CHECK(decoded.entries.first().slot == kdockw::DockWidgetSlot::Start);
    CHECK_FALSE(decoded.entries.first().widgetVisible);
}

TEST_CASE("Dock widget management adds edits moves hides and removes persisted entries", "[dock-entries][dock-widgets]")
{
    kdockw::DockEntriesModel model;
    const QString separatorId = model.appendSeparator(QStringLiteral("start"));
    const QString spacerId = model.appendSpacer(80, QStringLiteral("center"));
    REQUIRE_FALSE(separatorId.isEmpty());
    CHECK(model.setBuiltInWidgetSize(separatorId, 36));
    CHECK(model.data(model.index(0, 0), kdockw::DockEntriesModel::WidgetSizeRole).toInt() == 36);
    REQUIRE_FALSE(spacerId.isEmpty());
    CHECK(model.appendSpacer(3).isEmpty());
    CHECK(model.setBuiltInWidgetSize(spacerId, 128));
    CHECK(model.setBuiltInWidgetVisible(spacerId, false));
    CHECK(model.setBuiltInWidgetSlot(spacerId, QStringLiteral("end")));
    CHECK(model.data(model.index(1, 0), kdockw::DockEntriesModel::WidgetSizeRole).toInt() == 128);
    CHECK_FALSE(model.data(model.index(1, 0), kdockw::DockEntriesModel::WidgetVisibleRole).toBool());
    CHECK(model.data(model.index(1, 0), kdockw::DockEntriesModel::PlacementSlotRole).toString() == QStringLiteral("end"));
    CHECK(model.moveEntryById(spacerId, separatorId));
    CHECK(model.entries().first().id == spacerId);
    CHECK(model.entryIdAt(0) == spacerId);
    CHECK(model.entryTypeAt(0) == QStringLiteral("builtInWidget"));
    CHECK(model.removeBuiltInWidget(spacerId));
    CHECK_FALSE(model.removeBuiltInWidget(spacerId));
}
