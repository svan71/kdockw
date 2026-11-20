// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Pointer hit testing of dock icons on every screen edge.
//
// main.qml maps the pointer to (primary = along the dock, secondary = depth)
// and updateHoveredItem() picks the icon whose zoomed bounds contain it. The
// secondary-axis bounds used to be hard-coded for a bottom dock, so on left
// and right docks only the first icon could be hovered or clicked, and on a
// top dock the zoomed part of an icon did not react.
//
// Drives the real MultiDockManager against a KWin virtual compositor and
// feeds synthetic pointer events into the dock window, so the whole QML path
// (MouseArea -> updateHoveredItem -> onClicked -> DockActions) is exercised.
//
// Must run under run-with-kwin.sh, which provides WAYLAND_DISPLAY, a private
// session bus and throwaway XDG directories.

#include "kdockw.h"
#include "models/dockactions.h"
#include "models/dockentry.h"
#include "models/dockmodel.h"
#include "models/launcherentrytracker.h"
#include "models/notificationtracker.h"
#include "platform/pointerfocustracker.h"
#include "shell/dockshell.h"
#include "shell/dockview.h"
#include "shell/multidockmanager.h"
#include "shell/outputordermonitor.h"
#include "../dockqmltypes.h"

#include <KAboutData>
#include <catch2/catch_session.hpp>
#include <catch2/catch_test_macros.hpp>

#include <QApplication>
#include <QDebug>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QProcess>
#include <QQuickItem>
#include <QQuickStyle>
#include <QScopeGuard>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTest>
#include <QtQml>

#include <algorithm>
#include <memory>

static void initResources()
{
    Q_INIT_RESOURCE(qml);
}

namespace
{

using Edge = kdockw::DockPlatform::Edge;

constexpr int kTimeoutMs = 15000;
constexpr int kLauncherCount = 5;

class TestPointerFocusTracker final : public kdockw::PointerFocusTracker
{
public:
    explicit TestPointerFocusTracker(QWindow *dockWindow, bool available = true)
        : PointerFocusTracker(dockWindow, false)
        , m_dockWindow(dockWindow)
        , m_available(available)
    {
    }

    [[nodiscard]] bool isPointerInside() const override { return m_inside; }
    [[nodiscard]] bool hasPointerFocus() const override { return !m_focusWindow.isNull(); }
    [[nodiscard]] QWindow *pointerFocusWindow() const override { return m_focusWindow.data(); }
    [[nodiscard]] bool isAvailable() const override { return m_available; }
    [[nodiscard]] quint64 dockSurfaceId() const override { return m_dockSurfaceId; }
    [[nodiscard]] quint64 dockSurfaceGeneration() const override { return m_dockSurfaceGeneration; }

    void sendSample(QWindow *focusWindow, const QPointF &position, bool valid = true)
    {
        const bool wasInside = m_inside;
        m_focusWindow = focusWindow;
        m_inside = valid && focusWindow == m_dockWindow;
        if (wasInside != m_inside)
            Q_EMIT pointerInsideChanged();
        Q_EMIT pointerFocusChanged();

        kdockw::PointerSample sample;
        sample.surfaceLocalPosition = position;
        sample.sequence = ++m_sequence;
        sample.surfaceId = focusWindow == m_dockWindow ? dockSurfaceId() : (focusWindow ? 202 : 0);
        sample.surfaceGeneration = focusWindow == m_dockWindow ? dockSurfaceGeneration() : (focusWindow ? 3 : 0);
        sample.pointerGeneration = 1;
        sample.focusedWindow = focusWindow;
        sample.valid = valid;
        sample.focusKnown = focusWindow != nullptr;
        publishPointerSample(sample);
    }

    void sendStaleSample(const QPointF &position, quint64 sequence)
    {
        kdockw::PointerSample sample;
        sample.surfaceLocalPosition = position;
        sample.sequence = sequence;
        sample.surfaceId = dockSurfaceId();
        sample.surfaceGeneration = dockSurfaceGeneration();
        sample.pointerGeneration = 1;
        sample.focusedWindow = m_dockWindow;
        sample.valid = true;
        sample.focusKnown = true;
        publishPointerSample(sample);
    }

    void sendMismatchedSurfaceSample(const QPointF &position)
    {
        kdockw::PointerSample sample;
        sample.surfaceLocalPosition = position;
        sample.sequence = ++m_sequence;
        sample.surfaceId = dockSurfaceId();
        sample.surfaceGeneration = dockSurfaceGeneration() + 1;
        sample.pointerGeneration = 1;
        sample.focusedWindow = m_dockWindow;
        sample.valid = true;
        sample.focusKnown = true;
        publishPointerSample(sample);
    }

    void recreateDockSurface()
    {
        ++m_dockSurfaceId;
        ++m_dockSurfaceGeneration;
    }

    [[nodiscard]] quint64 latestSequence() const { return m_sequence; }

private:
    QPointer<QWindow> m_dockWindow;
    QPointer<QWindow> m_focusWindow;
    bool m_available = true;
    bool m_inside = false;
    quint64 m_sequence = 0;
    quint64 m_dockSurfaceId = 101;
    quint64 m_dockSurfaceGeneration = 7;
};

struct App {
    std::unique_ptr<KDockWSettings> settings;
    std::unique_ptr<kdockw::DockModel> model;
    std::unique_ptr<kdockw::NotificationTracker> tracker;
    std::unique_ptr<kdockw::LauncherEntryTracker> launcherEntries;
};

// Mirrors the QML singletons Application::run() registers.
App &app()
{
    static App *instance = [] {
        auto *a = new App;
        a->settings = std::make_unique<KDockWSettings>();
        a->settings->load();
        a->settings->setMonitorMode(kdockw::MultiDockManager::PrimaryOnly);
        a->model = std::make_unique<kdockw::DockModel>();
        a->tracker = std::make_unique<kdockw::NotificationTracker>();
        a->launcherEntries = std::make_unique<kdockw::LauncherEntryTracker>();

        auto *model = a->model.get();
        qmlRegisterSingletonType<kdockw::DockModel>("com.thicking.kdockw", 1, 0, "DockModel", [model](QQmlEngine *, QJSEngine *) -> QObject * {
            QQmlEngine::setObjectOwnership(model, QQmlEngine::CppOwnership);
            return model;
        });
        auto *settings = a->settings.get();
        qmlRegisterSingletonType<KDockWSettings>("com.thicking.kdockw", 1, 0, "DockSettings", [settings](QQmlEngine *, QJSEngine *) -> QObject * {
            QQmlEngine::setObjectOwnership(settings, QQmlEngine::CppOwnership);
            return settings;
        });
        auto *tracker = a->tracker.get();
        qmlRegisterSingletonType<kdockw::NotificationTracker>("com.thicking.kdockw", 1, 0, "NotificationTracker", [tracker](QQmlEngine *, QJSEngine *) -> QObject * {
            QQmlEngine::setObjectOwnership(tracker, QQmlEngine::CppOwnership);
            return tracker;
        });
        auto *launcherEntries = a->launcherEntries.get();
        qmlRegisterSingletonType<kdockw::LauncherEntryTracker>("com.thicking.kdockw",
                                                              1,
                                                              0,
                                                              "LauncherEntryTracker",
                                                              [launcherEntries](QQmlEngine *, QJSEngine *) -> QObject * {
                                                                  QQmlEngine::setObjectOwnership(launcherEntries, QQmlEngine::CppOwnership);
                                                                  return launcherEntries;
                                                              });
        registerDockQmlTypes();
        return a;
    }();
    return *instance;
}

QString launcherName(int i)
{
    return QStringLiteral("KDockW Hit %1").arg(QChar(u'A' + i));
}

// Pins kLauncherCount launchers whose activation is harmless and observable
// only through DockActions::taskLaunching.
void pinLaunchers()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/applications");
    REQUIRE(QDir().mkpath(dir));
    QStringList urls;
    for (int i = 0; i < kLauncherCount; ++i) {
        QFile desktop(dir + QStringLiteral("/kdockw-hit-%1.desktop").arg(i));
        REQUIRE(desktop.open(QIODevice::WriteOnly | QIODevice::Truncate));
        desktop.write(QStringLiteral("[Desktop Entry]\nType=Application\nName=%1\nExec=true\nStartupNotify=false\nIcon=utilities-terminal\n")
                          .arg(launcherName(i))
                          .toUtf8());
        desktop.close();
        urls.append(QUrl::fromLocalFile(desktop.fileName()).toString());
    }
    QProcess::execute(QStringLiteral("kbuildsycoca6"), {});
    app().settings->setPinnedLaunchers(urls);
    // This helper may run after the authoritative-pointer test adds a media
    // player to the shared model. Reset the complete order so hit testing
    // always sees exactly the five launchers it owns.
    app().model->loadDockEntries(kdockw::DockEntriesCodec::encode(kdockw::DockEntriesCodec::fromLegacyLaunchers(urls)));
}

void collectDelegates(QQuickItem *item, QList<QQuickItem *> &out)
{
    for (auto *child : item->childItems()) {
        if (child->property("itemCenterX").isValid() && child->property("displayName").isValid()) {
            out.append(child);
        }
        collectDelegates(child, out);
    }
}

// Dock icon delegates in dock order (along the primary axis).
QList<QQuickItem *> delegates(kdockw::DockView *view)
{
    QList<QQuickItem *> items;
    if (view->rootObject()) {
        collectDelegates(view->rootObject(), items);
    }
    std::sort(items.begin(), items.end(), [](QQuickItem *a, QQuickItem *b) {
        return a->property("itemCenterX").toReal() < b->property("itemCenterX").toReal();
    });
    return items;
}

// Unscaled icon rectangle in window coordinates (the Scale transform is
// applied on top of the item's own geometry, so map the parent's rect).
QRectF baseRect(QQuickItem *item)
{
    return item->parentItem()->mapRectToScene(QRectF(item->position(), item->size()));
}

// A point inside the zoomed icon but outside its unscaled rect: past the
// icon's inner side (away from the screen edge), where the zoom grows.
QPointF zoomedExtensionPoint(const QRectF &r, Edge edge, qreal scale)
{
    const QPointF c = r.center();
    switch (edge) {
    case Edge::Top:
        return {c.x(), r.bottom() + r.height() * (scale - 1.0) / 2.0};
    case Edge::Bottom:
        return {c.x(), r.top() - r.height() * (scale - 1.0) / 2.0};
    case Edge::Left:
        return {r.right() + r.width() * (scale - 1.0) / 2.0, c.y()};
    case Edge::Right:
        return {r.left() - r.width() * (scale - 1.0) / 2.0, c.y()};
    }
    return c;
}

const char *edgeName(Edge edge)
{
    switch (edge) {
    case Edge::Top:
        return "top";
    case Edge::Bottom:
        return "bottom";
    case Edge::Left:
        return "left";
    case Edge::Right:
        return "right";
    }
    return "?";
}

void runEdge(Edge edge)
{
    INFO("edge " << edgeName(edge));
    pinLaunchers();
    app().settings->setEdge(static_cast<int>(edge));
    const auto restore = qScopeGuard([] {
        app().settings->setEdge(static_cast<int>(Edge::Bottom));
    });

    // Like Application::run(): create shells only once the Plasma output
    // order is known, otherwise the shell is recreated underneath the test.
    REQUIRE(QTest::qWaitFor(
        [] {
            return kdockw::OutputOrderMonitor::instance()->orderReady();
        },
        kTimeoutMs));
    // QTest injects Qt mouse events directly and does not generate compositor
    // wl_pointer samples. Keep this test on the Qt fallback path; the
    // authoritative-source path is exercised by runAuthoritativePointerReturn.
    kdockw::PointerFocusTrackerFactory factory = [](QWindow *window) {
        return std::make_unique<TestPointerFocusTracker>(window, false);
    };
    auto manager = std::make_unique<kdockw::MultiDockManager>(app().settings.get(), app().model.get(), app().tracker.get(), nullptr,
                                                              std::move(factory));
    manager->initialize();
    auto *shell = manager->primaryShell();
    REQUIRE(shell);
    auto *view = shell->view();
    REQUIRE(QTest::qWaitForWindowExposed(view, kTimeoutMs));
    REQUIRE(manager->primaryShell() == shell);

    // Wait until all launchers are laid out and the slide-in and add/move
    // transitions have settled (geometry unchanged for 500 ms).
    QList<QRectF> previous;
    QList<QRectF> firstObserved;
    int geometryChangeSamples = 0;
    int delegateCountMismatchSamples = 0;
    int lastDelegateCount = 0;
    QElapsedTimer unchanged;
    unchanged.start();
    const bool layoutSettled = QTest::qWaitFor(
        [&] {
            const auto items = delegates(view);
            QList<QRectF> now;
            for (auto *item : items) {
                now.append(baseRect(item));
            }
            lastDelegateCount = items.size();
            if (items.size() != kLauncherCount) {
                ++delegateCountMismatchSamples;
            }
            if (items.size() != kLauncherCount || now != previous) {
                if (!now.isEmpty() && firstObserved.isEmpty()) {
                    firstObserved = now;
                }
                if (now != previous) {
                    ++geometryChangeSamples;
                }
                previous = now;
                unchanged.restart();
                return false;
            }
            return unchanged.elapsed() >= 500;
        },
        kTimeoutMs);
    if (!layoutSettled) {
        qWarning() << "HITTEST_LAYOUT_TIMEOUT" << edgeName(edge) << "delegateCount" << lastDelegateCount << "geometryChangeSamples"
                   << geometryChangeSamples << "delegateCountMismatchSamples" << delegateCountMismatchSamples << "first" << firstObserved
                   << "last" << previous;
    }
    REQUIRE(layoutSettled);

    const qreal maxZoom = app().settings->maxZoomFactor();
    REQUIRE(maxZoom > 1.2);

    QSignalSpy launching(shell->actions(), &kdockw::DockActions::taskLaunching);
    QObject *root = view->rootObject();

    for (int i : {0, kLauncherCount / 2, kLauncherCount - 1}) {
        INFO("icon " << i);
        auto items = delegates(view);
        REQUIRE(items.size() == kLauncherCount);
        QQuickItem *icon = items.at(i);
        REQUIRE(icon->property("displayName").toString() == launcherName(i));
        const QRectF r = baseRect(icon);

        // hoveredIndex once it equals i, or its value after a short wait.
        auto hoveredAfterWait = [&] {
            QTest::qWaitFor(
                [&] {
                    return root->property("hoveredIndex").toInt() == i;
                },
                2000);
            return root->property("hoveredIndex").toInt();
        };

        // Icon center selects the icon.
        QTest::mouseMove(view, r.center().toPoint());
        const int centerHovered = hoveredAfterWait();
        qInfo("HIT edge=%s icon=%d where=center at=(%d,%d) hovered=%d", edgeName(edge), i, r.center().toPoint().x(), r.center().toPoint().y(), centerHovered);
        CHECK(centerHovered == i);

        // Let the zoom grow, then hover the zoomed part of the icon.
        CHECK(QTest::qWaitFor(
            [&] {
                return icon->property("currentScale").toReal() > maxZoom - 0.05;
            },
            2000));
        const QPoint ext = zoomedExtensionPoint(r, edge, maxZoom).toPoint();
        QTest::mouseMove(view, ext);
        const int extHovered = hoveredAfterWait();
        qInfo("HIT edge=%s icon=%d where=zoomed at=(%d,%d) scale=%.2f hovered=%d",
              edgeName(edge),
              i,
              ext.x(),
              ext.y(),
              icon->property("currentScale").toReal(),
              extHovered);
        CHECK(extHovered == i);

        // Clicking there activates exactly this launcher.
        launching.clear();
        QTest::mouseClick(view, Qt::LeftButton, {}, ext);
        QTest::qWaitFor(
            [&] {
                return !launching.isEmpty();
            },
            2000);
        const int activated = launching.isEmpty() ? -1 : launching.first().first().toInt();
        qInfo("HIT edge=%s icon=%d where=click at=(%d,%d) activated=%d", edgeName(edge), i, ext.x(), ext.y(), activated);
        CHECK(activated == i);

        // Along the dock an icon is claimed only up to half its scaled
        // along-dock extent, widened by 25% hysteresis for the hovered one
        // (updateHoveredItem). One pixel past that boundary the point is
        // inside the next icon's rect, or past the last icon on the dock.
        // On vertical docks that extent is item.height, not item.width.
        const bool vertical = (edge == Edge::Left || edge == Edge::Right);
        const qreal depthPos = vertical ? r.center().x() : r.center().y();
        QQuickItem *next = i + 1 < items.size() ? items.at(i + 1) : nullptr;
        const qreal extent = vertical ? icon->height() : icon->width();
        const qreal scale = icon->property("currentScale").toReal();
        const qreal centerPos = vertical ? r.center().y() : r.center().x();
        const qreal alongPos = centerPos + extent * scale / 2.0 * 1.25 + 1.0;
        const QPoint along =
            vertical ? QPoint(static_cast<int>(depthPos), static_cast<int>(alongPos)) : QPoint(static_cast<int>(alongPos), static_cast<int>(depthPos));
        const int neighborIndex = next ? i + 1 : -1;
        QTest::mouseMove(view, along);
        QTest::qWaitFor(
            [&] {
                return root->property("hoveredIndex").toInt() != i;
            },
            2000);
        const int alongHovered = root->property("hoveredIndex").toInt();
        qInfo("HIT edge=%s icon=%d where=along-dock at=(%d,%d) hovered=%d expect=%d", edgeName(edge), i, along.x(), along.y(), alongHovered, neighborIndex);
        CHECK(alongHovered == neighborIndex);
    }
}

void runAuthoritativePointerReturn(Edge edge)
{
    INFO("authoritative pointer return on " << edgeName(edge));
    pinLaunchers();
    auto &a = app();
    a.settings->setEdge(static_cast<int>(edge));
    const auto restore = qScopeGuard([&a] { a.settings->setEdge(static_cast<int>(Edge::Bottom)); });
    a.settings->setMagnificationMode(1); // Spring
    a.settings->setMediaPlayerEnabled(true);
    a.settings->setMediaPlayerDisplayMode(0); // Compact
    a.settings->setMediaPlayerHoverPopup(true);
    a.settings->setMediaPlayerHoverDelay(80);
    a.model->setMediaPlayerEnabled(true);
    if (!a.model->dockEntriesModel()->hasMediaPlayer())
        REQUIRE(!a.model->dockEntriesModel()->appendMediaPlayer().isEmpty());
    a.model->dockPresentationModel()->setMediaPlayerAvailable(true);

    REQUIRE(QTest::qWaitFor(
        [] { return kdockw::OutputOrderMonitor::instance()->orderReady(); },
        kTimeoutMs));
    TestPointerFocusTracker *pointerTracker = nullptr;
    kdockw::PointerFocusTrackerFactory factory = [&pointerTracker](QWindow *window) {
        auto tracker = std::make_unique<TestPointerFocusTracker>(window);
        pointerTracker = tracker.get();
        return tracker;
    };
    auto manager = std::make_unique<kdockw::MultiDockManager>(a.settings.get(), a.model.get(), a.tracker.get(), nullptr,
                                                              std::move(factory));
    manager->initialize();
    auto *shell = manager->primaryShell();
    REQUIRE(shell);
    auto *view = shell->view();
    REQUIRE(QTest::qWaitForWindowExposed(view, kTimeoutMs));
    REQUIRE(pointerTracker);
    CHECK(view->pointerSourceMode() == 1);

    QObject *root = view->rootObject();
    REQUIRE(root);
    QQuickItem *media = nullptr;
    REQUIRE(QTest::qWaitFor(
        [&] {
            media = nullptr;
            for (QQuickItem *item : delegates(view)) {
                if (item->property("isMediaPlayer").toBool()) {
                    media = item;
                    break;
                }
            }
            return media != nullptr
                && qvariant_cast<QQuickItem *>(media->property("mediaPlayerWidget")) != nullptr;
        },
        kTimeoutMs));

    auto *spring = root->findChild<QObject *>(QStringLiteral("dockSpringZoomController"));
    REQUIRE(spring);
    const int mediaIndex = media->property("index").toInt();
    const QRectF mediaBounds = baseRect(media);
    const QPointF mediaCenter = mediaBounds.center();
    pointerTracker->sendSample(view, mediaCenter);
    REQUIRE(QTest::qWaitFor([&] { return root->property("hoveredIndex").toInt() == mediaIndex; }, 3000));
    REQUIRE(QTest::qWaitFor([&] { return spring->property("targetAmount").toReal() > 0.999; }, 3000));
    REQUIRE(QTest::qWaitFor([&] { return media->property("currentScale").toReal() > 1.05; }, 3000));

    auto *mediaWidget = qvariant_cast<QQuickItem *>(media->property("mediaPlayerWidget"));
    REQUIRE(mediaWidget);
    QTest::mouseMove(view, mediaCenter.toPoint(), 30);
    REQUIRE(QTest::qWaitFor([&] { return mediaWidget->property("diagnosticPopupVisible").toBool(); }, 5000));
    auto *popupWindow = qvariant_cast<QWindow *>(mediaWidget->property("popupWindow"));
    REQUIRE(popupWindow);

    pointerTracker->sendSample(popupWindow, QPointF(12, 12));
    REQUIRE(QTest::qWaitFor([&] { return root->property("hoveredIndex").toInt() == -1; }, 3000));
    REQUIRE(QTest::qWaitFor([&] { return spring->property("targetAmount").toReal() < 0.001; }, 3000));
    const bool vertical = edge == Edge::Left || edge == Edge::Right;
    const QPointF staleQtPoint = mediaBounds.center() + (vertical ? QPointF(0, 40) : QPointF(40, 0));
    QTest::mouseMove(view, staleQtPoint.toPoint(), 30);
    QCoreApplication::processEvents();
    CHECK(root->property("hoveredIndex").toInt() == -1);
    CHECK(spring->property("targetAmount").toReal() < 0.001);

    // Deliberately leave QML at the stale Qt point. Only a fresh Wayland
    // sample may restore the Compact hit and SpringZoomController target.
    pointerTracker->sendSample(view, mediaCenter);
    REQUIRE(QTest::qWaitFor([&] { return root->property("hoveredIndex").toInt() == mediaIndex; }, 3000));
    REQUIRE(QTest::qWaitFor([&] { return spring->property("targetAmount").toReal() > 0.999; }, 3000));
    REQUIRE(QTest::qWaitFor([&] { return media->property("currentScale").toReal() > 1.05; }, 3000));
    const quint64 acceptedSequence = pointerTracker->latestSequence();
    pointerTracker->sendStaleSample(staleQtPoint, acceptedSequence - 1);
    QTest::mouseMove(view, staleQtPoint.toPoint(), 30);
    QCoreApplication::processEvents();
    CHECK(root->property("hoveredIndex").toInt() == mediaIndex);
    CHECK(spring->property("targetAmount").toReal() > 0.999);

    pointerTracker->sendMismatchedSurfaceSample(mediaCenter);
    REQUIRE(QTest::qWaitFor([&] { return !view->pointerSampleValid(); }, 3000));
    REQUIRE(QTest::qWaitFor([&] { return root->property("hoveredIndex").toInt() == -1; }, 3000));
    REQUIRE(QTest::qWaitFor([&] { return spring->property("targetAmount").toReal() < 0.001; }, 3000));
    pointerTracker->recreateDockSurface();
    pointerTracker->sendSample(view, mediaCenter);
    REQUIRE(QTest::qWaitFor([&] { return view->pointerSampleValid(); }, 3000));
    REQUIRE(QTest::qWaitFor([&] { return root->property("hoveredIndex").toInt() == mediaIndex; }, 3000));
    REQUIRE(QTest::qWaitFor([&] { return spring->property("targetAmount").toReal() > 0.999; }, 3000));

    pointerTracker->sendSample(nullptr, {}, false);
    REQUIRE(QTest::qWaitFor([&] { return root->property("hoveredIndex").toInt() == -1; }, 3000));
    REQUIRE(QTest::qWaitFor([&] { return spring->property("targetAmount").toReal() < 0.001; }, 3000));
}

} // namespace

TEST_CASE("Hovering and clicking selects the icon under the pointer on every edge", "[hit-test]")
{
    SECTION("bottom")
    {
        runEdge(Edge::Bottom);
    }
    SECTION("top")
    {
        runEdge(Edge::Top);
    }
    SECTION("left")
    {
        runEdge(Edge::Left);
    }
    SECTION("right")
    {
        runEdge(Edge::Right);
    }
}

TEST_CASE("Authoritative Wayland samples restore Compact magnification after media popup", "[hit-test][pointer-source][media]")
{
    SECTION("bottom") { runAuthoritativePointerReturn(Edge::Bottom); }
    SECTION("top") { runAuthoritativePointerReturn(Edge::Top); }
    SECTION("left") { runAuthoritativePointerReturn(Edge::Left); }
    SECTION("right") { runAuthoritativePointerReturn(Edge::Right); }
}

int main(int argc, char *argv[])
{
    // Opt into the layer-shell platform plugin, like the real dock.
    qputenv("QT_WAYLAND_SHELL_INTEGRATION", "layer-shell");

    QApplication application(argc, argv);
    if (QQuickStyle::name().isEmpty()) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }
    KAboutData aboutData(QStringLiteral("kdockw"), QStringLiteral("KDockW"), QStringLiteral("test"));
    KAboutData::setApplicationData(aboutData);
    initResources();

    return Catch::Session().run(argc, argv);
}
