# MPRIS2 with QtDBus

## Verified local Qt API

Verified against Qt 6.10.2 headers installed under
`/usr/include/x86_64-linux-gnu/qt6/QtDBus/`:

- `QDBusConnection::asyncCall(const QDBusMessage &, int)` returns a pending
  call without blocking the caller. Observe completion with
  `QDBusPendingCallWatcher` and inspect it through `QDBusPendingReply<T>`.
- `QDBusServiceWatcher` watches explicit names for registration,
  unregistration, or owner changes. MPRIS names share a prefix, so initial
  enumeration uses an asynchronous `org.freedesktop.DBus.ListNames` call;
  one `NameOwnerChanged` subscription can then filter that prefix without
  periodic polling.
- `QDBusConnection::connect` supports matching the bus daemon's
  `NameOwnerChanged` signal and each service's
  `org.freedesktop.DBus.Properties.PropertiesChanged` and player `Seeked`
  signals. `disconnect` removes those exact matches during teardown.
- The project already links `Qt6::DBus`, and existing code uses the same
  asynchronous watcher/reply pattern. No new package dependency is required.

## MPRIS contract

The well-known service prefix is `org.mpris.MediaPlayer2.` and the object path
is `/org/mpris/MediaPlayer2`. Read `org.mpris.MediaPlayer2` and
`org.mpris.MediaPlayer2.Player` properties through the standard
`org.freedesktop.DBus.Properties` interface. Handle missing optional
properties and remove a session when its well-known name loses its owner.

`Position`, `mpris:length`, `Seek`, and `SetPosition` use microseconds.
`SetPosition` also takes the current `mpris:trackid`, allowing the player to
ignore a seek sent for a previous track. `Seeked` reports discontinuous
position changes. MPRIS does not require periodic `PropertiesChanged` updates
for normal position progression, so the UI extrapolates from the last known
position with a monotonic clock while the selected session is Playing and
stops progression while paused.

Every method/property action is sent to the currently selected service at
dispatch time, asynchronously. Check read-only `Can*` properties before
presenting an action as available. D-Bus errors are non-fatal and must not
retain session objects after an owner change.

## Sources

- [MPRIS D-Bus Interface Specification 2.2](https://specifications.freedesktop.org/mpris/latest/)
- [MPRIS Player Interface](https://specifications.freedesktop.org/mpris/latest/Player_Interface.html)
