// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "models/mediaplayercontroller.h"
#include "models/systemvolumebackend.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusError>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QElapsedTimer>
#include <QSignalSpy>
#include <QCoreApplication>
#include <QTimer>
#include <QTest>

#include <catch2/catch_test_macros.hpp>

namespace
{
constexpr auto kPath = "/org/mpris/MediaPlayer2";
constexpr auto kProperties = "org.freedesktop.DBus.Properties";
constexpr auto kPlayer = "org.mpris.MediaPlayer2.Player";
constexpr auto kRoot = "org.mpris.MediaPlayer2";

class MprisFixture final : public QDBusVirtualObject
{
public:
    using QDBusVirtualObject::QDBusVirtualObject;
    QString title = QStringLiteral("First track");
    QString playbackStatus = QStringLiteral("Playing");
    bool metadataAvailable = true;
    bool includeVolume = true;
    bool canControl = true;
    bool ignoreVolumeWrites = false;
    QString volumeSetError;
    int volumeSignalDelayMs = 20;
    double volume = 0.6;
    QStringList methods;
    QVariantList lastArguments;

    QString introspect(const QString &) const override
    {
        return QStringLiteral("<node><interface name='org.freedesktop.DBus.Properties'><method name='GetAll'><arg direction='in' type='s'/><arg direction='out' type='a{sv}'/></method><method name='Get'><arg direction='in' type='s'/><arg direction='in' type='s'/><arg direction='out' type='v'/></method><signal name='PropertiesChanged'><arg type='s'/><arg type='a{sv}'/><arg type='as'/></signal></interface><interface name='org.mpris.MediaPlayer2.Player'/><interface name='org.mpris.MediaPlayer2'/></node>");
    }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        if (message.interface() == QLatin1String(kProperties) && message.member() == QLatin1String("GetAll")) {
            const QString iface = message.arguments().value(0).toString();
            QVariantMap values;
            if (iface == QLatin1String(kPlayer)) {
                QVariantMap metadata;
                if (metadataAvailable) {
                    metadata.insert(QStringLiteral("mpris:trackid"), QVariant::fromValue(QDBusObjectPath(QStringLiteral("/track/one"))));
                    metadata.insert(QStringLiteral("mpris:length"), QVariant::fromValue<qlonglong>(180'000'000));
                    metadata.insert(QStringLiteral("xesam:title"), title);
                    metadata.insert(QStringLiteral("xesam:artist"), QStringList{QStringLiteral("Fixture artist")});
                    metadata.insert(QStringLiteral("xesam:album"), QStringLiteral("Fixture album"));
                }
                values = {{QStringLiteral("PlaybackStatus"), playbackStatus},
                    {QStringLiteral("Position"), QVariant::fromValue<qlonglong>(12'000'000)},
                    {QStringLiteral("Rate"), 1.0},
                    {QStringLiteral("Shuffle"), false}, {QStringLiteral("LoopStatus"), QStringLiteral("None")},
                    {QStringLiteral("CanControl"), canControl}, {QStringLiteral("CanPlay"), true},
                    {QStringLiteral("CanPause"), true}, {QStringLiteral("CanGoPrevious"), true},
                    {QStringLiteral("CanGoNext"), true}, {QStringLiteral("CanSeek"), true}};
                if (includeVolume) values.insert(QStringLiteral("Volume"), volume);
                if (metadataAvailable) values.insert(QStringLiteral("Metadata"), metadata);
            } else if (iface == QLatin1String(kRoot)) {
                values = {{QStringLiteral("Identity"), QStringLiteral("Fixture Player")},
                    {QStringLiteral("DesktopEntry"), QStringLiteral("multimedia-player")},
                    {QStringLiteral("CanRaise"), true}};
            }
            connection.send(message.createReply({QVariant::fromValue(values)}));
            return true;
        }
        if (message.interface() == QLatin1String(kProperties) && message.member() == QLatin1String("Get")) {
            const QString iface = message.arguments().value(0).toString();
            const QString property = message.arguments().value(1).toString();
            if (iface != QLatin1String(kPlayer) || property != QLatin1String("Volume") || !includeVolume) {
                connection.send(message.createErrorReply(QStringLiteral("org.freedesktop.DBus.Error.UnknownProperty"),
                                                         QStringLiteral("fixture property unavailable")));
            } else {
                connection.send(message.createReply({QVariant::fromValue(QDBusVariant(volume))}));
            }
            return true;
        }
        if (message.interface() == QLatin1String(kPlayer)) {
            methods.append(message.member());
            lastArguments = message.arguments();
            connection.send(message.createReply());
            return true;
        }
        if (message.interface() == QLatin1String(kProperties) && message.member() == QLatin1String("Set")) {
            methods.append(QStringLiteral("Set:") + message.arguments().value(1).toString());
            lastArguments = message.arguments();
            if (message.arguments().value(1).toString() == QLatin1String("Volume")) {
                if (!volumeSetError.isEmpty()) {
                    connection.send(message.createErrorReply(volumeSetError, QStringLiteral("fixture volume set failed")));
                    return true;
                }
                if (!includeVolume) {
                    connection.send(message.createErrorReply(QStringLiteral("org.freedesktop.DBus.Error.UnknownProperty"),
                                                             QStringLiteral("fixture property unavailable")));
                    return true;
                }
                const double requested = message.arguments().value(2).value<QDBusVariant>().variant().toDouble();
                connection.send(message.createReply());
                if (!ignoreVolumeWrites) {
                    QTimer::singleShot(volumeSignalDelayMs, QCoreApplication::instance(), [this, connection, requested] {
                        volume = requested;
                        QDBusMessage signal = QDBusMessage::createSignal(QString::fromLatin1(kPath),
                            QString::fromLatin1(kProperties), QStringLiteral("PropertiesChanged"));
                        signal << QString::fromLatin1(kPlayer)
                               << QVariantMap{{QStringLiteral("Volume"), volume}} << QStringList{};
                        connection.send(signal);
                    });
                }
            } else {
                connection.send(message.createReply());
            }
            return true;
        }
        return false;
    }

    void changeTitle(const QDBusConnection &connection, const QString &newTitle)
    {
        title = newTitle;
        QVariantMap metadata;
        metadata.insert(QStringLiteral("mpris:trackid"), QVariant::fromValue(QDBusObjectPath(QStringLiteral("/track/one"))));
        metadata.insert(QStringLiteral("mpris:length"), QVariant::fromValue<qlonglong>(180'000'000));
        metadata.insert(QStringLiteral("xesam:title"), title);
        metadata.insert(QStringLiteral("xesam:artist"), QStringList{QStringLiteral("Fixture artist")});
        QDBusMessage signal = QDBusMessage::createSignal(QString::fromLatin1(kPath),
            QString::fromLatin1(kProperties), QStringLiteral("PropertiesChanged"));
        QVariantMap changed;
        changed.insert(QStringLiteral("Metadata"), metadata);
        signal << QString::fromLatin1(kPlayer) << changed << QStringList{};
        connection.send(signal);
    }

    void invalidateMetadata(const QDBusConnection &connection)
    {
        metadataAvailable = false;
        QDBusMessage signal = QDBusMessage::createSignal(QString::fromLatin1(kPath),
            QString::fromLatin1(kProperties), QStringLiteral("PropertiesChanged"));
        signal << QString::fromLatin1(kPlayer) << QVariantMap{} << QStringList{QStringLiteral("Metadata")};
        connection.send(signal);
    }

    void invalidatePlaybackStatus(const QDBusConnection &connection)
    {
        QDBusMessage signal = QDBusMessage::createSignal(QString::fromLatin1(kPath),
            QString::fromLatin1(kProperties), QStringLiteral("PropertiesChanged"));
        signal << QString::fromLatin1(kPlayer) << QVariantMap{} << QStringList{QStringLiteral("PlaybackStatus")};
        connection.send(signal);
    }
};

class FakeSystemVolumeBackend final : public kdockw::SystemVolumeBackend
{
public:
    using SystemVolumeBackend::SystemVolumeBackend;

    void startMonitoring() override
    {
        if (!monitoring) {
            monitoring = true;
            ++startCount;
        }
    }

    void setVolume(double value) override
    {
        writes.append(value);
        publishState(available(), value, muted(), defaultOutput());
    }

    void publish(bool available, double value, bool muted, const QString &output)
    {
        publishState(available, value, muted, output);
    }

    QList<double> writes;
    bool monitoring = false;
    int startCount = 0;
};

class MprisRegistration final
{
public:
    MprisRegistration(QDBusConnection bus, QString service, QString connectionName = {})
        : m_bus(std::move(bus))
        , m_service(std::move(service))
        , m_connectionName(std::move(connectionName))
    {
    }

    ~MprisRegistration()
    {
        m_bus.unregisterObject(QString::fromLatin1(kPath));
        m_bus.unregisterService(m_service);
        if (!m_connectionName.isEmpty())
            QDBusConnection::disconnectFromBus(m_connectionName);
    }

private:
    QDBusConnection m_bus;
    QString m_service;
    QString m_connectionName;
};

template<typename Predicate>
bool waitUntil(Predicate predicate, int timeoutMs)
{
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < timeoutMs) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        if (predicate()) return true;
        QTest::qWait(5);
    }
    QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    return predicate();
}

TEST_CASE("MPRIS source model selects among concurrent services and targets the selected owner", "[media-player][mpris-integration]")
{
    QDBusConnection primaryBus = QDBusConnection::sessionBus();
    if (!primaryBus.isConnected()) SKIP("A D-Bus session bus is required for the MPRIS fixture test");

    const QString suffix = QString::number(QCoreApplication::applicationPid());
    const QString firstService = QStringLiteral("org.mpris.MediaPlayer2.kdockw_first_%1").arg(suffix);
    const QString secondService = QStringLiteral("org.mpris.MediaPlayer2.kdockw_second_%1").arg(suffix);
    const QString secondConnectionName = QStringLiteral("kdockw-mpris-second-%1").arg(suffix);
    QDBusConnection secondBus = QDBusConnection::connectToBus(QDBusConnection::SessionBus,
                                                               secondConnectionName);
    REQUIRE(secondBus.isConnected());
    REQUIRE(primaryBus.registerService(firstService));
    MprisFixture firstFixture;
    firstFixture.title = QStringLiteral("First source");
    REQUIRE(primaryBus.registerVirtualObject(QString::fromLatin1(kPath), &firstFixture,
                                             QDBusConnection::SingleNode));
    MprisRegistration firstRegistration(primaryBus, firstService);

    REQUIRE(secondBus.registerService(secondService));
    MprisFixture secondFixture;
    secondFixture.title = QStringLiteral("Second source");
    secondFixture.playbackStatus = QStringLiteral("Paused");
    REQUIRE(secondBus.registerVirtualObject(QString::fromLatin1(kPath), &secondFixture,
                                            QDBusConnection::SingleNode));
    MprisRegistration secondRegistration(secondBus, secondService, secondConnectionName);

    kdockw::MediaPlayerController controller;
    REQUIRE(waitUntil([&] {
        bool firstFound = false;
        bool secondFound = false;
        for (int row = 0; row < controller.rowCount(); ++row) {
            firstFound = firstFound || controller.serviceAt(row) == firstService;
            secondFound = secondFound || controller.serviceAt(row) == secondService;
        }
        return firstFound && secondFound;
    }, 3000));
    REQUIRE(controller.selectSession(secondService));
    secondFixture.invalidatePlaybackStatus(secondBus);
    const int firstRow = [&] {
        for (int row = 0; row < controller.rowCount(); ++row)
            if (controller.serviceAt(row) == firstService) return row;
        return -1;
    }();
    REQUIRE(firstRow >= 0);
    REQUIRE(waitUntil([&] {
        return controller.data(controller.index(firstRow), kdockw::MediaPlayerController::PlaybackStatusRole).toString()
            == QStringLiteral("Playing")
            && controller.data(controller.index(firstRow), kdockw::MediaPlayerController::TitleRole).toString()
                == QStringLiteral("First source");
    }, 3000));
    const int secondRow = [&] {
        for (int row = 0; row < controller.rowCount(); ++row)
            if (controller.serviceAt(row) == secondService) return row;
        return -1;
    }();
    REQUIRE(secondRow >= 0);
    REQUIRE(waitUntil([&] {
        return controller.data(controller.index(secondRow), kdockw::MediaPlayerController::PlaybackStatusRole).toString()
            == QStringLiteral("Paused");
    }, 3000));
    CHECK(controller.selectedService() == secondService);
    CHECK(waitUntil([&] { return controller.title() == QStringLiteral("Second source"); }, 3000));
    CHECK(controller.selectedService() == secondService);
    REQUIRE(controller.previous());
    REQUIRE(waitUntil([&] { return secondFixture.methods.contains(QStringLiteral("Previous")); }, 3000));
    secondFixture.volumeSignalDelayMs = 180;
    REQUIRE(controller.setVolume(0.22));
    REQUIRE(waitUntil([&] { return secondFixture.methods.contains(QStringLiteral("Set:Volume")); }, 1000));
    REQUIRE(controller.selectSession(firstService));
    QTest::qWait(300);
    CHECK(controller.selectedService() == firstService);
    CHECK(qAbs(controller.volume() - firstFixture.volume) < 0.02);
    CHECK(firstFixture.methods.empty());
}
}

TEST_CASE("MPRIS backend discovers a session, follows properties, and sends guarded commands", "[media-player][mpris-integration]")
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) SKIP("A D-Bus session bus is required for the MPRIS fixture test");

    const QString service = QStringLiteral("org.mpris.MediaPlayer2.kdockw_test_%1").arg(QCoreApplication::applicationPid());
    REQUIRE(bus.registerService(service));
    MprisFixture fixture;
    REQUIRE(bus.registerVirtualObject(QString::fromLatin1(kPath), &fixture,
                                      QDBusConnection::SingleNode));
    MprisRegistration registration(bus, service);

    {
        kdockw::MediaPlayerController controller;
        REQUIRE(waitUntil([&] {
            for (int row = 0; row < controller.rowCount(); ++row)
                if (controller.serviceAt(row) == service) return true;
            return false;
        }, 3000));
        REQUIRE(controller.selectSession(service));
        REQUIRE(waitUntil([&] { return controller.title() == QStringLiteral("First track"); }, 3000));
        CHECK(controller.identity() == QStringLiteral("Fixture Player"));
        CHECK(controller.artist() == QStringLiteral("Fixture artist"));
        CHECK(controller.durationUs() == 180'000'000);
        CHECK(controller.canSeek());
        CHECK(controller.canGoNext());

        fixture.changeTitle(bus, QStringLiteral("Updated track"));
        REQUIRE(waitUntil([&] { return controller.title() == QStringLiteral("Updated track"); }, 3000));
        fixture.invalidateMetadata(bus);
        REQUIRE(waitUntil([&] { return controller.title().isEmpty() && controller.durationUs() == -1; }, 3000));
        CHECK_FALSE(controller.seekTo(56'000'000, QStringLiteral("/track/one")));
        fixture.metadataAvailable = true;
        fixture.changeTitle(bus, QStringLiteral("Restored track"));
        REQUIRE(waitUntil([&] { return controller.title() == QStringLiteral("Restored track"); }, 3000));
        CHECK(controller.playPause());
        REQUIRE(waitUntil([&] { return fixture.methods.contains(QStringLiteral("PlayPause")); }, 3000));
        CHECK(controller.seekTo(55'000'000, QStringLiteral("/track/one")));
        REQUIRE(waitUntil([&] { return fixture.methods.contains(QStringLiteral("SetPosition")); }, 3000));
        CHECK(fixture.lastArguments.value(0).value<QDBusObjectPath>().path() == QStringLiteral("/track/one"));
        CHECK(fixture.lastArguments.value(1).toLongLong() == 55'000'000);
        CHECK_FALSE(controller.seekTo(56'000'000, QStringLiteral("/track/stale")));
    }

}

TEST_CASE("MPRIS volume remains the only target in Player Only and Automatic modes", "[media-player][mpris-integration][volume]")
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) SKIP("A D-Bus session bus is required for the MPRIS fixture test");
    const QString service = QStringLiteral("org.mpris.MediaPlayer2.kdockw_volume_supported_%1").arg(QCoreApplication::applicationPid());
    REQUIRE(bus.registerService(service));
    MprisFixture fixture;
    REQUIRE(bus.registerVirtualObject(QString::fromLatin1(kPath), &fixture, QDBusConnection::SingleNode));
    MprisRegistration registration(bus, service);
    FakeSystemVolumeBackend system;
    system.publish(true, 0.72, false, QStringLiteral("output-a"));

    kdockw::MediaPlayerController controller(nullptr, &system);
    REQUIRE(waitUntil([&] { return controller.selectedService() == service && controller.activeVolumeSource() == QLatin1String("player"); }, 3000));
    controller.setVolumeControlMode(1);
    REQUIRE(controller.setVolume(0.35));
    REQUIRE(waitUntil([&] { return qAbs(fixture.volume - 0.35) < 0.01 && qAbs(controller.volume() - 0.35) < 0.02; }, 1500));
    CHECK(controller.activeVolumeSource() == QLatin1String("player"));
    CHECK(system.writes.isEmpty());

    controller.setVolumeControlMode(0);
    CHECK(system.startCount == 0);
    REQUIRE(controller.setVolume(0.45));
    REQUIRE(waitUntil([&] { return qAbs(fixture.volume - 0.45) < 0.01 && qAbs(controller.volume() - 0.45) < 0.02; }, 1500));
    CHECK(controller.activeVolumeSource() == QLatin1String("player"));
    CHECK(system.writes.isEmpty());
}

TEST_CASE("Writable MPRIS Volume is independent of the aggregate CanControl flag", "[media-player][mpris-integration][volume]")
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) SKIP("A D-Bus session bus is required for the MPRIS fixture test");
    const QString service = QStringLiteral("org.mpris.MediaPlayer2.kdockw_volume_can_control_false_%1")
                                .arg(QCoreApplication::applicationPid());
    REQUIRE(bus.registerService(service));
    MprisFixture fixture;
    fixture.canControl = false;
    REQUIRE(bus.registerVirtualObject(QString::fromLatin1(kPath), &fixture, QDBusConnection::SingleNode));
    MprisRegistration registration(bus, service);
    FakeSystemVolumeBackend system;
    system.publish(true, 0.72, false, QStringLiteral("output-a"));
    kdockw::MediaPlayerController controller(nullptr, &system);
    controller.setVolumeControlMode(0);

    REQUIRE(waitUntil([&] { return controller.selectedService() == service
        && controller.activeVolumeSource() == QLatin1String("player"); }, 3000));
    REQUIRE(controller.setVolume(0.33));
    REQUIRE(waitUntil([&] { return qAbs(fixture.volume - 0.33) < 0.01; }, 1000));
    CHECK(system.writes.isEmpty());
}

TEST_CASE("Automatic mode falls back only after successful but ignored MPRIS writes", "[media-player][mpris-integration][volume]")
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) SKIP("A D-Bus session bus is required for the MPRIS fixture test");
    const QString service = QStringLiteral("org.mpris.MediaPlayer2.kdockw_volume_ignored_%1").arg(QCoreApplication::applicationPid());
    REQUIRE(bus.registerService(service));
    MprisFixture fixture;
    fixture.ignoreVolumeWrites = true;
    REQUIRE(bus.registerVirtualObject(QString::fromLatin1(kPath), &fixture, QDBusConnection::SingleNode));
    MprisRegistration registration(bus, service);
    FakeSystemVolumeBackend system;
    system.publish(true, 0.68, false, QStringLiteral("default-output"));

    kdockw::MediaPlayerController controller(nullptr, &system);
    controller.setVolumeControlMode(0);
    REQUIRE(waitUntil([&] { return controller.selectedService() == service && controller.activeVolumeSource() == QLatin1String("player"); }, 3000));
    REQUIRE(controller.setVolume(0.30));
    CHECK(system.writes.isEmpty());
    REQUIRE(waitUntil([&] { return controller.activeVolumeSource() == QLatin1String("system"); }, 2500));
    CHECK(system.startCount == 1);
    CHECK(qAbs(controller.volume() - 0.68) < 0.02);
    CHECK(system.writes.isEmpty());

    REQUIRE(controller.setVolume(0.42));
    REQUIRE(waitUntil([&] { return system.writes.size() == 1; }, 500));
    CHECK(qAbs(system.writes.constFirst() - 0.42) < 0.001);
    REQUIRE(controller.setVolume(1.2));
    REQUIRE(waitUntil([&] { return system.writes.size() == 2; }, 500));
    CHECK(system.writes.constLast() == 1.0);
    CHECK(fixture.methods.count(QStringLiteral("Set:Volume")) == 1);
}

TEST_CASE("Missing MPRIS Volume and transient errors never cross routing modes", "[media-player][mpris-integration][volume]")
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) SKIP("A D-Bus session bus is required for the MPRIS fixture test");
    const QString service = QStringLiteral("org.mpris.MediaPlayer2.kdockw_volume_missing_%1").arg(QCoreApplication::applicationPid());
    REQUIRE(bus.registerService(service));
    MprisFixture fixture;
    fixture.includeVolume = false;
    REQUIRE(bus.registerVirtualObject(QString::fromLatin1(kPath), &fixture, QDBusConnection::SingleNode));
    MprisRegistration registration(bus, service);
    FakeSystemVolumeBackend system;
    system.publish(true, 0.55, false, QStringLiteral("default-output"));
    kdockw::MediaPlayerController controller(nullptr, &system);

    REQUIRE(waitUntil([&] { return controller.selectedService() == service && controller.activeVolumeSource() == QLatin1String("unavailable"); }, 3000));
    CHECK_FALSE(controller.setVolume(0.40));
    controller.setVolumeControlMode(0);
    CHECK(controller.activeVolumeSource() == QLatin1String("system"));
    REQUIRE(controller.setVolume(0.40));
    REQUIRE(waitUntil([&] { return system.writes.size() == 1; }, 500));
    controller.setVolumeControlMode(1);
    CHECK(controller.activeVolumeSource() == QLatin1String("unavailable"));
    CHECK_FALSE(controller.setVolume(0.25));
    CHECK(system.writes.size() == 1);
}

TEST_CASE("A transient MPRIS Set error does not trigger automatic fallback", "[media-player][mpris-integration][volume]")
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) SKIP("A D-Bus session bus is required for the MPRIS fixture test");
    const QString service = QStringLiteral("org.mpris.MediaPlayer2.kdockw_volume_error_%1").arg(QCoreApplication::applicationPid());
    REQUIRE(bus.registerService(service));
    MprisFixture fixture;
    fixture.volumeSetError = QStringLiteral("org.freedesktop.DBus.Error.Failed");
    REQUIRE(bus.registerVirtualObject(QString::fromLatin1(kPath), &fixture, QDBusConnection::SingleNode));
    MprisRegistration registration(bus, service);
    FakeSystemVolumeBackend system;
    system.publish(true, 0.61, false, QStringLiteral("default-output"));
    kdockw::MediaPlayerController controller(nullptr, &system);
    controller.setVolumeControlMode(0);
    REQUIRE(waitUntil([&] { return controller.selectedService() == service && controller.activeVolumeSource() == QLatin1String("player"); }, 3000));
    REQUIRE(controller.setVolume(0.20));
    REQUIRE(waitUntil([&] { return fixture.methods.contains(QStringLiteral("Set:Volume")); }, 500));
    QTest::qWait(100);
    CHECK(controller.activeVolumeSource() == QLatin1String("player"));
    CHECK(system.writes.isEmpty());
}

TEST_CASE("Delayed MPRIS Volume updates and rapid changes are generation-safe", "[media-player][mpris-integration][volume]")
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) SKIP("A D-Bus session bus is required for the MPRIS fixture test");
    const QString service = QStringLiteral("org.mpris.MediaPlayer2.kdockw_volume_delayed_%1").arg(QCoreApplication::applicationPid());
    REQUIRE(bus.registerService(service));
    MprisFixture fixture;
    fixture.volumeSignalDelayMs = 220;
    REQUIRE(bus.registerVirtualObject(QString::fromLatin1(kPath), &fixture, QDBusConnection::SingleNode));
    MprisRegistration registration(bus, service);
    FakeSystemVolumeBackend system;
    system.publish(true, 0.63, false, QStringLiteral("default-output"));
    kdockw::MediaPlayerController controller(nullptr, &system);
    controller.setVolumeControlMode(0);
    REQUIRE(waitUntil([&] { return controller.selectedService() == service && controller.activeVolumeSource() == QLatin1String("player"); }, 3000));

    REQUIRE(controller.setVolume(0.40));
    REQUIRE(controller.setVolume(0.30));
    REQUIRE(waitUntil([&] { return qAbs(fixture.volume - 0.30) < 0.01 && qAbs(controller.volume() - 0.30) < 0.02; }, 1600));
    CHECK(controller.activeVolumeSource() == QLatin1String("player"));
    CHECK(fixture.methods.count(QStringLiteral("Set:Volume")) == 2);
    CHECK(system.writes.isEmpty());
}

TEST_CASE("Automatic volume support is isolated when the selected MPRIS session changes", "[media-player][mpris-integration][volume]")
{
    QDBusConnection primaryBus = QDBusConnection::sessionBus();
    if (!primaryBus.isConnected()) SKIP("A D-Bus session bus is required for the MPRIS fixture test");

    const QString suffix = QString::number(QCoreApplication::applicationPid());
    const QString ignoredService = QStringLiteral("org.mpris.MediaPlayer2.kdockw_volume_switch_ignored_%1").arg(suffix);
    const QString supportedService = QStringLiteral("org.mpris.MediaPlayer2.kdockw_volume_switch_supported_%1").arg(suffix);
    const QString secondConnectionName = QStringLiteral("kdockw-volume-switch-%1").arg(suffix);
    QDBusConnection secondBus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, secondConnectionName);
    REQUIRE(secondBus.isConnected());

    REQUIRE(primaryBus.registerService(ignoredService));
    MprisFixture ignoredFixture;
    ignoredFixture.ignoreVolumeWrites = true;
    REQUIRE(primaryBus.registerVirtualObject(QString::fromLatin1(kPath), &ignoredFixture, QDBusConnection::SingleNode));
    MprisRegistration ignoredRegistration(primaryBus, ignoredService);

    REQUIRE(secondBus.registerService(supportedService));
    MprisFixture supportedFixture;
    supportedFixture.volume = 0.45;
    REQUIRE(secondBus.registerVirtualObject(QString::fromLatin1(kPath), &supportedFixture, QDBusConnection::SingleNode));
    MprisRegistration supportedRegistration(secondBus, supportedService, secondConnectionName);

    FakeSystemVolumeBackend system;
    system.publish(true, 0.72, false, QStringLiteral("default-output"));
    kdockw::MediaPlayerController controller(nullptr, &system);
    REQUIRE(waitUntil([&] {
        bool ignoredFound = false;
        bool supportedFound = false;
        for (int row = 0; row < controller.rowCount(); ++row) {
            ignoredFound = ignoredFound || controller.serviceAt(row) == ignoredService;
            supportedFound = supportedFound || controller.serviceAt(row) == supportedService;
        }
        return ignoredFound && supportedFound;
    }, 3000));

    REQUIRE(controller.selectSession(ignoredService));
    REQUIRE(waitUntil([&] { return controller.activeVolumeSource() == QLatin1String("player"); }, 1000));
    controller.setVolumeControlMode(0);
    REQUIRE(controller.setVolume(0.30));
    REQUIRE(controller.selectSession(supportedService));
    REQUIRE(waitUntil([&] {
        return controller.selectedService() == supportedService
            && controller.activeVolumeSource() == QLatin1String("player");
    }, 1000));
    CHECK(controller.activeVolumeSource() == QLatin1String("player"));
    CHECK(system.startCount == 0);
    REQUIRE(waitUntil([&] { return ignoredFixture.methods.contains(QStringLiteral("Set:Volume")); }, 1000));
    QTest::qWait(1100);

    CHECK(controller.selectedService() == supportedService);
    CHECK(controller.activeVolumeSource() == QLatin1String("player"));
    CHECK(system.startCount == 0);
    CHECK(system.writes.isEmpty());

    REQUIRE(controller.selectSession(ignoredService));
    CHECK(controller.activeVolumeSource() == QLatin1String("system"));
    CHECK(system.startCount == 1);
    CHECK(qAbs(controller.volume() - 0.72) < 0.02);
}

TEST_CASE("System mode tracks external output, mute, and default-device changes without MPRIS writes", "[media-player][mpris-integration][volume]")
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) SKIP("A D-Bus session bus is required for the MPRIS fixture test");
    const QString service = QStringLiteral("org.mpris.MediaPlayer2.kdockw_volume_system_%1").arg(QCoreApplication::applicationPid());
    REQUIRE(bus.registerService(service));
    MprisFixture fixture;
    REQUIRE(bus.registerVirtualObject(QString::fromLatin1(kPath), &fixture, QDBusConnection::SingleNode));
    MprisRegistration registration(bus, service);
    FakeSystemVolumeBackend system;
    system.publish(true, 0.77, false, QStringLiteral("output-a"));
    kdockw::MediaPlayerController controller(nullptr, &system);
    QSignalSpy volumeSpy(&controller, &kdockw::MediaPlayerController::volumeChanged);
    controller.setVolumeControlMode(2);
    REQUIRE(waitUntil([&] {
        for (int row = 0; row < controller.rowCount(); ++row) {
            if (controller.serviceAt(row) == service) {
                return true;
            }
        }
        return false;
    }, 3000));
    REQUIRE(controller.selectSession(service));
    CHECK(controller.selectedService() == service);
    CHECK(controller.activeVolumeSource() == QLatin1String("system"));
    CHECK(qAbs(controller.volume() - 0.77) < 0.01);
    REQUIRE(controller.setVolume(0.40));
    CHECK(system.writes.size() == 1);
    CHECK(fixture.methods.count(QStringLiteral("Set:Volume")) == 0);

    system.publish(true, 0.25, true, QStringLiteral("output-b"));
    CHECK(qAbs(controller.volume() - 0.25) < 0.01);
    CHECK(controller.volumeMuted());
    CHECK(system.defaultOutput() == QLatin1String("output-b"));
    CHECK(volumeSpy.count() > 0);
}

TEST_CASE("Unavailable system audio keeps System mode inert", "[media-player][mpris-integration][volume]")
{
    FakeSystemVolumeBackend system;
    system.publish(false, 0.0, false, {});
    kdockw::MediaPlayerController controller(nullptr, &system);
    controller.setVolumeControlMode(2);
    CHECK(controller.activeVolumeSource() == QLatin1String("unavailable"));
    CHECK_FALSE(controller.volumeControlAvailable());
    CHECK_FALSE(controller.setVolume(0.5));
    CHECK(system.writes.isEmpty());
}

TEST_CASE("Missing pactl leaves system volume unavailable without blocking", "[media-player][volume]")
{
    kdockw::PactlSystemVolumeBackend backend(QStringLiteral("/no/such/kdockw-test-pactl"));
    CHECK_FALSE(backend.available());
    backend.startMonitoring();
    QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
    CHECK_FALSE(backend.available());
}
