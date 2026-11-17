// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "models/mediaplayercontroller.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusVirtualObject>
#include <QElapsedTimer>
#include <QCoreApplication>
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
    QStringList methods;
    QVariantList lastArguments;

    QString introspect(const QString &) const override
    {
        return QStringLiteral("<node><interface name='org.freedesktop.DBus.Properties'><method name='GetAll'><arg direction='in' type='s'/><arg direction='out' type='a{sv}'/></method><signal name='PropertiesChanged'><arg type='s'/><arg type='a{sv}'/><arg type='as'/></signal></interface><interface name='org.mpris.MediaPlayer2.Player'/><interface name='org.mpris.MediaPlayer2'/></node>");
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
                    {QStringLiteral("Rate"), 1.0}, {QStringLiteral("Volume"), 0.6},
                    {QStringLiteral("Shuffle"), false}, {QStringLiteral("LoopStatus"), QStringLiteral("None")},
                    {QStringLiteral("CanControl"), true}, {QStringLiteral("CanPlay"), true},
                    {QStringLiteral("CanPause"), true}, {QStringLiteral("CanGoPrevious"), true},
                    {QStringLiteral("CanGoNext"), true}, {QStringLiteral("CanSeek"), true}};
                if (metadataAvailable) values.insert(QStringLiteral("Metadata"), metadata);
            } else if (iface == QLatin1String(kRoot)) {
                values = {{QStringLiteral("Identity"), QStringLiteral("Fixture Player")},
                    {QStringLiteral("DesktopEntry"), QStringLiteral("multimedia-player")},
                    {QStringLiteral("CanRaise"), true}};
            }
            connection.send(message.createReply({QVariant::fromValue(values)}));
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
            connection.send(message.createReply());
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
    REQUIRE(waitUntil([&] { return controller.title() == QStringLiteral("Second source"); }, 3000));
    CHECK(controller.selectedService() == secondService);
    REQUIRE(controller.previous());
    REQUIRE(waitUntil([&] { return secondFixture.methods.contains(QStringLiteral("Previous")); }, 3000));
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
