// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Mock of DockModel. Per-index lookups read roles from tasksModel so a test
// only has to populate one place: DockModel.tasksModel.addTask({ ... }).
// Mock-only roles: IconName, IsOnCurrentDesktop; IsLauncher backs isPinned().
pragma Singleton
import QtQuick
import kdockw.test

QtObject {
    readonly property MockTasksModel tasksModel: MockTasksModel {}
    readonly property var dockPresentationModel: tasksModel
    readonly property QtObject applicationCatalog: QtObject {
        signal catalogChanged()
        property bool ready: false
        property var applications: []
        property var menuTree: []
        function ensureLoaded() { ready = true; catalogChanged() }
        function refresh() { ready = true; catalogChanged() }
        function search(query) { return [] }
        function application(serviceId) { return ({}) }
        function launch(serviceId) { return false }
        function launchAction(serviceId, actionName) { return false }
    }
    readonly property QtObject applicationLauncherState: QtObject {
        property string style: "launchpad"
        property var pinnedApplicationIds: []
        function isPinned(serviceId) { return pinnedApplicationIds.includes(serviceId) }
        function togglePinned(serviceId) { }
        function movePinned(fromIndex, toIndex) { return false }
    }
    readonly property var dockEntriesModel: ListModel {
        id: entries
        property int _nextWidgetId: 0
        function entryIdAt(row) { return row >= 0 && row < count ? get(row).entryId : "" }
        function entryTypeAt(row) { return row >= 0 && row < count ? get(row).entryType : "" }
        function appendSeparator(slot) {
            const id = "widget:separator:mock-" + (++_nextWidgetId)
            append({ entryId: id, entryType: "builtInWidget", widgetKind: "separator",
                     placementSlot: slot || "center", widgetSize: 0, widgetVisible: true })
            return id
        }
        function appendSpacer(size, slot) {
            const id = "widget:spacer:mock-" + (++_nextWidgetId)
            append({ entryId: id, entryType: "builtInWidget", widgetKind: "spacer",
                     placementSlot: slot || "center", widgetSize: size, widgetVisible: true })
            return id
        }
        function removeBuiltInWidget(entryId) {
            for (let row = 0; row < count; ++row) {
                if (get(row).entryId === entryId && get(row).entryType === "builtInWidget") {
                    remove(row)
                    return true
                }
            }
            return false
        }
        function setBuiltInWidgetSize(entryId, size) {
            for (let row = 0; row < count; ++row)
                if (get(row).entryId === entryId) { setProperty(row, "widgetSize", size); return true }
            return false
        }
        function setBuiltInWidgetVisible(entryId, visible) {
            for (let row = 0; row < count; ++row)
                if (get(row).entryId === entryId) { setProperty(row, "widgetVisible", visible); return true }
            return false
        }
        function setBuiltInWidgetSlot(entryId, slot) {
            for (let row = 0; row < count; ++row)
                if (get(row).entryId === entryId) { setProperty(row, "placementSlot", slot); return true }
            return false
        }
        function moveEntry(from, to) { if (from < 0 || to < 0 || from >= count || to >= count) return false; move(from, to, 1); return true }
        function removeFolderStack(entryId) {
            for (let row = 0; row < count; ++row) {
                if (get(row).entryId === entryId) {
                    remove(row)
                    return true
                }
            }
            return false
        }
    }
    property int currentDesktop: 1
    // 0=ShowAll, 1=DimOtherDesktops, 2=CurrentOnly
    property int virtualDesktopMode: 0
    // Fixtures supply prepartitioned task rows and their pinned boundary;
    // production DockModel's sorting is exercised by the model/native suites.
    property int pinnedTaskCount: 0
    readonly property int pinnedDockEntryCount: pinnedTaskCount + entries.count
    property var delegateGeometryRequests: []
    property var folderThemeIconRequests: []

    function _role(i, name) { return tasksModel.get(i, name) }
    function isPinned(i) { return !!_role(i, "IsLauncher") }
    function appId(i) { return _role(i, "AppId") || "" }
    function iconName(i) { return _role(i, "IconName") || "" }
    function launcherUrl(i) { return _role(i, "LauncherUrl") || "" }
    function isOnCurrentDesktop(i) { let v = _role(i, "IsOnCurrentDesktop"); return v === undefined ? true : !!v }
    function childCount(i) { return tasksModel.rowCount(tasksModel.index(i, 0)) }
    function isDesktopFile(url) { return url.toString().endsWith(".desktop") }
    function isLocalDirectory(url) { return url.toString() === "file:///tmp" || url.toString().endsWith("/") }
    function moveDockEntry(fromId, toId) { return tasksModel.moveByEntryId(fromId, toId) }
    function chooseFolderStackThemeIcon(entryId, transientParent) {
        folderThemeIconRequests = folderThemeIconRequests.concat([{
            entryId: entryId,
            hasTransientParent: !!transientParent,
        }])
        return true
    }

    function publishDelegateGeometry(i, delegate) {
        delegateGeometryRequests = delegateGeometryRequests.concat([{
            index: i,
            isWindow: !!_role(i, "IsWindow"),
            isGroupParent: !!_role(i, "IsGroupParent"),
            childCount: _role(i, "ChildCount") || 0,
            geometry: {
                x: delegate.x,
                y: delegate.y,
                width: delegate.width,
                height: delegate.height,
            },
        }])
    }

    function resetDelegateGeometryRequests() {
        delegateGeometryRequests = []
    }

    function reset() {
        tasksModel.reset()
        entries.clear()
        currentDesktop = 1
        virtualDesktopMode = 0
        pinnedTaskCount = 0
        folderThemeIconRequests = []
        resetDelegateGeometryRequests()
    }
}
