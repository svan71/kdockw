// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Qt Quick Test runner for KDockW's QML components.
//
// The real QML files under src/qml are loaded unchanged. Their C++ backends
// are replaced by test doubles:
//  - mocks/com/thicking/kdockw/*.qml  — QML singletons for DockModel,
//  DockSettings,
//    DockView, DockVisibility, DockActions, DockContextMenu, PreviewController,
//    NotificationTracker (production registers these as singletons/context
//    properties from C++).
//  - qmltestmocks.cpp            — org.kde.taskmanager / org.kde.pipewire
//  types.
// i18n() is provided by the real KLocalizedContext, exactly as in DockView.

#include "qmltestmocks.h"
#include "kdockw.h"
#include "models/applicationcatalog.h"
#include "models/applicationlauncherstate.h"
#include "utils/springzoomcontroller.h"

#include <KLocalizedQmlContext>
#include <KLocalizedString>
#include <QPointF>
#include <QColor>
#include <QQuickImageProvider>
#include <QQmlContext>
#include <QQmlEngine>
#include <QImage>
#include <QIcon>
#include <QRectF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QSize>
#include <QString>
#include <QTemporaryDir>
#include <QVariant>
#include <QtQuickTest>

#include <clocale>
#include <memory>

class MockPreviewFrameImageProvider final : public QQuickImageProvider {
public:
  MockPreviewFrameImageProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

  QImage requestImage(const QString &, QSize *size,
                      const QSize &requestedSize) override {
    const QSize imageSize = requestedSize.isValid() ? requestedSize : QSize(32, 20);
    if (size)
      *size = imageSize;
    QImage image(imageSize, QImage::Format_ARGB32_Premultiplied);
    image.fill(QColor(QStringLiteral("#5277aa")));
    return image;
  }
};

class MockIconImageProvider final : public QQuickImageProvider {
public:
  MockIconImageProvider() : QQuickImageProvider(QQuickImageProvider::Pixmap) {}

  QPixmap requestPixmap(const QString &, QSize *size,
                        const QSize &requestedSize) override {
    const QSize pixmapSize = requestedSize.width() > 0 && requestedSize.height() > 0
        ? requestedSize : QSize(32, 32);
    if (size)
      *size = pixmapSize;
    QPixmap pixmap(pixmapSize);
    pixmap.fill(QColor(QStringLiteral("#5277aa")));
    return pixmap;
  }
};

class SystemThemeIconImageProvider final : public QQuickImageProvider {
public:
  SystemThemeIconImageProvider() : QQuickImageProvider(QQuickImageProvider::Pixmap) {}

  QPixmap requestPixmap(const QString &id, QSize *size,
                        const QSize &requestedSize) override {
    const QSize pixmapSize = requestedSize.width() > 0 && requestedSize.height() > 0
        ? requestedSize : QSize(32, 32);
    if (size)
      *size = pixmapSize;
    const QString iconName = id.section(QLatin1Char('?'), 0, 0);
    QIcon icon = QIcon::fromTheme(iconName);
    if (icon.isNull())
      icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
    return icon.pixmap(pixmapSize);
  }
};

class MockIconDiagnostics : public QObject {
  Q_OBJECT
  Q_PROPERTY(
      bool debugEnabled READ debugEnabled WRITE setDebugEnabled NOTIFY changed)
  Q_PROPERTY(bool testHiDpiEnabled READ testHiDpiEnabled WRITE
                 setTestHiDpiEnabled NOTIFY changed)
  Q_PROPERTY(bool testBadgeLayerOff READ testBadgeLayerOff WRITE
                 setTestBadgeLayerOff NOTIFY changed)
  Q_PROPERTY(bool testBadgeShadowOff READ testBadgeShadowOff WRITE
                 setTestBadgeShadowOff NOTIFY changed)
  Q_PROPERTY(bool testBadgeCrisp READ testBadgeCrisp WRITE setTestBadgeCrisp
                 NOTIFY changed)
  Q_PROPERTY(bool testBadgeCrispStable READ testBadgeCrispStable WRITE
                 setTestBadgeCrispStable NOTIFY changed)
  Q_PROPERTY(bool testBadgeMetrics READ testBadgeMetrics WRITE
                 setTestBadgeMetrics NOTIFY changed)
  Q_PROPERTY(bool testBadgeSeparate READ testBadgeSeparate WRITE
                 setTestBadgeSeparate NOTIFY changed)
  Q_PROPERTY(bool testBadgeOverlay READ testBadgeOverlay WRITE
                 setTestBadgeOverlay NOTIFY changed)
  Q_PROPERTY(bool testBadgeTextQt READ testBadgeTextQt WRITE
                 setTestBadgeTextQt NOTIFY changed)
  Q_PROPERTY(bool testBadgeTextNative READ testBadgeTextNative WRITE
                 setTestBadgeTextNative NOTIFY changed)
  Q_PROPERTY(QString previewClipMode READ previewClipMode WRITE
                 setPreviewClipMode NOTIFY changed)
  Q_PROPERTY(QString previewSourceMode READ previewSourceMode WRITE
                 setPreviewSourceMode NOTIFY changed)
  Q_PROPERTY(bool previewSceneGraphTrace READ previewSceneGraphTrace WRITE
                 setPreviewSceneGraphTrace NOTIFY changed)
  Q_PROPERTY(bool previewCaptureMetrics READ previewCaptureMetrics CONSTANT)
  Q_PROPERTY(qreal windowDevicePixelRatio READ windowDevicePixelRatio NOTIFY
                 changed)

public:
  bool debugEnabled() const { return m_debugEnabled; }
  bool testHiDpiEnabled() const { return m_testHiDpiEnabled; }
  bool testBadgeLayerOff() const { return m_testBadgeLayerOff; }
  bool testBadgeShadowOff() const { return m_testBadgeShadowOff; }
  bool testBadgeCrisp() const { return m_testBadgeCrisp; }
  bool testBadgeCrispStable() const { return m_testBadgeCrispStable; }
  bool testBadgeMetrics() const { return m_testBadgeMetrics; }
  bool testBadgeSeparate() const { return m_testBadgeSeparate; }
  bool testBadgeOverlay() const { return m_testBadgeOverlay; }
  bool testBadgeTextQt() const { return m_testBadgeTextQt; }
  bool testBadgeTextNative() const { return m_testBadgeTextNative; }
  QString previewClipMode() const { return m_previewClipMode; }
  QString previewSourceMode() const { return m_previewSourceMode; }
  bool previewSceneGraphTrace() const { return m_previewSceneGraphTrace; }
  bool previewCaptureMetrics() const { return false; }
  qreal windowDevicePixelRatio() const { return 1.0; }

  void setDebugEnabled(bool value) { assign(m_debugEnabled, value); }
  void setTestHiDpiEnabled(bool value) { assign(m_testHiDpiEnabled, value); }
  void setTestBadgeLayerOff(bool value) { assign(m_testBadgeLayerOff, value); }
  void setTestBadgeShadowOff(bool value) {
    assign(m_testBadgeShadowOff, value);
  }
  void setTestBadgeCrisp(bool value) { assign(m_testBadgeCrisp, value); }
  void setTestBadgeCrispStable(bool value) {
    assign(m_testBadgeCrispStable, value);
  }
  void setTestBadgeMetrics(bool value) { assign(m_testBadgeMetrics, value); }
  void setTestBadgeSeparate(bool value) { assign(m_testBadgeSeparate, value); }
  void setTestBadgeOverlay(bool value) { assign(m_testBadgeOverlay, value); }
  void setTestBadgeTextQt(bool value) { assign(m_testBadgeTextQt, value); }
  void setTestBadgeTextNative(bool value) {
    assign(m_testBadgeTextNative, value);
  }
  void setPreviewClipMode(const QString &value) {
    if (m_previewClipMode == value)
      return;
    m_previewClipMode = value;
    Q_EMIT changed();
  }
  void setPreviewSourceMode(const QString &value) {
    if (m_previewSourceMode == value)
      return;
    m_previewSourceMode = value;
    Q_EMIT changed();
  }
  void setPreviewSceneGraphTrace(bool value) { assign(m_previewSceneGraphTrace, value); }

  Q_INVOKABLE void logQmlImage(const QString &, const QString &,
                               const QString &, const QString &, const QSize &,
                               const QSize &, qreal) const {}
  Q_INVOKABLE void logBadge(const QString &, int, const QString &,
                            const QRectF &, qreal, qreal, bool, bool, bool,
                            bool, bool, const QSize &) const {}
  Q_INVOKABLE void logBadgeMetrics(const QString &, const QString &, int, qreal,
                                   const QPointF &, const QPointF &,
                                   const QRectF &, qreal, qreal, qreal, qreal,
                                   qreal, qreal, qreal, qreal) const {}
  Q_INVOKABLE void logBadgeOverlayRenderMetrics(
      const QString &, int, const QString &, qreal, qreal, qreal, qreal,
      qreal, qreal, qreal, const QRectF &, const QRectF &, bool, bool, qreal,
      qreal, qreal) const {}

Q_SIGNALS:
  void changed();

private:
  void assign(bool &property, bool value) {
    if (property == value)
      return;
    property = value;
    Q_EMIT changed();
  }

  bool m_debugEnabled = false;
  bool m_testHiDpiEnabled = false;
  bool m_testBadgeLayerOff = false;
  bool m_testBadgeShadowOff = false;
  bool m_testBadgeCrisp = false;
  bool m_testBadgeCrispStable = false;
  bool m_testBadgeMetrics = false;
  bool m_testBadgeSeparate = false;
  bool m_testBadgeOverlay = false;
  bool m_testBadgeTextQt = false;
  bool m_testBadgeTextNative = false;
  QString m_previewClipMode;
  QString m_previewSourceMode;
  bool m_previewSceneGraphTrace = false;
};

class LauncherVariantListFixture final : public QObject {
  Q_OBJECT
  Q_PROPERTY(QVariantList folderTree READ folderTree CONSTANT)
  Q_PROPERTY(QVariantList applications READ applications CONSTANT)

public:
  QVariantList applications() const {
    return {QVariantMap{{QStringLiteral("id"), QStringLiteral("org.example.fixture.desktop")},
                        {QStringLiteral("type"), QStringLiteral("application")},
                        {QStringLiteral("name"), QStringLiteral("Fixture App")},
                        {QStringLiteral("icon"), QStringLiteral("applications-other")}}};
  }
  QVariantList folderTree() const {
    const QVariantMap app{{QStringLiteral("id"), QStringLiteral("org.example.fixture.desktop")},
                          {QStringLiteral("type"), QStringLiteral("application")},
                          {QStringLiteral("name"), QStringLiteral("Fixture App")},
                          {QStringLiteral("icon"), QStringLiteral("applications-other")}};
    return {QVariantMap{{QStringLiteral("id"), QStringLiteral("group:fixture")},
                        {QStringLiteral("type"), QStringLiteral("folder")},
                        {QStringLiteral("name"), QStringLiteral("Fixture Folder")},
                        {QStringLiteral("icon"), QStringLiteral("folder")},
                        {QStringLiteral("children"), QVariantList{app}},
                        {QStringLiteral("previewIcons"), QVariantList{app}}}};
  }
};

class ApplicationLauncherStateFixture final : public QObject {
  Q_OBJECT
  Q_PROPERTY(QObject *state READ state NOTIFY stateChanged)
  Q_PROPERTY(QObject *catalog READ catalog CONSTANT)
  Q_PROPERTY(QString captureDirectory READ captureDirectory CONSTANT)

public:
  ApplicationLauncherStateFixture() {
    m_previousConfigHome = qgetenv("XDG_CONFIG_HOME");
    m_hadConfigHome = qEnvironmentVariableIsSet("XDG_CONFIG_HOME");
    qputenv("XDG_CONFIG_HOME", m_configHome.path().toLocal8Bit());
    m_settings = std::make_unique<KDockWSettings>();
    m_settings->load();
    m_state = std::make_unique<kdockw::ApplicationLauncherState>(m_settings.get());
  }

  ~ApplicationLauncherStateFixture() override {
    m_state.reset();
    m_settings.reset();
    if (m_hadConfigHome)
      qputenv("XDG_CONFIG_HOME", m_previousConfigHome);
    else
      qunsetenv("XDG_CONFIG_HOME");
  }

  QObject *state() const { return m_state.get(); }
  QObject *catalog() const { return m_catalog.get(); }
  QString captureDirectory() const {
    return qEnvironmentVariable("KDOCKW_CAPTURE_DIR");
  }

  Q_INVOKABLE bool capture(QObject *object, const QString &path) const {
    auto *item = qobject_cast<QQuickItem *>(object);
    if (!item || path.isEmpty())
      return false;
    auto *window = item->window();
    if (!window)
      return false;
    window->update();
    const QImage image = window->grabWindow();
    return !image.isNull() && image.save(path);
  }

  Q_INVOKABLE void reset() {
    const QVariantList folders = m_state->launchpadFolders();
    for (const QVariant &value : folders)
      m_state->deleteLaunchpadFolder(value.toMap().value(QStringLiteral("id")).toString());
    const QStringList pins = m_state->pinnedApplicationIds();
    for (const QString &pin : pins)
      m_state->togglePinned(pin);
    m_state->setLaunchpadItemOrder({});
    m_settings->save();
  }

  Q_INVOKABLE void save() { m_settings->save(); }

  void initializeCatalog() {
    if (!m_catalog)
      m_catalog = std::make_unique<kdockw::ApplicationCatalog>();
  }

  Q_INVOKABLE void reload() {
    m_settings->save();
    m_state.reset();
    m_settings.reset();
    m_settings = std::make_unique<KDockWSettings>();
    m_settings->load();
    m_state = std::make_unique<kdockw::ApplicationLauncherState>(m_settings.get());
    Q_EMIT stateChanged();
  }

Q_SIGNALS:
  void stateChanged();

private:
  QTemporaryDir m_configHome;
  QByteArray m_previousConfigHome;
  bool m_hadConfigHome = false;
  std::unique_ptr<KDockWSettings> m_settings;
  std::unique_ptr<kdockw::ApplicationLauncherState> m_state;
  std::unique_ptr<kdockw::ApplicationCatalog> m_catalog;
};

class KDockWQmlTestSetup : public QObject {
  Q_OBJECT

public Q_SLOTS:
  void applicationAvailable() {
    if (qEnvironmentVariableIsSet("KDOCKW_USE_SYSTEM_THEME_ICONS")) {
      const QString theme = qEnvironmentVariable("KDOCKW_TEST_ICON_THEME", QStringLiteral("breeze"));
      QStringList iconPaths = QIcon::themeSearchPaths();
      iconPaths.prepend(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
                        + QStringLiteral("/icons"));
      iconPaths.prepend(QStringLiteral("/usr/local/share/icons"));
      iconPaths.prepend(QStringLiteral("/usr/share/icons"));
      QIcon::setThemeSearchPaths(iconPaths);
      if (!theme.isEmpty())
        QIcon::setThemeName(theme);
      QIcon::setFallbackThemeName(QStringLiteral("breeze"));
    }
    KLocalizedString::setApplicationDomain(QByteArrayLiteral("kdockw"));
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    KLocalizedString::addDomainLocaleDir(QByteArrayLiteral("kdockw"),
                                         QStringLiteral(KDOCKW_DIAGNOSTIC_LOCALE_DIR));
#endif
    if (qEnvironmentVariable("LANGUAGE").startsWith(QStringLiteral("ru"))) {
      KLocalizedString::setLanguages({QStringLiteral("ru")});
      const bool russianLocaleAvailable = std::setlocale(LC_MESSAGES, "ru_RU.UTF-8") != nullptr;
      qputenv("KDOCKW_TEST_RU_LOCALE_AVAILABLE", russianLocaleAvailable ? QByteArrayLiteral("1") : QByteArrayLiteral("0"));
    }
    KDockWQmlTest::registerMockTypes();
    if (qEnvironmentVariableIsSet("KDOCKW_TEST_REAL_APPLICATION_CATALOG"))
      applicationLauncherStateFixture.initializeCatalog();
    qmlRegisterType<kdockw::SpringZoomController>("com.thicking.kdockw", 1,
                                                  0, "SpringZoomController");
  }

  void qmlEngineAvailable(QQmlEngine *engine) {
    // Prepend so the mock modules shadow any installed real plugins.
    QStringList paths = engine->importPathList();
    paths.prepend(QStringLiteral(KDOCKW_QML_MOCKS_DIR));
    engine->setImportPathList(paths);
    engine->addImageProvider(QStringLiteral("previewframes"),
                             new MockPreviewFrameImageProvider);
    if (qEnvironmentVariableIsSet("KDOCKW_USE_SYSTEM_THEME_ICONS")) {
      engine->addImageProvider(QStringLiteral("icon"), new SystemThemeIconImageProvider);
    } else {
      engine->addImageProvider(QStringLiteral("icon"), new MockIconImageProvider);
    }
    engine->rootContext()->setContextProperty(QStringLiteral("IconDiagnostics"),
                                              &iconDiagnostics);
    engine->rootContext()->setContextProperty(QStringLiteral("SettingsWindow"),
                                              &zoomLayoutEngine);
    engine->rootContext()->setContextProperty(
        QStringLiteral("testRussianLocaleAvailable"),
        qEnvironmentVariableIntValue("KDOCKW_TEST_RU_LOCALE_AVAILABLE") == 1);
    engine->rootContext()->setContextProperty(QStringLiteral("LauncherVariantListFixture"),
                                              &launcherVariantListFixture);
    engine->rootContext()->setContextProperty(QStringLiteral("ApplicationLauncherStateFixture"),
                                              &applicationLauncherStateFixture);
    engine->rootContext()->setContextProperty(QStringLiteral("ApplicationCatalogFixture"),
                                              applicationLauncherStateFixture.catalog());

    auto *localizedContext = KLocalization::setupLocalizedContext(engine);
    localizedContext->setTranslationDomain(QStringLiteral("kdockw"));
  }

private:
  MockIconDiagnostics iconDiagnostics;
  LauncherVariantListFixture launcherVariantListFixture;
  ApplicationLauncherStateFixture applicationLauncherStateFixture;
  KDockWQmlTest::ZoomLayoutEngine zoomLayoutEngine;
};

QUICK_TEST_MAIN_WITH_SETUP(kdockw_qml, KDockWQmlTestSetup)

#include "main.moc"
