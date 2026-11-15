# Plasma Launcher Favorites (Plasma 6.6.6)

## Installed interface checked

The installed system reports `plasmashell 6.6.6`. Its QML module directory is
`/usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/plasma/private/kicker/` and exports
`Kicker.RootModel` through `org.kde.plasma.private.kicker`. The installed
`kickerplugin.qmltypes` describes `RootModel.favoritesModel`; the local
Plasma-integrated PearDock QML also obtains this property and reads the
`model.favoriteId` role from its favorites-backed delegates.

This is a private Plasma module, not a stable public API. It may be missing or
change between Plasma releases. KDockW therefore loads its favorites reader
through a separate QML `Loader`; failure leaves the Windows Start launcher
usable and records an unavailable import status. It only reads the model and
never calls favorite mutation methods.

## Import contract

- On the first Windows Start view, wait for the KService catalog and the
  optional Kicker source to settle, then persist an attempted marker.
- Preserve any existing Start pins. An empty persisted list before the first
  attempt may be seeded from the source; removing pins after that attempt does
  not trigger a second import.
- Map Kicker IDs to the current application catalog's stable IDs. Accept
  `applications:` identifiers, preserve source order, and skip invalid,
  duplicate, or non-application records.
- Keep the imported list in KDockW settings. Never write back to Plasma or
  change any Plasma applet configuration.
- Report source unavailability or an empty/unsupported source in the Start
  home state rather than blocking application search and launch.

The source data and exact ID mapping still require functional confirmation in
the owner's Plasma 6.6.6 session. Automated tests cover state persistence,
one-time behavior, ordering, de-duplication, and invalid identifiers without
reading or modifying the host favorites.
