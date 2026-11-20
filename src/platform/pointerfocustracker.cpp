// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "pointerfocustracker.h"

#include <wayland-client.h>

#include <algorithm>
#include <string_view>

#include <QCoreApplication>
#include <QEnterEvent>
#include <QEvent>
#include <QGuiApplication>
#include <QHoverEvent>
#include <QMouseEvent>
#include <QPlatformSurfaceEvent>
#include <QRegion>
#include <QScreen>
#include <QtGui/qguiapplication_platform.h>
#include <qpa/qplatformnativeinterface.h>

#include <time.h>

namespace kdockw
{

namespace
{

void ignoreButton(void *, wl_pointer *, uint32_t, uint32_t, uint32_t, uint32_t)
{
}

void ignoreAxis(void *, wl_pointer *, uint32_t, uint32_t, wl_fixed_t)
{
}

void ignoreFrame(void *, wl_pointer *)
{
}

void ignoreAxisSource(void *, wl_pointer *, uint32_t)
{
}

void ignoreAxisStop(void *, wl_pointer *, uint32_t, uint32_t)
{
}

void ignoreAxisDiscrete(void *, wl_pointer *, uint32_t, int32_t)
{
}

#ifdef WL_POINTER_AXIS_VALUE120_SINCE_VERSION
void ignoreAxisValue120(void *, wl_pointer *, uint32_t, int32_t)
{
}
#endif

#ifdef WL_POINTER_AXIS_RELATIVE_DIRECTION_SINCE_VERSION
void ignoreAxisRelativeDirection(void *, wl_pointer *, uint32_t, uint32_t)
{
}
#endif

#ifdef WL_POINTER_WARP_SINCE_VERSION
void ignoreWarp(void *, wl_pointer *, wl_fixed_t, wl_fixed_t)
{
}
#endif

void ignoreSeatName(void *, wl_seat *, const char *)
{
}

// wl_seat.release (and wl_pointer.release) need version 5; nothing newer is
// used, so the pointer never receives events from later versions either.
constexpr uint32_t s_seatVersion = 5;
constexpr quint32 s_maxQtWindowInputEvents = 8192;
constexpr qint64 s_qtWindowMotionSampleIntervalNs = 16'000'000;

QString qtPointerEventName(QEvent::Type type)
{
    switch (type) {
    case QEvent::Enter:
        return QStringLiteral("Enter");
    case QEvent::Leave:
        return QStringLiteral("Leave");
    case QEvent::MouseMove:
        return QStringLiteral("MouseMove");
    case QEvent::MouseButtonPress:
        return QStringLiteral("MouseButtonPress");
    case QEvent::MouseButtonRelease:
        return QStringLiteral("MouseButtonRelease");
    case QEvent::HoverEnter:
        return QStringLiteral("HoverEnter");
    case QEvent::HoverMove:
        return QStringLiteral("HoverMove");
    case QEvent::HoverLeave:
        return QStringLiteral("HoverLeave");
    default:
        return {};
    }
}

QVariantMap pointDetails(const QPointF &point)
{
    return {
        {QStringLiteral("x"), point.x()},
        {QStringLiteral("y"), point.y()},
    };
}

} // namespace

PointerFocusTracker::PointerFocusTracker(QWindow *window, QObject *parent)
    : PointerFocusTracker(window, true, parent)
{
}

PointerFocusTracker::PointerFocusTracker(QWindow *window, bool initializeWayland, QObject *parent)
    : QObject(parent)
    , m_window(window)
{
    watchSurfaceWindow(window);
    if (!initializeWayland) {
        return;
    }
    auto *waylandApp = qGuiApp ? qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>() : nullptr;
    if (!waylandApp || !waylandApp->display()) {
        return;
    }
    static const wl_registry_listener listener = {
        .global = &PointerFocusTracker::handleGlobal,
        .global_remove = &PointerFocusTracker::handleGlobalRemove,
    };
    // A registry and seat of our own: Qt's seat proxy already has Qt's
    // listener, and Qt exposes no signal for its capability changes. The
    // registry inherits the display's default queue, which Qt dispatches on
    // the GUI thread; so do the seat and pointer created from it.
    m_registry = wl_display_get_registry(waylandApp->display());
    if (m_registry) {
        wl_registry_add_listener(m_registry, &listener, this);
    }
}

PointerFocusTracker::~PointerFocusTracker()
{
    // DockView's trace sink is a later-declared member and is destroyed before
    // this tracker. Keep teardown from emitting diagnostics through that sink.
    m_diagnosticEnabled = false;
    m_destroying = true;
    releaseSeat();
    m_focusedSurface = nullptr;
    if (m_registry) {
        wl_registry_destroy(m_registry);
    }
}

void PointerFocusTracker::bindSeat(uint32_t name, uint32_t version)
{
    if (m_seat) {
        return;
    }
    static const wl_seat_listener listener = {
        .capabilities = &PointerFocusTracker::handleCapabilities,
        .name = ignoreSeatName,
    };
    m_seat = static_cast<wl_seat *>(wl_registry_bind(m_registry, name, &wl_seat_interface, std::min(version, s_seatVersion)));
    if (m_seat) {
        m_seatName = name;
        wl_seat_add_listener(m_seat, &listener, this);
        recordDiagnostic(QStringLiteral("wayland-seat-bound"), {
            {QStringLiteral("seatGlobalName"), m_seatName},
            {QStringLiteral("advertisedVersion"), version},
            {QStringLiteral("boundVersion"), std::min(version, s_seatVersion)},
        });
    }
}

void PointerFocusTracker::releaseSeat()
{
    invalidatePointerSample(m_focusedSurface);
    releasePointer(QStringLiteral("seat-released"));
    if (!m_seat) {
        return;
    }
    recordDiagnostic(QStringLiteral("wayland-seat-released"), {
        {QStringLiteral("seatGlobalName"), m_seatName},
        {QStringLiteral("focusedSurfaceBefore"), focusedSurfaceDetails()},
    });
    if (wl_proxy_get_version(reinterpret_cast<wl_proxy *>(m_seat)) >= WL_SEAT_RELEASE_SINCE_VERSION) {
        wl_seat_release(m_seat);
    } else {
        wl_seat_destroy(m_seat);
    }
    m_seat = nullptr;
    m_seatName = 0;
}

void PointerFocusTracker::setCapabilities(uint32_t capabilities)
{
    recordDiagnostic(QStringLiteral("wayland-seat-capabilities"), {
        {QStringLiteral("capabilities"), capabilities},
        {QStringLiteral("pointerCapability"), (capabilities & WL_SEAT_CAPABILITY_POINTER) != 0},
        {QStringLiteral("focusedSurfaceBefore"), focusedSurfaceDetails()},
    });
    if (!(capabilities & WL_SEAT_CAPABILITY_POINTER)) {
        // The protocol makes the old pointer defunct; a regained capability
        // needs a new one.
        releasePointer(QStringLiteral("pointer-capability-lost"));
        setFocusedSurface(nullptr);
        invalidatePointerSample();
        recordDiagnostic(QStringLiteral("wayland-pointer-focus-cleared"), {
            {QStringLiteral("reason"), QStringLiteral("pointer-capability-lost")},
            {QStringLiteral("focusedSurfaceAfter"), focusedSurfaceDetails()},
        });
        return;
    }
    if (m_pointer) {
        return;
    }

    // Every member is set: libwayland calls listener slots without null checks
    // for any event the bound version can send.
    static const wl_pointer_listener listener = {
        .enter = &PointerFocusTracker::handleEnter,
        .leave = &PointerFocusTracker::handleLeave,
        .motion = &PointerFocusTracker::handleMotion,
        .button = ignoreButton,
        .axis = ignoreAxis,
        .frame = ignoreFrame,
        .axis_source = ignoreAxisSource,
        .axis_stop = ignoreAxisStop,
        .axis_discrete = ignoreAxisDiscrete,
#ifdef WL_POINTER_AXIS_VALUE120_SINCE_VERSION
        .axis_value120 = ignoreAxisValue120,
#endif
#ifdef WL_POINTER_AXIS_RELATIVE_DIRECTION_SINCE_VERSION
        .axis_relative_direction = ignoreAxisRelativeDirection,
#endif
#ifdef WL_POINTER_WARP_SINCE_VERSION
        .warp = ignoreWarp,
#endif
    };

    // If the pointer already lies on one of our surfaces, the compositor
    // sends the new pointer an enter right away.
    m_pointer = wl_seat_get_pointer(m_seat);
    if (m_pointer) {
        ++m_pointerGeneration;
        wl_pointer_add_listener(m_pointer, &listener, this);
        recordDiagnostic(QStringLiteral("wayland-pointer-created"), {
            {QStringLiteral("pointerGeneration"), m_pointerGeneration},
            {QStringLiteral("seatGlobalName"), m_seatName},
        });
    }
}

void PointerFocusTracker::releasePointer(const QString &reason)
{
    if (!m_pointer) {
        return;
    }
    recordDiagnostic(QStringLiteral("wayland-pointer-destroyed"), {
        {QStringLiteral("pointerGeneration"), m_pointerGeneration},
        {QStringLiteral("seatGlobalName"), m_seatName},
        {QStringLiteral("reason"), reason},
        {QStringLiteral("focusedSurfaceBefore"), focusedSurfaceDetails()},
    });
    if (m_focusedSurface) {
        setFocusedSurface(nullptr);
    }
    invalidatePointerSample(m_focusedSurface);
    if (wl_proxy_get_version(reinterpret_cast<wl_proxy *>(m_pointer)) >= WL_POINTER_RELEASE_SINCE_VERSION) {
        wl_pointer_release(m_pointer);
    } else {
        wl_pointer_destroy(m_pointer);
    }
    m_pointer = nullptr;
}

bool PointerFocusTracker::isPointerInside() const
{
    if (!m_pointer || !m_focusedSurface || !m_window) {
        return false;
    }
    auto *nativeInterface = QGuiApplication::platformNativeInterface();
    if (!nativeInterface) {
        return false;
    }
    // Look the surface up each time: QtWayland recreates it when the window
    // is hidden and shown again.
    auto *surface = static_cast<wl_surface *>(nativeInterface->nativeResourceForWindow(QByteArrayLiteral("surface"), m_window.data()));
    return surface && surface == m_focusedSurface;
}

bool PointerFocusTracker::isAvailable() const
{
    // Source availability describes the backend, not whether the pointer is
    // currently over a surface or whether the compositor currently advertises
    // a pointer capability. Do not fall back to stale Qt coordinates for
    // those temporary states.
    return m_registry != nullptr;
}

quint64 PointerFocusTracker::dockSurfaceId() const
{
    return m_dockSurfaceId;
}

quint64 PointerFocusTracker::dockSurfaceGeneration() const
{
    return m_dockSurfaceGeneration;
}

bool PointerFocusTracker::hasPointerFocus() const
{
    return m_pointer && m_focusedSurface;
}

QWindow *PointerFocusTracker::pointerFocusWindow() const
{
    if (!m_focusedSurface) {
        return nullptr;
    }
    auto *nativeInterface = QGuiApplication::platformNativeInterface();
    if (!nativeInterface) {
        return nullptr;
    }
    for (QWindow *window : QGuiApplication::allWindows()) {
        auto *surface = static_cast<wl_surface *>(
            nativeInterface->nativeResourceForWindow(QByteArrayLiteral("surface"), window));
        if (surface && surface == m_focusedSurface) {
            return window;
        }
    }
    return nullptr;
}

void PointerFocusTracker::setDiagnosticEnabled(bool enabled)
{
    if (m_diagnosticEnabled == enabled) {
        return;
    }
    m_diagnosticEnabled = enabled;
    if (!enabled) {
        return;
    }
    for (QWindow *window : QGuiApplication::allWindows()) {
        watchWindow(window, window == m_window ? QStringLiteral("dock") : QStringLiteral("other"));
    }
    recordDiagnostic(QStringLiteral("wayland-diagnostics-ready"), {
        {QStringLiteral("seatGlobalName"), m_seatName},
        {QStringLiteral("pointerGeneration"), m_pointerGeneration},
        {QStringLiteral("focusedSurface"), focusedSurfaceDetails()},
    });
}

void PointerFocusTracker::registerDiagnosticWindow(QWindow *window, const QString &role)
{
    if (!m_diagnosticEnabled || !window) {
        return;
    }
    const QString safeRole = role == QLatin1String("dock")
            || role == QLatin1String("media-popup")
            || role == QLatin1String("window-preview")
        ? role
        : QStringLiteral("other");
    watchWindow(window, safeRole);
    QVariantMap details = windowDetails(window);
    details.insert(QStringLiteral("registrationRole"), safeRole);
    details.insert(QStringLiteral("surface"), surfaceDetails(surfaceForWindow(window)));
    recordDiagnostic(QStringLiteral("wayland-window-registered"), details);
}

void PointerFocusTracker::recordDiagnostic(const QString &event, QVariantMap details, bool pointerEvent)
{
    if (!m_diagnosticEnabled) {
        return;
    }
    details.insert(QStringLiteral("trackerEventSequence"), ++m_diagnosticSequence);
    if (pointerEvent) {
        details.insert(QStringLiteral("waylandPointerEventId"), ++m_pointerEventSequence);
    }
    details.insert(QStringLiteral("seatGlobalName"), m_seatName);
    details.insert(QStringLiteral("pointerGeneration"), m_pointerGeneration);
    details.insert(QStringLiteral("event"), event);
    m_lastDiagnosticEvent = details;
    if (pointerEvent) {
        m_lastPointerEvent = details;
    }
    Q_EMIT diagnosticEvent(event, details);
}

QVariantMap PointerFocusTracker::diagnosticSnapshot() const
{
    if (!m_diagnosticEnabled) {
        return {{QStringLiteral("available"), false},
                {QStringLiteral("reason"), QStringLiteral("diagnostics-disabled")}};
    }

    QVariantMap focusedSurface;
    if (m_focusedSurfaceId != 0) {
        focusedSurface.insert(QStringLiteral("surfaceId"), m_focusedSurfaceId);
        const bool surfaceTracked = m_focusedSurface
            && m_surfaceIds.value(m_focusedSurface) == m_focusedSurfaceId;
        focusedSurface.insert(QStringLiteral("surfaceStillTracked"), surfaceTracked);
        if (surfaceTracked) {
            focusedSurface.insert(QStringLiteral("waylandObjectId"),
                                  wl_proxy_get_id(reinterpret_cast<wl_proxy *>(m_focusedSurface)));
        }
        for (QWindow *window : m_watchedWindows) {
            if (!window || m_windowSurfaceIds.value(window) != m_focusedSurfaceId) {
                continue;
            }
            focusedSurface.insert(QStringLiteral("surfaceClass"),
                                  m_windowRoles.value(window, QStringLiteral("other")));
            focusedSurface.insert(QStringLiteral("window"), windowDetails(window));
            break;
        }
    }

    QVariantList windows;
    for (QWindow *window : m_watchedWindows) {
        if (!window) {
            continue;
        }
        QVariantMap details = windowDetails(window);
        const quint64 surfaceId = m_windowSurfaceIds.value(window);
        details.insert(QStringLiteral("surfaceId"), surfaceId);
        if (surfaceId != 0) {
            if (wl_surface *surface = surfaceForWindow(window)) {
                details.insert(QStringLiteral("waylandObjectId"),
                               wl_proxy_get_id(reinterpret_cast<wl_proxy *>(surface)));
            }
        }
        windows.append(details);
    }

    return {
        {QStringLiteral("available"), true},
        {QStringLiteral("seatGlobalName"), m_seatName},
        {QStringLiteral("pointerGeneration"), m_pointerGeneration},
        {QStringLiteral("pointerEventSequence"), static_cast<qint64>(m_pointerEventSequence)},
        {QStringLiteral("pointerCapabilityPresent"), m_pointer != nullptr},
        {QStringLiteral("pointerFocusKnown"), m_focusedSurface != nullptr},
        {QStringLiteral("focusedSurface"), focusedSurface},
        {QStringLiteral("lastWaylandEvent"), m_lastDiagnosticEvent},
        {QStringLiteral("lastWaylandPointerEvent"), m_lastPointerEvent},
        {QStringLiteral("lastWaylandPointerMotion"), m_lastPointerMotion},
        {QStringLiteral("watchedWindows"), windows},
    };
}

quint64 PointerFocusTracker::idForSurface(wl_surface *surface)
{
    if (!surface) {
        return 0;
    }
    const auto existing = m_surfaceIds.constFind(surface);
    if (existing != m_surfaceIds.cend()) {
        if (!m_surfaceGenerations.contains(surface)) {
            m_surfaceGenerations.insert(surface, ++m_nextSurfaceGeneration);
        }
        return existing.value();
    }
    const quint64 id = ++m_nextSurfaceId;
    m_surfaceIds.insert(surface, id);
    m_surfaceGenerations.insert(surface, ++m_nextSurfaceGeneration);
    if (surface == surfaceForWindow(m_window)) {
        m_dockSurfaceId = id;
        m_dockSurfaceGeneration = m_surfaceGenerations.value(surface);
    }
    return id;
}

quint64 PointerFocusTracker::surfaceGenerationFor(wl_surface *surface)
{
    if (!surface) {
        return 0;
    }
    (void)idForSurface(surface);
    return m_surfaceGenerations.value(surface);
}

void PointerFocusTracker::watchSurfaceWindow(QWindow *window)
{
    if (!window) {
        return;
    }
    if (!m_surfaceLifecycleWindows.contains(window)) {
        m_surfaceLifecycleWindows.insert(window);
        window->installEventFilter(this);

        connect(window, &QObject::destroyed, this, [this, window] {
            wl_surface *surface = m_windowSurfaceHandles.value(window, nullptr);
            if (surface && m_focusedSurface == surface) {
                setFocusedSurface(nullptr);
                invalidatePointerSample(surface);
            }
            if (surface) {
                m_surfaceIds.remove(surface);
                m_surfaceGenerations.remove(surface);
                m_surfaceWindows.remove(surface);
            }
            m_windowSurfaceHandles.remove(window);
            m_windowSurfaceGenerations.remove(window);
            m_surfaceLifecycleWindows.remove(window);
            if (window == m_window) {
                m_dockSurfaceId = 0;
                m_dockSurfaceGeneration = 0;
            }
        });
    }

    // Surface resources may not exist when the tracker is constructed. Keep
    // this method useful on later enter/diagnostic calls as well as from the
    // PlatformSurface event filter.
    wl_surface *surface = surfaceForWindow(window);
    if (!surface || m_windowSurfaceHandles.value(window) == surface) {
        return;
    }
    wl_surface *previous = m_windowSurfaceHandles.value(window, nullptr);
    if (previous) {
        m_surfaceIds.remove(previous);
        m_surfaceGenerations.remove(previous);
        m_surfaceWindows.remove(previous);
    }
    m_windowSurfaceHandles.insert(window, surface);
    const quint64 generation = m_windowSurfaceGenerations.value(window, 0) + 1;
    m_windowSurfaceGenerations.insert(window, generation);
    const quint64 surfaceId = idForSurface(surface);
    m_surfaceGenerations.insert(surface, generation);
    m_surfaceWindows.insert(surface, window);
    if (window == m_window) {
        m_dockSurfaceId = surfaceId;
        m_dockSurfaceGeneration = generation;
    }
}

void PointerFocusTracker::handleSurfaceLifecycleEvent(QWindow *window, QPlatformSurfaceEvent *event)
{
    if (!window || !event) {
        return;
    }

    if (event->surfaceEventType() == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed) {
        wl_surface *surface = m_windowSurfaceHandles.value(window, surfaceForWindow(window));
        const bool hadPointerFocus = surface && m_focusedSurface == surface;
        if (hadPointerFocus) {
            setFocusedSurface(nullptr);
        }
        if (surface && (hadPointerFocus || window == m_window)) {
            invalidatePointerSample(surface);
        }
        if (surface) {
            m_surfaceIds.remove(surface);
            m_surfaceGenerations.remove(surface);
            m_surfaceWindows.remove(surface);
        }
        m_windowSurfaceHandles.remove(window);
        m_windowSurfaceIds.remove(window);
        if (window == m_window) {
            m_dockSurfaceId = 0;
            m_dockSurfaceGeneration = 0;
        }
        return;
    }

    if (event->surfaceEventType() != QPlatformSurfaceEvent::SurfaceCreated) {
        return;
    }
    watchSurfaceWindow(window);
}

void PointerFocusTracker::publishSurfaceSample(wl_surface *surface, const QPointF &position, bool valid)
{
    if (m_destroying) {
        return;
    }
    PointerSample sample;
    sample.surfaceLocalPosition = valid ? position : QPointF{};
    sample.sequence = ++m_pointerSampleSequence;
    sample.surfaceId = surface ? idForSurface(surface) : 0;
    sample.surfaceGeneration = surface ? surfaceGenerationFor(surface) : 0;
    sample.pointerGeneration = m_pointerGeneration;
    sample.valid = valid && surface != nullptr;
    sample.focusKnown = m_pointer && m_focusedSurface != nullptr;
    sample.focusedWindow = sample.focusKnown ? m_surfaceWindows.value(surface) : nullptr;
    publishPointerSample(sample);
}

void PointerFocusTracker::invalidatePointerSample(wl_surface *surface)
{
    publishSurfaceSample(surface, {}, false);
}

void PointerFocusTracker::publishPointerSample(const PointerSample &sample)
{
    if (!m_destroying) {
        Q_EMIT pointerSampleChanged(sample);
    }
}

wl_surface *PointerFocusTracker::surfaceForWindow(QWindow *window) const
{
    if (!window) {
        return nullptr;
    }
    auto *nativeInterface = QGuiApplication::platformNativeInterface();
    if (!nativeInterface) {
        return nullptr;
    }
    return static_cast<wl_surface *>(nativeInterface->nativeResourceForWindow(
        QByteArrayLiteral("surface"), window));
}

QWindow *PointerFocusTracker::windowForSurface(wl_surface *surface) const
{
    if (!surface) {
        return nullptr;
    }
    if (const auto it = m_surfaceWindows.constFind(surface); it != m_surfaceWindows.cend()) {
        return it.value().data();
    }
    for (QWindow *window : QGuiApplication::allWindows()) {
        if (surfaceForWindow(window) == surface) {
            return window;
        }
    }
    return nullptr;
}

QVariantMap PointerFocusTracker::windowDetails(QWindow *window) const
{
    if (!window) {
        return {};
    }
    const QRect geometry = window->geometry();
    const QRect frameGeometry = window->frameGeometry();
    const QRegion mask = window->mask();
    const QRect maskBounds = mask.boundingRect();
    QVariantList maskRects;
    constexpr qsizetype maxMaskRects = 256;
    qsizetype rectIndex = 0;
    for (const QRect &rect : mask) {
        if (rectIndex++ >= maxMaskRects) {
            break;
        }
        maskRects.append(QVariantMap{
            {QStringLiteral("x"), rect.x()},
            {QStringLiteral("y"), rect.y()},
            {QStringLiteral("width"), rect.width()},
            {QStringLiteral("height"), rect.height()},
        });
    }
    const QScreen *screen = window->screen();
    const QRect screenGeometry = screen ? screen->geometry() : QRect{};
    return {
        {QStringLiteral("windowId"), m_windowIds.value(window)},
        {QStringLiteral("windowRole"), m_windowRoles.value(window, QStringLiteral("other"))},
        {QStringLiteral("objectName"), window->objectName()},
        {QStringLiteral("windowType"), static_cast<int>(window->type())},
        {QStringLiteral("visible"), window->isVisible()},
        {QStringLiteral("visibility"), static_cast<int>(window->visibility())},
        {QStringLiteral("devicePixelRatio"), window->devicePixelRatio()},
        {QStringLiteral("screenName"), screen ? screen->name() : QString()},
        {QStringLiteral("screenGeometryLogical"), QVariantMap{
            {QStringLiteral("x"), screenGeometry.x()},
            {QStringLiteral("y"), screenGeometry.y()},
            {QStringLiteral("width"), screenGeometry.width()},
            {QStringLiteral("height"), screenGeometry.height()},
        }},
        {QStringLiteral("geometryCoordinateSpace"), QStringLiteral("QWindow logical geometry; layer-shell compositor placement is not independently observable here")},
        {QStringLiteral("geometry"), QVariantMap{
            {QStringLiteral("x"), geometry.x()},
            {QStringLiteral("y"), geometry.y()},
            {QStringLiteral("width"), geometry.width()},
            {QStringLiteral("height"), geometry.height()},
        }},
        {QStringLiteral("frameGeometry"), QVariantMap{
            {QStringLiteral("x"), frameGeometry.x()},
            {QStringLiteral("y"), frameGeometry.y()},
            {QStringLiteral("width"), frameGeometry.width()},
            {QStringLiteral("height"), frameGeometry.height()},
        }},
        {QStringLiteral("qtWindowMask"), QVariantMap{
            {QStringLiteral("configured"), !mask.isEmpty()},
            {QStringLiteral("rectCount"), mask.rectCount()},
            {QStringLiteral("rectanglesTruncated"), mask.rectCount() > maskRects.size()},
            {QStringLiteral("rectangles"), maskRects},
            {QStringLiteral("boundingRect"), QVariantMap{
                {QStringLiteral("x"), maskBounds.x()},
                {QStringLiteral("y"), maskBounds.y()},
                {QStringLiteral("width"), maskBounds.width()},
                {QStringLiteral("height"), maskBounds.height()},
            }},
        }},
    };
}

QVariantMap PointerFocusTracker::surfaceDetails(wl_surface *surface)
{
    if (!surface) {
        return {};
    }
    const quint64 surfaceId = idForSurface(surface);
    QWindow *window = windowForSurface(surface);
    if (window && !m_watchedWindows.contains(window)) {
        watchWindow(window, window == m_window ? QStringLiteral("dock") : QStringLiteral("other"));
    }
    QVariantMap details{
        {QStringLiteral("surfaceId"), surfaceId},
        {QStringLiteral("waylandObjectId"), wl_proxy_get_id(reinterpret_cast<wl_proxy *>(surface))},
        {QStringLiteral("surfaceClass"), window ? m_windowRoles.value(window, QStringLiteral("other"))
                                                : QStringLiteral("unknown")},
        {QStringLiteral("windowSurfaceMatch"), window != nullptr},
    };
    if (window) {
        details.insert(QStringLiteral("window"), windowDetails(window));
    }
    return details;
}

QVariantMap PointerFocusTracker::focusedSurfaceDetails()
{
    if (!m_focusedSurfaceId) {
        return {};
    }
    if (m_focusedSurface && m_surfaceIds.value(m_focusedSurface) == m_focusedSurfaceId) {
        return surfaceDetails(m_focusedSurface);
    }
    return {
        {QStringLiteral("surfaceId"), m_focusedSurfaceId},
        {QStringLiteral("surfaceClass"), QStringLiteral("unknown")},
        {QStringLiteral("surfaceStillTracked"), false},
    };
}

void PointerFocusTracker::watchWindow(QWindow *window, const QString &role)
{
    if (!window) {
        return;
    }
    m_windowRoles.insert(window, role);
    if (!m_windowIds.contains(window)) {
        m_windowIds.insert(window, ++m_nextWindowId);
    }
    if (m_watchedWindows.contains(window)) {
        return;
    }
    m_watchedWindows.insert(window);
    watchSurfaceWindow(window);
    if (wl_surface *surface = surfaceForWindow(window)) {
        m_windowSurfaceIds.insert(window, idForSurface(surface));
    }
    const QPointer<QWindow> guardedWindow(window);
    const quint64 windowId = m_windowIds.value(window);
    connect(window, &QWindow::xChanged, this, [this, guardedWindow] {
        if (guardedWindow) {
            QVariantMap details = windowDetails(guardedWindow);
            details.insert(QStringLiteral("change"), QStringLiteral("x"));
            recordDiagnostic(QStringLiteral("wayland-window-geometry"), details);
        }
    });
    connect(window, &QWindow::yChanged, this, [this, guardedWindow] {
        if (guardedWindow) {
            QVariantMap details = windowDetails(guardedWindow);
            details.insert(QStringLiteral("change"), QStringLiteral("y"));
            recordDiagnostic(QStringLiteral("wayland-window-geometry"), details);
        }
    });
    connect(window, &QWindow::widthChanged, this, [this, guardedWindow] {
        if (guardedWindow) {
            QVariantMap details = windowDetails(guardedWindow);
            details.insert(QStringLiteral("change"), QStringLiteral("width"));
            recordDiagnostic(QStringLiteral("wayland-window-geometry"), details);
        }
    });
    connect(window, &QWindow::heightChanged, this, [this, guardedWindow] {
        if (guardedWindow) {
            QVariantMap details = windowDetails(guardedWindow);
            details.insert(QStringLiteral("change"), QStringLiteral("height"));
            recordDiagnostic(QStringLiteral("wayland-window-geometry"), details);
        }
    });
    connect(window, &QWindow::visibilityChanged, this, [this, guardedWindow](QWindow::Visibility visibility) {
        QVariantMap details = guardedWindow ? windowDetails(guardedWindow) : QVariantMap{};
        details.insert(QStringLiteral("visibilityEvent"), static_cast<int>(visibility));
        recordDiagnostic(QStringLiteral("wayland-window-visibility"), details);
    });
    connect(window, &QObject::destroyed, this, [this, window, windowId, role] {
        const quint64 surfaceId = m_windowSurfaceIds.value(window);
        recordDiagnostic(QStringLiteral("wayland-window-destroyed"), {
            {QStringLiteral("windowId"), windowId},
            {QStringLiteral("windowRole"), m_windowRoles.value(window, role)},
            {QStringLiteral("surfaceId"), surfaceId},
        });
        for (auto it = m_surfaceIds.begin(); it != m_surfaceIds.end();) {
            if (it.value() == surfaceId) {
                it = m_surfaceIds.erase(it);
            } else {
                ++it;
            }
        }
        m_watchedWindows.remove(window);
        m_windowIds.remove(window);
        m_lastWindowMotionDiagnosticNs.remove(window);
        m_windowRoles.remove(window);
        m_windowSurfaceIds.remove(window);
    });
    QVariantMap details = windowDetails(window);
    details.insert(QStringLiteral("surface"), surfaceDetails(surfaceForWindow(window)));
    recordDiagnostic(QStringLiteral("wayland-window-watched"), details);
}

bool PointerFocusTracker::eventFilter(QObject *watched, QEvent *event)
{
    auto *window = qobject_cast<QWindow *>(watched);
    if (window && event->type() == QEvent::PlatformSurface
        && (window == m_window || m_surfaceLifecycleWindows.contains(window))) {
        handleSurfaceLifecycleEvent(window, static_cast<QPlatformSurfaceEvent *>(event));
    }
    if (m_diagnosticEnabled && window) {
        const QString eventName = qtPointerEventName(event->type());
        if (!eventName.isEmpty()) {
            bool shouldRecord = true;
            if (event->type() == QEvent::MouseMove) {
                timespec now{};
                clock_gettime(CLOCK_MONOTONIC, &now);
                const qint64 nowNs = static_cast<qint64>(now.tv_sec) * 1000000000LL + now.tv_nsec;
                const qint64 lastNs = m_lastWindowMotionDiagnosticNs.value(window, 0);
                shouldRecord = lastNs == 0 || nowNs - lastNs >= s_qtWindowMotionSampleIntervalNs;
                if (shouldRecord) {
                    m_lastWindowMotionDiagnosticNs.insert(window, nowNs);
                }
            }

            if (shouldRecord && m_qtWindowInputEventCount < s_maxQtWindowInputEvents) {
                QVariantMap details{
                    {QStringLiteral("qtEventBoundary"), QStringLiteral("QWindow eventFilter before QWindow::event")},
                    {QStringLiteral("qtEventType"), eventName},
                    {QStringLiteral("qtEventTypeCode"), static_cast<int>(event->type())},
                    {QStringLiteral("qtEventSpontaneous"), event->spontaneous()},
                    {QStringLiteral("windowId"), m_windowIds.value(window)},
                    {QStringLiteral("windowRole"), m_windowRoles.value(window, QStringLiteral("other"))},
                    {QStringLiteral("surfaceId"), m_windowSurfaceIds.value(window)},
                    {QStringLiteral("quickWindow"), window->inherits("QQuickWindow")},
                    {QStringLiteral("pointerFocusMatchesWindow"), m_focusedSurfaceId != 0
                         && m_windowSurfaceIds.value(window) == m_focusedSurfaceId},
                    {QStringLiteral("coordinateSpace"), QStringLiteral("QWindow logical coordinates")},
                };

                if (event->type() == QEvent::Enter) {
                    const auto *pointerEvent = static_cast<const QEnterEvent *>(event);
                    details.insert(QStringLiteral("localPosition"), pointDetails(pointerEvent->position()));
                    details.insert(QStringLiteral("scenePosition"), pointDetails(pointerEvent->scenePosition()));
                    details.insert(QStringLiteral("globalPosition"), pointDetails(pointerEvent->globalPosition()));
                    details.insert(QStringLiteral("qtEventTimestamp"), pointerEvent->timestamp());
                } else if (event->type() == QEvent::MouseMove
                           || event->type() == QEvent::MouseButtonPress
                           || event->type() == QEvent::MouseButtonRelease) {
                    const auto *pointerEvent = static_cast<const QMouseEvent *>(event);
                    details.insert(QStringLiteral("localPosition"), pointDetails(pointerEvent->position()));
                    details.insert(QStringLiteral("scenePosition"), pointDetails(pointerEvent->scenePosition()));
                    details.insert(QStringLiteral("globalPosition"), pointDetails(pointerEvent->globalPosition()));
                    details.insert(QStringLiteral("qtEventTimestamp"), pointerEvent->timestamp());
                    details.insert(QStringLiteral("mouseEventSource"), static_cast<int>(pointerEvent->source()));
                    details.insert(QStringLiteral("button"), static_cast<int>(pointerEvent->button()));
                    details.insert(QStringLiteral("buttons"), static_cast<int>(pointerEvent->buttons()));
                } else if (event->type() == QEvent::HoverEnter
                           || event->type() == QEvent::HoverMove
                           || event->type() == QEvent::HoverLeave) {
                    const auto *pointerEvent = static_cast<const QHoverEvent *>(event);
                    details.insert(QStringLiteral("localPosition"), pointDetails(pointerEvent->position()));
                    details.insert(QStringLiteral("globalPosition"), pointDetails(pointerEvent->globalPosition()));
                    details.insert(QStringLiteral("oldLocalPosition"), pointDetails(pointerEvent->oldPosF()));
                    details.insert(QStringLiteral("qtEventTimestamp"), pointerEvent->timestamp());
                }

                ++m_qtWindowInputEventCount;
                recordDiagnostic(QStringLiteral("qt-window-input-event"), details);
            } else if (shouldRecord && !m_qtWindowInputEventLimitReported) {
                m_qtWindowInputEventLimitReported = true;
                recordDiagnostic(QStringLiteral("qt-window-input-events-truncated"), {
                    {QStringLiteral("maximumEvents"), s_maxQtWindowInputEvents},
                    {QStringLiteral("boundary"), QStringLiteral("QWindow eventFilter")},
                });
            }
        }
    }

    if (m_diagnosticEnabled && window && event->type() == QEvent::PlatformSurface) {
        auto *surfaceEvent = static_cast<QPlatformSurfaceEvent *>(event);
        wl_surface *surface = surfaceForWindow(window);
        QVariantMap details = windowDetails(window);
        const quint64 id = surface ? idForSurface(surface) : m_windowSurfaceIds.value(window);
        details.insert(QStringLiteral("surfaceId"), id);
        details.insert(QStringLiteral("surfaceEventType"), static_cast<int>(surfaceEvent->surfaceEventType()));
        if (surfaceEvent->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated) {
            if (surface) {
                m_windowSurfaceIds.insert(window, id);
            }
            details.insert(QStringLiteral("focusedSurfaceBefore"), focusedSurfaceDetails());
            recordDiagnostic(QStringLiteral("wayland-window-surface-created"), details);
        } else if (surfaceEvent->surfaceEventType() == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed) {
            details.insert(QStringLiteral("focusedSurfaceBefore"), focusedSurfaceDetails());
            recordDiagnostic(QStringLiteral("wayland-window-surface-destroying"), details);
            if (id != 0) {
                for (auto it = m_surfaceIds.begin(); it != m_surfaceIds.end();) {
                    if (it.value() == id) {
                        it = m_surfaceIds.erase(it);
                    } else {
                        ++it;
                    }
                }
            }
        }
    }
    return QObject::eventFilter(watched, event);
}

void PointerFocusTracker::setFocusedSurface(wl_surface *surface)
{
    if (surface == m_focusedSurface) {
        return;
    }
    m_focusedSurface = surface;
    m_focusedSurfaceId = surface ? idForSurface(surface) : 0;
    Q_EMIT pointerFocusChanged();
    // An enter on another surface of this client (e.g. the preview popup)
    // also leaves the window, so compare the derived state, not the surface.
    const bool inside = isPointerInside();
    if (inside != m_lastInside) {
        m_lastInside = inside;
        Q_EMIT pointerInsideChanged();
    }
}

void PointerFocusTracker::handleGlobal(void *data, wl_registry *, uint32_t name, const char *interface, uint32_t version)
{
    if (std::string_view(interface) == wl_seat_interface.name) {
        static_cast<PointerFocusTracker *>(data)->bindSeat(name, version);
    }
}

void PointerFocusTracker::handleGlobalRemove(void *data, wl_registry *, uint32_t name)
{
    auto *self = static_cast<PointerFocusTracker *>(data);
    if (self->m_seat && name == self->m_seatName) {
        self->releaseSeat();
        self->setFocusedSurface(nullptr);
        self->recordDiagnostic(QStringLiteral("wayland-pointer-focus-cleared"), {
            {QStringLiteral("reason"), QStringLiteral("seat-global-removed")},
            {QStringLiteral("focusedSurfaceAfter"), self->focusedSurfaceDetails()},
        });
    }
}

void PointerFocusTracker::handleCapabilities(void *data, wl_seat *, uint32_t capabilities)
{
    static_cast<PointerFocusTracker *>(data)->setCapabilities(capabilities);
}

void PointerFocusTracker::handleEnter(void *data, wl_pointer *, uint32_t serial, wl_surface *surface, int32_t x, int32_t y)
{
    auto *self = static_cast<PointerFocusTracker *>(data);
    if (QWindow *window = self->windowForSurface(surface)) {
        self->watchSurfaceWindow(window);
        self->m_surfaceWindows.insert(surface, window);
    }
    const quint64 enterSurfaceId = self->idForSurface(surface);
    const bool addressMatchesFocus = surface == self->m_focusedSurface;
    const bool stableIdMatchesFocus = enterSurfaceId == self->m_focusedSurfaceId;
    if (addressMatchesFocus && !stableIdMatchesFocus) {
        self->recordDiagnostic(QStringLiteral("wayland-surface-address-reused"), {
            {QStringLiteral("previousSurfaceId"), self->m_focusedSurfaceId},
            {QStringLiteral("newSurfaceId"), enterSurfaceId},
            {QStringLiteral("surfaceClass"), self->surfaceDetails(surface).value(QStringLiteral("surfaceClass"))},
            {QStringLiteral("behaviorNote"), QStringLiteral("Existing pointer handler compares raw surface addresses")},
        });
    }
    self->recordDiagnostic(QStringLiteral("wayland-pointer-enter"), {
        {QStringLiteral("waylandSerial"), serial},
        {QStringLiteral("pointerObjectSessionId"), QStringLiteral("pointer-%1").arg(self->m_pointerGeneration)},
        {QStringLiteral("enterSurface"), self->surfaceDetails(surface)},
        {QStringLiteral("focusedSurfaceBefore"), self->focusedSurfaceDetails()},
        {QStringLiteral("focusedSurfaceAfter"), self->surfaceDetails(surface)},
        {QStringLiteral("focusChangeReason"), QStringLiteral("wl_pointer.enter")},
        {QStringLiteral("surfaceAddressMatchesFocusBefore"), addressMatchesFocus},
        {QStringLiteral("stableSurfaceIdMatchesFocusBefore"), stableIdMatchesFocus},
        {QStringLiteral("surfaceLocalFixed"), QVariantMap{
            {QStringLiteral("x"), x},
            {QStringLiteral("y"), y},
        }},
        {QStringLiteral("surfaceLocal"), QVariantMap{
            {QStringLiteral("x"), wl_fixed_to_double(x)},
            {QStringLiteral("y"), wl_fixed_to_double(y)},
        }},
    }, true);
    self->setFocusedSurface(surface);
    self->publishSurfaceSample(surface,
                               QPointF(wl_fixed_to_double(x), wl_fixed_to_double(y)),
                               true);
    self->recordDiagnostic(QStringLiteral("wayland-pointer-enter-applied"), {
        {QStringLiteral("waylandPointerEventId"), self->m_pointerEventSequence},
        {QStringLiteral("waylandSerial"), serial},
        {QStringLiteral("focusedSurfaceAfter"), self->focusedSurfaceDetails()},
        {QStringLiteral("focusWindowId"), self->m_windowIds.value(self->pointerFocusWindow())},
        {QStringLiteral("pointerInsideDock"), self->isPointerInside()},
    });
}

void PointerFocusTracker::handleLeave(void *data, wl_pointer *, uint32_t serial, wl_surface *surface)
{
    auto *self = static_cast<PointerFocusTracker *>(data);
    const quint64 leaveSurfaceId = self->idForSurface(surface);
    const quint64 focusedSurfaceIdBefore = self->m_focusedSurfaceId;
    self->recordDiagnostic(QStringLiteral("wayland-pointer-leave"), {
        {QStringLiteral("waylandSerial"), serial},
        {QStringLiteral("pointerObjectSessionId"), QStringLiteral("pointer-%1").arg(self->m_pointerGeneration)},
        {QStringLiteral("leaveSurface"), self->surfaceDetails(surface)},
        {QStringLiteral("focusedSurfaceBefore"), self->focusedSurfaceDetails()},
        {QStringLiteral("focusedSurfaceAfter"), QVariantMap{}},
        {QStringLiteral("focusChangeReason"), QStringLiteral("wl_pointer.leave")},
        {QStringLiteral("leaveMatchesCurrentFocus"), leaveSurfaceId == focusedSurfaceIdBefore},
        {QStringLiteral("leaveAddressMatchesCurrentFocus"), surface == self->m_focusedSurface},
        {QStringLiteral("leaveSurfaceId"), leaveSurfaceId},
        {QStringLiteral("focusedSurfaceIdBefore"), focusedSurfaceIdBefore},
    }, true);
    // A delayed leave from an older surface must not invalidate a newer
    // enter/sample. Normal Wayland leave→enter order still clears first.
    if (leaveSurfaceId == focusedSurfaceIdBefore && surface == self->m_focusedSurface) {
        self->setFocusedSurface(nullptr);
        self->invalidatePointerSample(surface);
    }
    self->recordDiagnostic(QStringLiteral("wayland-pointer-leave-applied"), {
        {QStringLiteral("waylandPointerEventId"), self->m_pointerEventSequence},
        {QStringLiteral("waylandSerial"), serial},
        {QStringLiteral("leaveSurfaceId"), self->idForSurface(surface)},
        {QStringLiteral("focusedSurfaceAfter"), self->focusedSurfaceDetails()},
        {QStringLiteral("focusWindowId"), self->m_windowIds.value(self->pointerFocusWindow())},
        {QStringLiteral("pointerInsideDock"), self->isPointerInside()},
    });
}

void PointerFocusTracker::handleMotion(void *data, wl_pointer *, uint32_t serial, int32_t x, int32_t y)
{
    auto *self = static_cast<PointerFocusTracker *>(data);
    if (self->m_focusedSurface) {
        self->publishSurfaceSample(self->m_focusedSurface,
                                   QPointF(wl_fixed_to_double(x), wl_fixed_to_double(y)),
                                   true);
    }
    if (!self->m_diagnosticEnabled) {
        return;
    }
    timespec now{};
    clock_gettime(CLOCK_MONOTONIC, &now);
    const qint64 monotonicReferenceNs = static_cast<qint64>(now.tv_sec) * 1000000000LL + now.tv_nsec;
    self->m_lastPointerMotion = {
        {QStringLiteral("waylandSerial"), serial},
        {QStringLiteral("pointerObjectSessionId"), QStringLiteral("pointer-%1").arg(self->m_pointerGeneration)},
        {QStringLiteral("focusedSurfaceId"), self->m_focusedSurfaceId},
        {QStringLiteral("focusedSurfaceObjectId"), self->m_focusedSurface
             ? QVariant(wl_proxy_get_id(reinterpret_cast<wl_proxy *>(self->m_focusedSurface))) : QVariant{}},
        {QStringLiteral("surfaceLocalFixed"), QVariantMap{{QStringLiteral("x"), x}, {QStringLiteral("y"), y}}},
        {QStringLiteral("surfaceLocal"), QVariantMap{
             {QStringLiteral("x"), wl_fixed_to_double(x)},
             {QStringLiteral("y"), wl_fixed_to_double(y)},
         }},
        {QStringLiteral("monotonicReferenceNs"), monotonicReferenceNs},
    };
}

} // namespace kdockw
