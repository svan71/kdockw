// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QObject>
#include <QPointer>
#include <QPointF>
#include <QHash>
#include <QMetaType>
#include <QSet>
#include <QString>
#include <QVariantMap>
#include <QWindow>

#include <cstdint>
#include <functional>
#include <memory>

struct wl_pointer;
struct wl_registry;
struct wl_seat;
struct wl_surface;
class QPlatformSurfaceEvent;

namespace kdockw
{

/** A compositor pointer sample tied to one live Wayland surface. */
struct PointerSample
{
    QPointF surfaceLocalPosition;
    quint64 sequence = 0;
    quint64 surfaceId = 0;
    quint64 surfaceGeneration = 0;
    quint32 pointerGeneration = 0;
    QPointer<QWindow> focusedWindow;
    bool valid = false;
    bool focusKnown = false;
};

/**
 * Authoritative Wayland pointer focus for one window.
 *
 * Qt's hover state cannot answer "is the pointer over this window" after a
 * popup grab: when a grabbing popup (e.g. a QMenu) opens, QtWayland
 * synthesizes a leave event for the parent window although the compositor
 * keeps pointer focus on it, and when the popup closes it synthesizes the
 * matching enter only for xdg-shell parents. A layer-shell parent such as
 * the dock therefore looks "outside" until the next real motion.
 *
 * This tracker binds its own wl_seat from its own registry and keeps its own
 * wl_pointer for as long as that seat has the pointer capability: created
 * when the capability appears (also after KDockW started without a pointer
 * device) and released when it goes away. The proxies live on the display's
 * default queue, so callbacks run on the GUI thread through Qt's event loop.
 * It records only the compositor's real enter/leave events and emits
 * pointerInsideChanged() when they change whether the pointer is on the
 * window. KWin advertises one seat; the first advertised seat is tracked.
 * Without Wayland, a seat or a pointer it reports the pointer as outside.
 */
class PointerFocusTracker : public QObject
{
    Q_OBJECT

public:
    explicit PointerFocusTracker(QWindow *window, QObject *parent = nullptr);
    ~PointerFocusTracker() override;

    PointerFocusTracker(const PointerFocusTracker &) = delete;
    PointerFocusTracker &operator=(const PointerFocusTracker &) = delete;

    /// True when the compositor's pointer focus is the window's current surface.
    [[nodiscard]] virtual bool isPointerInside() const;
    /// True when a Wayland pointer focus surface is currently known.
    [[nodiscard]] virtual bool hasPointerFocus() const;
    /// Window currently holding compositor pointer focus, if it belongs to
    /// this client. This lets QML distinguish the dock from its own popup
    /// surfaces instead of treating every surface leave as leaving the UI.
    [[nodiscard]] virtual QWindow *pointerFocusWindow() const;
    /// Whether this tracker has a supported Wayland display source. This is
    /// independent of current pointer focus or seat pointer capability.
    [[nodiscard]] virtual bool isAvailable() const;
    /// Current identity of the dock's live surface, or zero before mapping.
    [[nodiscard]] virtual quint64 dockSurfaceId() const;
    [[nodiscard]] virtual quint64 dockSurfaceGeneration() const;

    /// Enable event-driven surface diagnostics without changing pointer handling.
    void setDiagnosticEnabled(bool enabled);
    /// Register an in-process window with a diagnostic role such as dock or media-popup.
    void registerDiagnosticWindow(QWindow *window, const QString &role);
    /// Return the last observed Wayland focus/motion state without dispatching or synthesizing input.
    [[nodiscard]] QVariantMap diagnosticSnapshot() const;

Q_SIGNALS:
    /// Emitted when a compositor enter/leave changes isPointerInside().
    void pointerInsideChanged();
    /// Emitted whenever the compositor changes pointer-focused surface.
    void pointerFocusChanged();
    /// Published for every dock enter/motion and focus invalidation, even when
    /// detailed diagnostics are disabled.
    void pointerSampleChanged(const kdockw::PointerSample &sample);
    /// Emitted synchronously on the Wayland event thread when diagnostics are enabled.
    void diagnosticEvent(const QString &event, const QVariantMap &details);

protected:
    /// Construct a tracker adapter without binding a compositor registry.
    /// Production instances always use the public Wayland-backed constructor.
    explicit PointerFocusTracker(QWindow *window, bool initializeWayland, QObject *parent = nullptr);
    /// Adapter seam for deterministic DockView/QML integration tests. The
    /// production tracker calls the same signal from wl_pointer callbacks.
    void publishPointerSample(const PointerSample &sample);

private:
    void bindSeat(uint32_t name, uint32_t version);
    void releaseSeat();
    /// Create or release the wl_pointer to follow the seat's capabilities.
    void setCapabilities(uint32_t capabilities);
    void releasePointer(const QString &reason = QString());

    /// Store the new focus and emit pointerInsideChanged() if the result of
    /// isPointerInside() changed.
    void setFocusedSurface(wl_surface *surface);
    void watchSurfaceWindow(QWindow *window);
    void handleSurfaceLifecycleEvent(QWindow *window, QPlatformSurfaceEvent *event);
    void publishSurfaceSample(wl_surface *surface, const QPointF &position, bool valid);
    void invalidatePointerSample(wl_surface *surface = nullptr);
    [[nodiscard]] quint64 surfaceGenerationFor(wl_surface *surface);
    bool eventFilter(QObject *watched, QEvent *event) override;
    void watchWindow(QWindow *window, const QString &role);
    void recordDiagnostic(const QString &event, QVariantMap details, bool pointerEvent = false);
    [[nodiscard]] QVariantMap surfaceDetails(wl_surface *surface);
    [[nodiscard]] QVariantMap focusedSurfaceDetails();
    [[nodiscard]] QVariantMap windowDetails(QWindow *window) const;
    [[nodiscard]] QWindow *windowForSurface(wl_surface *surface) const;
    [[nodiscard]] wl_surface *surfaceForWindow(QWindow *window) const;
    [[nodiscard]] quint64 idForSurface(wl_surface *surface);

    static void handleGlobal(void *data, wl_registry *registry, uint32_t name, const char *interface, uint32_t version);
    static void handleGlobalRemove(void *data, wl_registry *registry, uint32_t name);
    static void handleCapabilities(void *data, wl_seat *seat, uint32_t capabilities);
    static void handleEnter(void *data, wl_pointer *pointer, uint32_t serial, wl_surface *surface, int32_t x, int32_t y);
    static void handleLeave(void *data, wl_pointer *pointer, uint32_t serial, wl_surface *surface);
    static void handleMotion(void *data, wl_pointer *pointer, uint32_t serial, int32_t x, int32_t y);

    QPointer<QWindow> m_window;
    wl_registry *m_registry = nullptr;
    wl_seat *m_seat = nullptr;
    uint32_t m_seatName = 0;
    wl_pointer *m_pointer = nullptr;
    // Compared by address only; never dereferenced (it may be stale after
    // the window's surface is recreated).
    wl_surface *m_focusedSurface = nullptr;
    quint64 m_focusedSurfaceId = 0;
    bool m_lastInside = false;
    bool m_diagnosticEnabled = false;
    bool m_destroying = false;
    quint32 m_pointerGeneration = 0;
    quint64 m_pointerEventSequence = 0;
    quint64 m_diagnosticSequence = 0;
    QVariantMap m_lastDiagnosticEvent;
    QVariantMap m_lastPointerEvent;
    QVariantMap m_lastPointerMotion;
    quint64 m_nextWindowId = 0;
    quint64 m_nextSurfaceId = 0;
    quint64 m_nextSurfaceGeneration = 0;
    quint64 m_pointerSampleSequence = 0;
    quint64 m_dockSurfaceId = 0;
    quint64 m_dockSurfaceGeneration = 0;
    QHash<wl_surface *, quint64> m_surfaceGenerations;
    QHash<QWindow *, wl_surface *> m_windowSurfaceHandles;
    QHash<QWindow *, quint64> m_windowSurfaceGenerations;
    QHash<wl_surface *, QPointer<QWindow>> m_surfaceWindows;
    QSet<QWindow *> m_surfaceLifecycleWindows;
    QHash<QWindow *, quint64> m_windowIds;
    QHash<QWindow *, qint64> m_lastWindowMotionDiagnosticNs;
    quint32 m_qtWindowInputEventCount = 0;
    bool m_qtWindowInputEventLimitReported = false;
    QHash<QWindow *, quint64> m_windowSurfaceIds;
    QHash<QWindow *, QString> m_windowRoles;
    QSet<QWindow *> m_watchedWindows;
    QHash<wl_surface *, quint64> m_surfaceIds;
};

using PointerFocusTrackerFactory = std::function<std::unique_ptr<PointerFocusTracker>(QWindow *)>;

} // namespace kdockw

Q_DECLARE_METATYPE(kdockw::PointerSample)
