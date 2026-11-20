// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "dockview.h"

#include "config/screensettings.h"
#include "dockvisibilitycontroller.h"
#include "kdockw.h"
#include "models/taskiconprovider.h"
#include "models/icondiag.h"
#include "platform/pointerfocustracker.h"
#include "utils/surfacegeometry.h"
#include "utils/zoomlayoutvariant.h"

#include <QDBusConnection>
#include <QDir>
#include <QGuiApplication>
#include <QLoggingCategory>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPalette>
#include <QPainterPath>
#include <QRegularExpression>
#include <QQuickStyle>
#include <QRegion>
#include <LayerShellQt/Window>

#include <taskmanager/tasksmodel.h>
#include <KIconLoader>
#include <KLocalizedQmlContext>

#include <QQmlEngine>
#include <QMap>
#include <QQuickItem>
#include <QScreen>
#include <QtQml>
#ifdef KDOCKW_DIAGNOSTIC_BUILD
#include <QElapsedTimer>
#include <QTimer>
#endif

#include <utility>
#include <functional>
#include <time.h>

Q_LOGGING_CATEGORY(lcDockView, "kdockw.shell.dockview")

namespace kdockw
{

namespace
{

QVariantMap inputRegionDiagnostic(const QRegion &region)
{
    QVariantList rectangles;
    constexpr int maxRectangles = 256;
    int rectangleIndex = 0;
    for (const QRect &rect : region) {
        if (rectangleIndex++ >= maxRectangles) {
            break;
        }
        rectangles.append(QVariantMap{
            {QStringLiteral("x"), rect.x()},
            {QStringLiteral("y"), rect.y()},
            {QStringLiteral("width"), rect.width()},
            {QStringLiteral("height"), rect.height()},
        });
    }
    const QRect bounds = region.boundingRect();
    return {
        {QStringLiteral("coordinateSpace"), QStringLiteral("dock-surface-local-logical")},
        {QStringLiteral("empty"), region.isEmpty()},
        {QStringLiteral("rectCount"), region.rectCount()},
        {QStringLiteral("rectanglesTruncated"), region.rectCount() > rectangles.size()},
        {QStringLiteral("rectangles"), rectangles},
        {QStringLiteral("boundingRect"), QVariantMap{
            {QStringLiteral("x"), bounds.x()},
            {QStringLiteral("y"), bounds.y()},
            {QStringLiteral("width"), bounds.width()},
            {QStringLiteral("height"), bounds.height()},
        }},
    };
}

qint64 monotonicReferenceNowNs()
{
    timespec now{};
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        return -1;
    }
    return static_cast<qint64>(now.tv_sec) * 1000000000LL + now.tv_nsec;
}

} // namespace

DockView::DockView(std::unique_ptr<DockPlatform> platform, KDockWSettings *settings, QWindow *parent)
    : QQuickView(parent)
    , m_platform(std::move(platform))
    , m_settings(settings)
{
    setColor(Qt::transparent);
    setResizeMode(QQuickView::SizeRootObjectToView);
    m_monotonicClock.start();
}

DockView::~DockView()
{
    if (m_pointerFocusTracker) {
        m_pointerFocusTracker->setDiagnosticEnabled(false);
    }
}

void DockView::initialize(TaskManager::TasksModel *tasksModel,
                          TaskManager::VirtualDesktopInfo *virtualDesktopInfo,
                          TaskManager::ActivityInfo *activityInfo,
                          DockPlatform::Edge edge,
                          DockPlatform::VisibilityMode visibilityMode)
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    m_geometryTraceEnabled = qEnvironmentVariable("KDOCKW_GEOMETRY_TRACE") == QLatin1String("1");
    m_launcherDiagnosticPage = qEnvironmentVariable("KDOCKW_DIAGNOSTIC_LAUNCHER_PAGE");
    if (!m_launcherDiagnosticPage.isEmpty()) {
        const QVariantMap state{
            {QStringLiteral("binary"), QCoreApplication::applicationFilePath()},
            {QStringLiteral("controlsStyle"), QQuickStyle::name()},
            {QStringLiteral("QT_QUICK_CONTROLS_STYLE"), qEnvironmentVariable("QT_QUICK_CONTROLS_STYLE")},
            {QStringLiteral("QT_QUICK_CONTROLS_FALLBACK_STYLE"), qEnvironmentVariable("QT_QUICK_CONTROLS_FALLBACK_STYLE")},
            {QStringLiteral("QT_QUICK_CONTROLS_CONF"), qEnvironmentVariable("QT_QUICK_CONTROLS_CONF")},
            {QStringLiteral("QT_QPA_PLATFORMTHEME"), qEnvironmentVariable("QT_QPA_PLATFORMTHEME")},
            {QStringLiteral("QT_STYLE_OVERRIDE"), qEnvironmentVariable("QT_STYLE_OVERRIDE")},
            {QStringLiteral("XDG_CONFIG_HOME"), qEnvironmentVariable("XDG_CONFIG_HOME")},
            {QStringLiteral("XDG_DATA_HOME"), qEnvironmentVariable("XDG_DATA_HOME")},
            {QStringLiteral("XDG_CACHE_HOME"), qEnvironmentVariable("XDG_CACHE_HOME")},
            {QStringLiteral("XDG_DATA_DIRS"), qEnvironmentVariable("XDG_DATA_DIRS")},
            {QStringLiteral("paletteWindow"), QGuiApplication::palette().color(QPalette::Window).name(QColor::HexArgb)},
            {QStringLiteral("paletteText"), QGuiApplication::palette().color(QPalette::WindowText).name(QColor::HexArgb)},
            {QStringLiteral("qmlImports"), engine()->importPathList()},
        };
        qCInfo(lcDockView).noquote() << "[KDOCKW_LAUNCHER_UI_ENV]"
                                     << QJsonDocument(QJsonObject::fromVariantMap(state)).toJson(QJsonDocument::Compact);
    }
#endif
    // Capture the screen MultiDockManager assigned before setupWindow():
    // LayerShellQt < 6.6 creates the platform window in Window::get(), and
    // QtWayland then re-derives screen() from the still-empty geometry.
    QScreen *targetScreen = screen();
    m_dockScreen = targetScreen;

    // Configure the platform layer (LayerShellQt on Wayland)
    m_platform->setupWindow(this);
    m_platform->setEdge(edge);
    // Pin the layer surface to this dock's screen before show():
    // QWindow::setScreen alone does not bind the layer surface on QtWayland,
    // so the platform pins it (LayerShellQt::Window screen, or the Qt screen
    // and position on LayerShellQt < 6.6). Layer-shell surfaces bind their
    // wl_output when the surface is created on show().
    m_platform->setScreen(targetScreen);

    // Store edge for QML access (must be set before QML loading)
    m_edge = edge;

    // Create visibility controller (manages show/hide logic for all modes)
    m_visibilityController = new DockVisibilityController(m_platform.get(),
                                                          tasksModel,
                                                          virtualDesktopInfo,
                                                          activityInfo,
                                                          this,
                                                          dockScreen(),
                                                          this);
    m_visibilityController->setMode(visibilityMode);

    // Created once, before show(), so it already holds the compositor's
    // focus when a context menu's popup grab fakes a leave.
    m_pointerFocusTracker = std::make_unique<PointerFocusTracker>(this);
    connect(m_pointerFocusTracker.get(), &PointerFocusTracker::pointerInsideChanged, this, &DockView::pointerInsideChanged);
    connect(m_pointerFocusTracker.get(), &PointerFocusTracker::pointerFocusChanged,
            this, &DockView::pointerFocusWindowChanged);
    connect(m_pointerFocusTracker.get(), &PointerFocusTracker::diagnosticEvent, this,
            [this](const QString &event, const QVariantMap &details) {
                m_lastWaylandPointerEventId = details.value(QStringLiteral("waylandPointerEventId"),
                                                             m_lastWaylandPointerEventId).toULongLong();
                QVariantMap observed = details;
                observed.insert(QStringLiteral("event"), event);
                observed.insert(QStringLiteral("monotonicMs"), m_monotonicClock.elapsed());
                observed.insert(QStringLiteral("monotonicNs"), m_monotonicClock.nsecsElapsed());
                observed.insert(QStringLiteral("monotonicReferenceNs"), monotonicReferenceNowNs());
                m_lastWaylandEvent = observed;
                if (details.contains(QStringLiteral("waylandPointerEventId"))) {
                    m_lastWaylandPointerEvent = observed;
                }
                traceMediaHover(event, details);
            });
    m_mediaPopupTraceEnabled = qEnvironmentVariable("KDOCKW_MEDIA_POPUP_TRACE") == QLatin1String("1");
    m_mediaHoverDebugEnabled = qEnvironmentVariable("KDOCKW_MEDIA_HOVER_DEBUG") == QLatin1String("1");
    if (m_mediaHoverDebugEnabled) {
        m_mediaHoverBuildId = qEnvironmentVariable("KDOCKW_MEDIA_HOVER_BUILD_ID");
        m_mediaHoverTraceFile.setFileName(qEnvironmentVariable("KDOCKW_MEDIA_HOVER_TRACE_OUT"));
        if (m_mediaHoverTraceFile.fileName().isEmpty()
            || !m_mediaHoverTraceFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
            qCWarning(lcDockView) << "Media hover diagnostic log could not be opened:" << m_mediaHoverTraceFile.fileName();
            m_mediaHoverDebugEnabled = false;
        } else {
            traceMediaHover(QStringLiteral("session-start"), {
                {QStringLiteral("profile"), qEnvironmentVariable("KDOCKW_MEDIA_HOVER_PROFILE")},
                {QStringLiteral("pid"), QCoreApplication::applicationPid()},
            });

            const QString runtimeDirectory = qEnvironmentVariable("XDG_RUNTIME_DIR");
            if (runtimeDirectory.isEmpty()) {
                traceMediaHover(QStringLiteral("marker-ipc-unavailable"), {
                    {QStringLiteral("reason"), QStringLiteral("XDG_RUNTIME_DIR is empty")},
                });
            } else {
                const QString socketPath = QDir(runtimeDirectory).filePath(
                    QStringLiteral("kdockw-media-hover-%1.sock").arg(QCoreApplication::applicationPid()));
                m_mediaHoverMarkerServer = std::make_unique<QLocalServer>();
                m_mediaHoverMarkerServer->setSocketOptions(QLocalServer::UserAccessOption);
                if (m_mediaHoverMarkerServer->listen(socketPath)) {
                    connect(m_mediaHoverMarkerServer.get(), &QLocalServer::newConnection,
                            this, &DockView::handleMediaHoverMarkerConnection);
                    traceMediaHover(QStringLiteral("marker-ipc-ready"), {
                        {QStringLiteral("socket"), socketPath},
                    });
                } else {
                    traceMediaHover(QStringLiteral("marker-ipc-unavailable"), {
                        {QStringLiteral("reason"), m_mediaHoverMarkerServer->errorString()},
                    });
                    qCWarning(lcDockView).noquote()
                        << "Media hover marker IPC could not listen:" << socketPath
                        << m_mediaHoverMarkerServer->errorString();
                    m_mediaHoverMarkerServer.reset();
                }
            }
        }
    }
    if (m_mediaHoverDebugEnabled && m_pointerFocusTracker) {
        m_pointerFocusTracker->setDiagnosticEnabled(true);
        m_pointerFocusTracker->registerDiagnosticWindow(this, QStringLiteral("dock"));
    }
    if (m_mediaHoverDebugEnabled && m_visibilityController) {
        m_visibilityController->setInputRegionDiagnosticsEnabled(true);
        connect(m_visibilityController, &DockVisibilityController::inputRegionApplied, this,
                [this](const QRegion &region, const QString &reason, const QVariantMap &state) {
                    m_lastDockInputRegion = region;
                    m_lastDockInputRegionReason = reason;
                    m_lastDockInputRegionState = state;
                    m_hasLastDockInputRegion = true;
                    QVariantMap details = inputRegionDiagnostic(region);
                    details.insert(QStringLiteral("surfaceRole"), QStringLiteral("dock"));
                    details.insert(QStringLiteral("reason"), reason);
                    details.insert(QStringLiteral("controllerState"), state);
                    details.insert(QStringLiteral("windowGeometry"), QVariantMap{
                        {QStringLiteral("x"), geometry().x()},
                        {QStringLiteral("y"), geometry().y()},
                        {QStringLiteral("width"), width()},
                        {QStringLiteral("height"), height()},
                    });
                    traceMediaHover(QStringLiteral("surface-input-region"), details);
                });
    }
    m_launcherTimingEnabled = qEnvironmentVariable("KDOCKW_LAUNCHER_TIMING") == QLatin1String("1");

    // Register the icon image provider for QML
    m_iconDiagnostics = new IconDiagnostics(this);
    m_iconDiagnostics->attachWindow(this);
    engine()->rootContext()->setContextProperty(QStringLiteral("IconDiagnostics"), m_iconDiagnostics);
    m_iconProvider = new TaskIconProvider(m_settings->iconNormalization(), m_iconDiagnostics);
    m_iconProvider->setIconScale(m_settings->iconScale());
    engine()->addImageProvider(QStringLiteral("icon"), m_iconProvider);

    // Invalidate icon normalization cache when icon theme changes
    connect(KIconLoader::global(), &KIconLoader::iconChanged, this, [this]() {
        m_iconProvider->clearCache();
        bumpIconCacheVersion();
    });
    connect(m_iconDiagnostics, &IconDiagnostics::iconDprChanged, this, &DockView::bumpIconCacheVersion);

    // Task icons bind directly to model.decoration and DockModel::iconName()
    // per row. Do not invalidate the shared icon URL cache for every task
    // decoration update: TaskManager emits these continuously, and changing
    // this global version reloads every dock icon on each notification.

    // Enable i18n() in QML (required for Accessible.name/description strings)
    KLocalization::setupLocalizedContext(engine());

    // Per-engine context property (supports multiple DockView instances for M8 multi-monitor)
    engine()->rootContext()->setContextProperty(QStringLiteral("DockVisibility"), m_visibilityController);

    // Apply background effects (blur, contrast)
    applyBackgroundStyle();

    // Load the QML UI
    setSource(QUrl(QStringLiteral("qrc:/qml/main.qml")));

    if (status() == QQuickView::Error) {
        const auto errs = errors();
        for (const auto &err : errs) {
            qCCritical(lcDockView) << "QML load error:" << err.toString();
        }
        return;
    }

    // Set initial window size
    updateSize();

    // React to screen changes (e.g. DPMS off/on replaces QScreen objects)
    connect(this, &QWindow::screenChanged, this, &DockView::handleScreenChanged);
    if (m_dockScreen) {
        m_screenGeometryConnection = connect(m_dockScreen, &QScreen::geometryChanged, this, &DockView::handleScreenGeometryChanged);
        if (m_geometryTraceEnabled) {
            connect(m_dockScreen, &QScreen::availableGeometryChanged, this, [this] {
                traceLayerGeometry(QStringLiteral("available-geometry-changed"));
            });
        }
    }
    if (m_geometryTraceEnabled) {
        if (LayerShellQt::Window *layerWindow = LayerShellQt::Window::get(this)) {
            connect(layerWindow, &LayerShellQt::Window::exclusionZoneChanged, this, [this] {
                traceLayerGeometry(QStringLiteral("exclusive-zone-changed"));
            });
        }
        connect(this, &QQuickWindow::frameSwapped, this, [this] {
            if (m_geometryTraceAfterFrame.isEmpty()) {
                return;
            }
            const QString phase = m_geometryTraceAfterFrame;
            m_geometryTraceAfterFrame.clear();
            traceLayerGeometry(QStringLiteral("frame-swapped-after-%1").arg(phase));
        });
        connect(this, &QWindow::visibleChanged, this, [this](bool visible) {
            traceLayerGeometry(visible ? QStringLiteral("visible") : QStringLiteral("hidden"));
        });
    }

    // React to screen lock/unlock (QScreen object stays the same, so screenChanged doesn't fire)
    QDBusConnection::sessionBus().connect(QStringLiteral("org.freedesktop.ScreenSaver"),
                                          QStringLiteral("/ScreenSaver"),
                                          QStringLiteral("org.freedesktop.ScreenSaver"),
                                          QStringLiteral("ActiveChanged"),
                                          this,
                                          SLOT(handleScreenLockChanged(bool)));

    show();
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    m_performanceDiagnosticsEnabled = qEnvironmentVariable("KDOCKW_PERF_DIAGNOSTICS") == QLatin1String("1");
    if (m_performanceDiagnosticsEnabled) {
        qCInfo(lcDockView).noquote()
            << "[KDOCKW_PERF_START]"
            << "binary=" << QCoreApplication::applicationFilePath()
            << "screen=" << (m_dockScreen ? m_dockScreen->name() : QStringLiteral("unknown"))
            << "screenGeometry=" << (m_dockScreen ? m_dockScreen->geometry() : QRect())
            << "surfaceGeometry=" << geometry()
            << "edge=" << static_cast<int>(m_edge)
            << "renderer=" << static_cast<int>(rendererInterface()->graphicsApi())
            << "qmlImportPaths=" << engine()->importPathList()
            << "qmlPluginPaths=" << engine()->pluginPathList();
        m_performanceClock.start();
        m_eventLoopClock.start();
        m_frameClock.start();
        m_eventLoopProbeTimer = new QTimer(this);
        m_eventLoopProbeTimer->setTimerType(Qt::PreciseTimer);
        m_eventLoopProbeTimer->setInterval(50);
        connect(m_eventLoopProbeTimer, &QTimer::timeout, this, [this] {
            const qint64 elapsed = m_eventLoopClock.restart();
            ++m_eventLoopSamples;
            m_eventLoopOver66Ms += elapsed > 66;
            m_eventLoopOver100Ms += elapsed > 100;
            m_eventLoopOver150Ms += elapsed > 150;
            m_eventLoopMaxLatenessMs = std::max(m_eventLoopMaxLatenessMs, std::max<qint64>(0, elapsed - 50));
        });
        m_eventLoopProbeTimer->start();
        connect(this, &QQuickWindow::frameSwapped, this, [this] {
            const qint64 elapsed = m_frameClock.restart();
            ++m_frameSamples;
            m_frameOver25Ms += elapsed > 25;
            m_frameMaxIntervalMs = std::max(m_frameMaxIntervalMs, elapsed);
        });
        m_performanceReportTimer = new QTimer(this);
        m_performanceReportTimer->setInterval(5000);
        connect(m_performanceReportTimer, &QTimer::timeout, this, [this] {
            const qint64 elapsed = m_performanceClock.restart();
            if (m_iconProvider) {
                m_iconProvider->reportPerformanceInterval();
            }
            qCInfo(lcDockView).noquote()
                << "[KDOCKW_PERF_EVENT_LOOP]"
                << "intervalMs=" << elapsed
                << "probeSamples=" << m_eventLoopSamples
                << "probeOver66ms=" << m_eventLoopOver66Ms
                << "probeOver100ms=" << m_eventLoopOver100Ms
                << "probeOver150ms=" << m_eventLoopOver150Ms
                << "maxLatenessMs=" << m_eventLoopMaxLatenessMs
                << "frames=" << m_frameSamples
                << "framesOver25ms=" << m_frameOver25Ms
                << "maxFrameIntervalMs=" << m_frameMaxIntervalMs
                << "visible=" << isVisible();
            m_eventLoopSamples = 0;
            m_eventLoopOver66Ms = 0;
            m_eventLoopOver100Ms = 0;
            m_eventLoopOver150Ms = 0;
            m_eventLoopMaxLatenessMs = 0;
            m_frameSamples = 0;
            m_frameOver25Ms = 0;
            m_frameMaxIntervalMs = 0;
        });
        m_performanceReportTimer->start();

        if (qEnvironmentVariable("KDOCKW_OBJECT_CENSUS") == QLatin1String("1")) {
            auto *censusTimer = new QTimer(this);
            censusTimer->setInterval(10000);
            connect(censusTimer, &QTimer::timeout, this, [this] {
                QMap<QString, int> types;
                int objectCount = 0;
                int quickItemCount = 0;
                std::function<void(const QObject *)> visit = [&](const QObject *object) {
                    if (!object) {
                        return;
                    }
                    ++objectCount;
                    ++types[QString::fromLatin1(object->metaObject()->className())];
                    quickItemCount += qobject_cast<const QQuickItem *>(object) != nullptr;
                    for (const QObject *child : object->children()) {
                        visit(child);
                    }
                };
                visit(rootObject());
                QStringList typeCounts;
                for (auto it = types.cbegin(); it != types.cend(); ++it) {
                    typeCounts.append(QStringLiteral("%1:%2").arg(it.key()).arg(it.value()));
                }
                qCInfo(lcDockView).noquote() << "[KDOCKW_OBJECT_CENSUS]"
                                              << "objects=" << objectCount
                                              << "quickItems=" << quickItemCount
                                              << "types=" << typeCounts.join(QLatin1Char(','));
            });
            censusTimer->start();
        }
    }
#endif
    if (m_geometryTraceEnabled) {
        traceLayerGeometry(QStringLiteral("initial-show"));
        m_geometryTraceAfterFrame = QStringLiteral("initial-show");
    }
    m_iconDiagnostics->logEnvironment(QStringLiteral("dock-shown"));
}

QColor DockView::backgroundColor() const
{
    auto type = static_cast<BackgroundStyleType>(m_settings->backgroundStyle());
    qreal opacity = m_settings->backgroundOpacity();

    return computeBackgroundColor(type, m_settings->tintColor(), opacity, m_settings->useAccentColor(), m_settings->useSystemColor());
}

bool DockView::isPointerInside() const
{
    return m_pointerFocusTracker && m_pointerFocusTracker->isPointerInside();
}

bool DockView::pointerFocusKnown() const
{
    return m_pointerFocusTracker && m_pointerFocusTracker->hasPointerFocus();
}

QWindow *DockView::pointerFocusWindow() const
{
    return m_pointerFocusTracker ? m_pointerFocusTracker->pointerFocusWindow() : nullptr;
}

bool DockView::mediaPopupTraceEnabled() const
{
    return m_mediaPopupTraceEnabled;
}

bool DockView::mediaHoverDebugEnabled() const
{
    return m_mediaHoverDebugEnabled;
}

bool DockView::launcherTimingEnabled() const
{
    return m_launcherTimingEnabled;
}

qint64 DockView::monotonicNowMs() const
{
    return m_monotonicClock.elapsed();
}

QVariantMap DockView::captureMediaHoverDiagnosticSnapshot() const
{
    if (!m_mediaHoverDebugEnabled) {
        return {{QStringLiteral("available"), false},
                {QStringLiteral("reason"), QStringLiteral("media-hover-diagnostics-disabled")}};
    }

    QVariant qmlState;
    QObject *root = rootObject();
    if (!root || !QMetaObject::invokeMethod(root,
                                            "mediaHoverDiagnosticSnapshot",
                                            Qt::DirectConnection,
                                            Q_RETURN_ARG(QVariant, qmlState))) {
        return {{QStringLiteral("available"), false},
                {QStringLiteral("reason"), QStringLiteral("qml-snapshot-method-unavailable")}};
    }

    QVariantMap snapshot = qmlState.toMap();
    snapshot.insert(QStringLiteral("available"), true);
    snapshot.insert(QStringLiteral("snapshotSemantics"),
                    QStringLiteral("read-only; no pointer polling, hit testing, or hover state update"));
    snapshot.insert(QStringLiteral("monotonicReferenceNs"), monotonicReferenceNowNs());
    snapshot.insert(QStringLiteral("lastWaylandEvent"), m_lastWaylandEvent);
    snapshot.insert(QStringLiteral("lastWaylandPointerEvent"), m_lastWaylandPointerEvent);
    if (m_pointerFocusTracker) {
        snapshot.insert(QStringLiteral("waylandPointerTracker"), m_pointerFocusTracker->diagnosticSnapshot());
    }
    snapshot.insert(QStringLiteral("dockSurfaceQtMask"), inputRegionDiagnostic(mask()));
    snapshot.insert(QStringLiteral("lastDockInputRegionSent"), m_hasLastDockInputRegion
                        ? QVariant(inputRegionDiagnostic(m_lastDockInputRegion)) : QVariant{});
    snapshot.insert(QStringLiteral("lastDockInputRegionReason"), m_lastDockInputRegionReason);
    snapshot.insert(QStringLiteral("lastDockInputRegionControllerState"), m_lastDockInputRegionState);
    snapshot.insert(QStringLiteral("inputRegionObservationLimit"),
                    QStringLiteral("client-side QWindow mask/request only; KWin's effective region is not exposed here"));
    return snapshot;
}

void DockView::registerDiagnosticSurface(QObject *windowObject, const QString &role)
{
    if (!m_mediaHoverDebugEnabled || !m_pointerFocusTracker || !windowObject) {
        return;
    }
    auto *window = qobject_cast<QWindow *>(windowObject);
    if (window) {
        m_pointerFocusTracker->registerDiagnosticWindow(window, role);
    }
}

void DockView::setDiagnosticInteractionContext(const QString &scenarioId,
                                              const QString &interactionId,
                                              const QString &interactionKind)
{
    if (!m_mediaHoverDebugEnabled) {
        return;
    }
    m_diagnosticScenarioId = scenarioId;
    m_diagnosticInteractionId = interactionId;
    m_diagnosticInteractionKind = interactionKind;
}

void DockView::traceMediaHover(const QString &event, const QVariantMap &details) const
{
    if (!m_mediaHoverDebugEnabled || !m_mediaHoverTraceFile.isOpen()) {
        return;
    }

    QJsonObject record = QJsonObject::fromVariantMap(details);
    if (!record.contains(QStringLiteral("scenarioId"))) {
        record.insert(QStringLiteral("scenarioId"), m_diagnosticScenarioId);
    }
    if (!record.contains(QStringLiteral("interactionId"))) {
        record.insert(QStringLiteral("interactionId"), m_diagnosticInteractionId);
    }
    if (!record.contains(QStringLiteral("interactionKind"))) {
        record.insert(QStringLiteral("interactionKind"), m_diagnosticInteractionKind);
    }
    record.insert(QStringLiteral("event"), event);
    record.insert(QStringLiteral("monotonicMs"), m_monotonicClock.elapsed());
    record.insert(QStringLiteral("monotonicNs"), m_monotonicClock.nsecsElapsed());
    record.insert(QStringLiteral("monotonicReferenceNs"), monotonicReferenceNowNs());
    record.insert(QStringLiteral("traceSequence"), static_cast<qint64>(++m_mediaHoverTraceSequence));
    record.insert(QStringLiteral("lastWaylandPointerEventId"), static_cast<qint64>(m_lastWaylandPointerEventId));
    record.insert(QStringLiteral("buildId"), m_mediaHoverBuildId);
    record.insert(QStringLiteral("version"), QStringLiteral(KDOCKW_VERSION_STRING));
    record.insert(QStringLiteral("executable"), QCoreApplication::applicationFilePath());
    const QByteArray line = QJsonDocument(record).toJson(QJsonDocument::Compact) + '\n';
    if (m_mediaHoverTraceFile.write(line) != line.size() || !m_mediaHoverTraceFile.flush()) {
        qCWarning(lcDockView) << "Media hover diagnostic log write failed:" << m_mediaHoverTraceFile.fileName();
    }
}

void DockView::handleMediaHoverMarkerConnection()
{
    if (!m_mediaHoverMarkerServer) {
        return;
    }

    while (m_mediaHoverMarkerServer->hasPendingConnections()) {
        QLocalSocket *socket = m_mediaHoverMarkerServer->nextPendingConnection();
        if (!socket) {
            continue;
        }
        connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QLocalSocket::readyRead, this, [this, socket] {
            QByteArray request = socket->property("markerRequest").toByteArray();
            request.append(socket->readAll());
            if (request.size() > 4096) {
                socket->write("ERR request too large\n");
                socket->disconnectFromServer();
                return;
            }

            const qsizetype newline = request.indexOf('\n');
            if (newline < 0) {
                socket->setProperty("markerRequest", request);
                return;
            }
            if (newline != request.size() - 1) {
                socket->write("ERR malformed request\n");
                socket->disconnectFromServer();
                return;
            }

            QJsonParseError parseError;
            const QJsonDocument document = QJsonDocument::fromJson(request.first(newline), &parseError);
            if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
                socket->write("ERR invalid JSON request\n");
                socket->disconnectFromServer();
                return;
            }
            const QJsonObject object = document.object();
            const QString command = object.value(QStringLiteral("command")).toString();
            if (command == QLatin1String("snapshot")) {
                const QString requestId = object.value(QStringLiteral("requestId")).toString();
                static const QRegularExpression validRequestId(QStringLiteral("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"));
                if (!validRequestId.match(requestId).hasMatch()) {
                    socket->write("ERR invalid request id\n");
                    socket->disconnectFromServer();
                    return;
                }
                const QVariantMap snapshot = captureMediaHoverDiagnosticSnapshot();
                traceMediaHover(QStringLiteral("owner-diagnostic-snapshot"), {
                    {QStringLiteral("requestId"), requestId},
                    {QStringLiteral("snapshot"), snapshot},
                });
                const QByteArray response = QJsonDocument(QJsonObject{
                    {QStringLiteral("status"), QStringLiteral("ok")},
                    {QStringLiteral("requestId"), requestId},
                    {QStringLiteral("snapshot"), QJsonObject::fromVariantMap(snapshot)},
                }).toJson(QJsonDocument::Compact) + '\n';
                socket->write(response);
                socket->disconnectFromServer();
                return;
            }
            if (!command.isEmpty()) {
                socket->write("ERR unsupported command\n");
                socket->disconnectFromServer();
                return;
            }

            const QString label = object.value(QStringLiteral("label")).toString();
            static const QRegularExpression validLabel(QStringLiteral("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"));
            if (!validLabel.match(label).hasMatch()) {
                socket->write("ERR invalid marker label\n");
                socket->disconnectFromServer();
                return;
            }

            Q_EMIT mediaHoverMarkerReceived(label);
            socket->write("OK\n");
            socket->disconnectFromServer();
        });
    }
}

bool DockView::performanceDiagnosticsEnabled() const
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    return qEnvironmentVariable("KDOCKW_PERF_DIAGNOSTICS") == QLatin1String("1");
#else
    return false;
#endif
}

QString DockView::launcherDiagnosticPage() const
{
    return m_launcherDiagnosticPage;
}

void DockView::traceLauncherUi(const QString &label, const QVariantMap &state) const
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    if (m_launcherTimingEnabled || !m_launcherDiagnosticPage.isEmpty()) {
        QVariantMap details = state;
        details.insert(QStringLiteral("label"), label);
        qCInfo(lcDockView).noquote() << "[KDOCKW_LAUNCHER_UI]"
                                     << QJsonDocument(QJsonObject::fromVariantMap(details)).toJson(QJsonDocument::Compact);
    }
#else
    Q_UNUSED(label);
    Q_UNUSED(state);
#endif
}

int DockView::backgroundStyleType() const
{
    return m_settings->backgroundStyle();
}

int DockView::floatingPadding() const
{
    return m_settings->floating() ? m_settings->floatingMargin() : 0;
}

int DockView::iconCacheVersion() const
{
    return m_iconCacheVersion;
}

int DockView::edge() const
{
    return static_cast<int>(m_edge);
}

bool DockView::isVertical() const
{
    return m_edge == DockPlatform::Edge::Left || m_edge == DockPlatform::Edge::Right;
}

int DockView::tooltipReserve() const
{
    return m_tooltipReserve;
}

QRect DockView::screenGeometry() const
{
    return dockScreen() ? dockScreen()->geometry() : QRect();
}

void DockView::setTooltipReserve(int reserve)
{
    if (m_tooltipReserve == reserve) {
        return;
    }
    m_tooltipReserve = reserve;
    updateSize();
    Q_EMIT tooltipReserveChanged();
}

void DockView::setEdge(DockPlatform::Edge edge)
{
    if (m_edge == edge) {
        return;
    }
    m_edge = edge;
    updateSize();
    Q_EMIT edgeChanged();
}

TaskIconProvider *DockView::iconProvider() const
{
    return m_iconProvider;
}

QScreen *DockView::dockScreen() const
{
    return m_dockScreen ? m_dockScreen.data() : screen();
}

void DockView::bumpIconCacheVersion()
{
    ++m_iconCacheVersion;
    Q_EMIT iconCacheVersionChanged();
}

void DockView::setScreenSettings(ScreenSettings *screenSettings)
{
    m_screenSettings = screenSettings;
}

int DockView::panelBarHeight() const
{
    const int iconSize = m_screenSettings ? m_screenSettings->iconSize() : m_settings->iconSize();
    const int leadingPadding = isVertical() ? m_settings->contentPaddingLeft() : m_settings->contentPaddingTop();
    const int trailingPadding = isVertical() ? m_settings->contentPaddingRight() : m_settings->contentPaddingBottom();
    return kdockw::panelBarHeight(iconSize,
                                  leadingPadding,
                                  trailingPadding,
                                  kdockw::runningIndicatorReserveForSize(m_settings->runningIndicatorSize()),
                                  floatingPadding());
}

DockPlatform *DockView::platform() const
{
    return m_platform.get();
}

DockVisibilityController *DockView::visibilityController() const
{
    return m_visibilityController;
}

QVariantMap DockView::zoomLayout(int count,
                                 qreal restStart,
                                 qreal iconSize,
                                 qreal spacing,
                                 int boundary,
                                 qreal boundaryGap,
                                 qreal restBackgroundStart,
                                 qreal restBackgroundEnd,
                                 qreal maxZoomFactor,
                                 int style,
                                 bool active,
                                 qreal cursor,
                                 qreal minEdge,
                                 qreal maxEdge) const
{
    return zoomLayoutVariant(count,
                             restStart,
                             iconSize,
                             spacing,
                             boundary,
                             boundaryGap,
                             restBackgroundStart,
                             restBackgroundEnd,
                             maxZoomFactor,
                             style,
                             active,
                             cursor,
                             minEdge,
                             maxEdge);
}

QVariantMap DockView::zoomLayoutForItems(const QVariantList &specs,
                                         qreal restStart,
                                         qreal spacing,
                                         int boundary,
                                         qreal boundaryGap,
                                         qreal restBackgroundStart,
                                         qreal restBackgroundEnd,
                                         qreal maxZoomFactor,
                                         int style,
                                         bool active,
                                         qreal cursor,
                                         qreal minEdge,
                                         qreal maxEdge) const
{
    return zoomLayoutItemsVariant(specs, restStart, spacing, boundary, boundaryGap, restBackgroundStart,
                                  restBackgroundEnd, maxZoomFactor, style, active, cursor, minEdge, maxEdge);
}

void DockView::updateSize()
{
    const int iconSize = m_screenSettings ? m_screenSettings->iconSize() : m_settings->iconSize();
    const double maxZoom = m_screenSettings ? m_screenSettings->maxZoomFactor() : m_settings->maxZoomFactor();
    const int crossPaddingLeading = isVertical() ? m_settings->contentPaddingLeft() : m_settings->contentPaddingTop();
    const int crossPaddingTrailing = isVertical() ? m_settings->contentPaddingRight()
                                                  : m_settings->contentPaddingBottom();
    // The tooltip is rendered inside this layer-shell surface on every edge.
    // Reserve its full extent plus zoom gap and shadow, not a fixed strip.
    const int tooltipReserve = std::max(s_tooltipReserve, m_tooltipReserve);
    const int h = kdockw::surfaceHeight(iconSize,
                                        crossPaddingLeading,
                                        crossPaddingTrailing,
                                        kdockw::runningIndicatorReserveForSize(m_settings->runningIndicatorSize()),
                                        maxZoom,
                                        tooltipReserve,
                                        floatingPadding());
    const QRect screenGeo = dockScreen() ? dockScreen()->geometry() : QRect();

    if (isVertical()) {
        // Vertical dock: h becomes width, screen height becomes height
        setWidth(h);
        setHeight(screenGeo.height());
        // Layer-shell: 0 on double-anchored axis (Top+Bottom) lets compositor decide
        m_platform->setSize(QSize(h, 0));
    } else {
        // Horizontal dock: screen width becomes width, h becomes height
        setWidth(screenGeo.width());
        setHeight(h);
        // Layer-shell: 0 on double-anchored axis (Left+Right) lets compositor decide
        m_platform->setSize(QSize(0, h));
    }

    // Reserve the panel bar only when screen-space reservation is enabled.
    m_platform->setExclusiveZone(kdockw::exclusiveZone(panelBarHeight(), m_settings->windowGap(), m_settings->reserveScreenSpace()));

    if (m_geometryTraceEnabled) {
        traceLayerGeometry(QStringLiteral("size-and-zone-requested"));
        m_geometryTraceAfterFrame = QStringLiteral("size-and-zone-requested");
    }

    if (m_visibilityController) {
        m_visibilityController->setZoomOverflowHeight(zoomOverflowHeight());
    }
}

int DockView::zoomOverflowHeight() const
{
    const int iconSize = m_screenSettings ? m_screenSettings->iconSize() : m_settings->iconSize();
    const double maxZoom = m_screenSettings ? m_screenSettings->maxZoomFactor() : m_settings->maxZoomFactor();
    return kdockw::zoomOverflowHeight(iconSize, maxZoom);
}

void DockView::handleScreenChanged(QScreen *newScreen)
{
    if (m_dockScreen && newScreen != m_dockScreen) {
        // QtWayland can recompute QWindow::screen() from a layer surface's
        // global geometry after output topology changes. The layer surface is
        // still pinned to m_dockScreen; keep sizing and screen-bound behavior
        // tied to that assigned output instead of migrating the dock state.
        qCDebug(lcDockView) << "Ignoring QWindow screen reassignment; dock remains on:" << m_dockScreen->name()
                            << "reported screen:" << (newScreen ? newScreen->name() : QStringLiteral("nullptr"));
        return;
    }

    // Disconnect from old screen's geometry signal
    disconnect(m_screenGeometryConnection);

    if (!newScreen) {
        qCDebug(lcDockView) << "Screen changed to nullptr (DPMS off / placeholder)";
        return;
    }

    // Connect to new screen's geometry signal
    m_screenGeometryConnection = connect(m_dockScreen ? m_dockScreen.data() : newScreen,
                                         &QScreen::geometryChanged,
                                         this,
                                         &DockView::handleScreenGeometryChanged);

    const QRect geo = dockScreen()->geometry();
    Q_EMIT screenGeometryChanged();
    qCDebug(lcDockView) << "Screen changed:" << newScreen->name() << "geometry=" << geo;

    // Skip recovery if geometry is invalid (placeholder screen during DPMS off)
    if (geo.width() <= 0 || geo.height() <= 0) {
        return;
    }

    // Not created yet: this is the screen assignment made while the platform
    // window is being created, and the surface will be created on newScreen.
    // hide()+show() here would re-enter QWindow::create() and leak a second
    // platform window whose QWindow pointer dangles after this view is destroyed.
    if (!handle()) {
        return;
    }

    // Force surface re-creation: the compositor destroys the layer-shell surface
    // when the associated output is removed. hide()+show() creates a fresh surface.
    hide();
    m_backgroundEffectPlan = {};
    updateSize();
    applyBackgroundStyle();
    show();
    if (m_visibilityController) {
        m_visibilityController->requestEvaluate();
    }
}

void DockView::handleScreenGeometryChanged()
{
    if (!dockScreen()) {
        return;
    }

    const QRect geo = dockScreen()->geometry();
    Q_EMIT screenGeometryChanged();
    qCDebug(lcDockView) << "Screen geometry changed:" << geo;

    if (geo.width() <= 0 || geo.height() <= 0) {
        return;
    }

    updateSize();
    applyBackgroundStyle();
    if (m_visibilityController) {
        m_visibilityController->requestEvaluate();
    }
}

void DockView::handleScreenLockChanged(bool active)
{
    if (m_geometryTraceEnabled) {
        traceLayerGeometry(active ? QStringLiteral("screensaver-active") : QStringLiteral("before-unlock-recovery"));
    }
    if (active) {
        m_unlockRecoveryPolicy.remember(unlockRecoveryState());
        return;
    }

    const auto decision = m_unlockRecoveryPolicy.consume(unlockRecoveryState());
    if (decision != UnlockRecoveryPolicy::Decision::Changed) {
        qCDebug(lcDockView) << "Screen unlocked — keeping current dock surface"
                            << (decision == UnlockRecoveryPolicy::Decision::Unchanged ? "(unchanged)" : "(no lock snapshot)");
        applyBackgroundStyle();
        if (m_geometryTraceEnabled) {
            traceLayerGeometry(QStringLiteral("after-unlock-surface-kept"));
            m_geometryTraceAfterFrame = QStringLiteral("unlock-surface-kept");
        }
        if (m_visibilityController) {
            m_visibilityController->requestEvaluate();
        }
        return;
    }

    qCDebug(lcDockView) << "Screen unlocked — recovering dock";
    // Surface may have been destroyed during DPMS-off while locked.
    // hide()+show() ensures a fresh surface on the current screen.
    hide();
    m_backgroundEffectPlan = {};
    updateSize();
    applyBackgroundStyle();
    show();
    if (m_geometryTraceEnabled) {
        traceLayerGeometry(QStringLiteral("after-unlock-show"));
        m_geometryTraceAfterFrame = QStringLiteral("unlock-recovery");
    }
    if (m_visibilityController) {
        m_visibilityController->requestEvaluate();
    }
}

UnlockRecoveryState DockView::unlockRecoveryState() const
{
    const bool reserveScreenSpace = m_settings->reserveScreenSpace();
    return {
        .screenIdentity = reinterpret_cast<quintptr>(dockScreen()),
        .screenGeometry = dockScreen() ? dockScreen()->geometry() : QRect{},
        .windowSize = size(),
        .layerSize = isVertical() ? QSize(width(), 0) : QSize(0, height()),
        .edge = static_cast<int>(m_edge),
        .platformEdge = static_cast<int>(m_platform->edge()),
        .requestedExclusiveZone = kdockw::exclusiveZone(panelBarHeight(), m_settings->windowGap(), reserveScreenSpace),
        .windowGap = m_settings->windowGap(),
        .reserveScreenSpace = reserveScreenSpace,
        .margin = m_platform->margin(),
        .visibilityMode = m_visibilityController ? m_visibilityController->mode() : -1,
    };
}

void DockView::traceLayerGeometry(const QString &phase)
{
    if (!m_geometryTraceEnabled) {
        return;
    }

    QScreen *screen = dockScreen();
    LayerShellQt::Window *layerWindow = LayerShellQt::Window::get(this);
    const QRect screenRect = screen ? screen->geometry() : QRect{};
    const QRect availableRect = screen ? screen->availableGeometry() : QRect{};
    QRect derivedSurfaceRect;
    switch (m_edge) {
    case DockPlatform::Edge::Top:
        derivedSurfaceRect = QRect(screenRect.x(), screenRect.y(), width(), height());
        break;
    case DockPlatform::Edge::Bottom:
        derivedSurfaceRect = QRect(screenRect.x(), screenRect.bottom() - height() + 1, width(), height());
        break;
    case DockPlatform::Edge::Left:
        derivedSurfaceRect = QRect(screenRect.x(), screenRect.y(), width(), height());
        break;
    case DockPlatform::Edge::Right:
        derivedSurfaceRect = QRect(screenRect.right() - width() + 1, screenRect.y(), width(), height());
        break;
    }

    QString layerScreenName = QStringLiteral("<unavailable>");
#ifndef KDOCKW_COMPAT_NO_LAYERSHELL_SCREEN
    if (layerWindow && layerWindow->screen()) {
        layerScreenName = layerWindow->screen()->name();
    }
#endif

    qCInfo(lcDockView).noquote() << "[KDOCKW_GEOMETRY_TRACE]"
                                 << "phase=" << phase
                                 << "screen=" << (screen ? screen->name() : QStringLiteral("<null>"))
                                 << "layerScreen=" << layerScreenName
                                 << "screenGeometry=" << screenRect
                                 << "availableGeometry=" << availableRect
                                 << "derivedSurfaceGeometry=" << derivedSurfaceRect
                                 << "qtGeometry=" << geometry()
                                 << "qtFrameGeometry=" << frameGeometry()
                                 << "size=" << size()
                                 << "zoneRequested=" << kdockw::exclusiveZone(panelBarHeight(), m_settings->windowGap(), m_settings->reserveScreenSpace())
                                 << "zoneLayerShell=" << (layerWindow ? layerWindow->exclusionZone() : -999)
                                 << "anchors=" << (layerWindow ? static_cast<int>(layerWindow->anchors()) : -1)
                                 << "edge=" << static_cast<int>(m_edge)
                                 << "reserve=" << m_settings->reserveScreenSpace()
                                 << "visible=" << isVisible()
                                 << "exposed=" << isExposed();
}

void DockView::applyBackgroundStyle()
{
    auto type = static_cast<BackgroundStyleType>(m_settings->backgroundStyle());
    qreal opacity = m_settings->backgroundOpacity();

    // When opacity is 0, compositor effects (blur/contrast) must also be disabled.
    // Otherwise KWindowEffects creates a visible frosted layer even with transparent QML color.
    if (styleUsesBlur(type) && qFuzzyIsNull(opacity)) {
        removeBackgroundFromWindow(this);
        m_backgroundEffectPlan = {};
        Q_EMIT backgroundColorChanged();
        Q_EMIT backgroundStyleTypeChanged();
        return;
    }

    // Restrict blur/contrast to the panel rectangle only.
    // Without a region, KWindowEffects applies effects to the entire layer-shell surface,
    // which covers the full screen width and causes a colored bar across the bottom.
    // Use a rounded rectangle to match the panel's corner radius.
    QRegion region;
    if (m_visibilityController) {
        const QRect panel = m_visibilityController->panelRect();
        if (panel.width() > 0) {
            const int radius = m_settings->cornerRadius();
            if (radius > 0) {
                QPainterPath path;
                path.addRoundedRect(QRectF(panel), radius, radius);
                region = QRegion(path.toFillPolygon().toPolygon());
            } else {
                region = QRegion(panel);
            }
        }
    }

    // An empty region means "whole surface" to KWin, which would blur the entire
    // (mostly transparent) layer-shell surface. Until QML reports the panel rect,
    // keep compositor effects off; panelRectChanged re-applies them.
    if (region.isEmpty() && styleUsesBlur(type)) {
        removeBackgroundFromWindow(this);
        m_backgroundEffectPlan = {};
    } else {
        const BackgroundEffectPlan plan = backgroundEffectPlan(type, region);
        applyBackgroundToWindow(this, plan, m_backgroundEffectPlan);
        m_backgroundEffectPlan = plan;
    }
    Q_EMIT backgroundColorChanged();
    Q_EMIT backgroundStyleTypeChanged();
}

} // namespace kdockw
