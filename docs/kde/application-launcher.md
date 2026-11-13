# Application Launcher APIs (KService + KIO)

Verified against the installed KF6 headers under `/usr/include/KF6/KService`,
`/usr/include/KF6/KConfigCore`, and `/usr/include/KF6/KIOGui`.

## System menu and catalog

- Start from `KServiceGroup::root()` and recursively read
  `entries(false, true, true)`. `sorted=false` preserves the menu's entry
  order; `excludeNoDisplay=true` excludes hidden menu rows and
  `allowSeparators=true` preserves menu separators where relevant.
- `KServiceGroup::Ptr` entries are `KSycocaEntry` pointers. Check
  `isType(KST_KServiceGroup)` or `isType(KST_KService)` before casting.
- Use `KService::name()`, `genericName()`, `comment()`, `icon()`,
  `categories()`, `keywords()`, `menuId()`, `storageId()`, and `actions()`;
  text getters return KDE-localized values where provided.
- `KService::noDisplay()`, `showInCurrentDesktop()`, and
  `showOnCurrentPlatform()` cover KDE's menu visibility checks. `Hidden=true`
  is checked from the desktop file because KService has no `hidden()` getter.
  Resolve the service's entry path as an applications resource and use
  `KDesktopFile::tryExec()` when `TryExec` is set.
- Prefer `menuId()` as the canonical menu identity, then
  `desktopEntryName()`, and use `storageId()` only as a last fallback. This
  coalesces entries exposed through multiple menu paths without persisting
  absolute paths.
- Search with `KApplicationTrader::query(FilterFunc)` and
  `KApplicationTrader::isSubsequence()` over localized names, generic names,
  comments, categories, and keywords. Do not use a query that accepts every
  service as a cheap catalog enumeration; KServiceGroup supplies the visible
  menu tree.
- Connect to `KSycoca::self()->databaseChanged()` and coalesce refreshes on the
  GUI event queue. KService/KServiceGroup remain the source of truth; keep only
  an in-memory index and rebuild it after the system cache changes.

## Launching

Resolve the selected stable service ID again through KService, then construct
`KIO::ApplicationLauncherJob(service)` and call `start()`. Desktop actions use
`KIO::ApplicationLauncherJob(KServiceAction)`. Do not parse `Exec` or invoke a
shell. The asynchronous job owns KDE startup notification and Wayland XDG
activation handling; close the launcher popup after a successful start.

## Build dependency

KDockW already links `KF6::Service`, `KF6::KIOGui`, and `KF6::ConfigCore`.
This launcher contract requires no new package dependency.
