// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "mediaplayercontroller.h"

#include <QDBusMessage>
#include <QDBusArgument>
#include <QDBusError>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QLoggingCategory>

#include <algorithm>
#include <cmath>
#include <cstring>

Q_LOGGING_CATEGORY(lcMediaPlayer, "kdockw.media")

namespace kdockw
{

namespace
{
constexpr auto kMprisPrefix = "org.mpris.MediaPlayer2.";
constexpr auto kMprisPath = "/org/mpris/MediaPlayer2";
constexpr auto kPlayerInterface = "org.mpris.MediaPlayer2.Player";
constexpr auto kRootInterface = "org.mpris.MediaPlayer2";
constexpr auto kPropertiesInterface = "org.freedesktop.DBus.Properties";
constexpr auto kBusService = "org.freedesktop.DBus";
constexpr auto kBusPath = "/org/freedesktop/DBus";
constexpr qint64 kPositionMaximumUs = 7LL * 24 * 60 * 60 * 1'000'000;

QString objectPathString(const QVariant &value)
{
    if (value.metaType() == QMetaType::fromType<QDBusObjectPath>()) {
        return value.value<QDBusObjectPath>().path();
    }
    return value.toString();
}

QVariant unbox(const QVariant &value)
{
    if (value.metaType() == QMetaType::fromType<QDBusVariant>()) {
        return value.value<QDBusVariant>().variant();
    }
    return value;
}

QVariantMap variantMap(const QVariant &value)
{
    const QVariant unboxed = unbox(value);
    if (unboxed.metaType() == QMetaType::fromType<QDBusArgument>()) {
        QVariantMap result;
        unboxed.value<QDBusArgument>() >> result;
        return result;
    }
    return unboxed.toMap();
}
} // namespace

MediaPlayerController::MediaPlayerController(QObject *parent, SystemVolumeBackend *systemVolumeBackend)
    : QAbstractListModel(parent)
    , m_bus(QDBusConnection::sessionBus())
    , m_systemVolumeBackend(systemVolumeBackend ? systemVolumeBackend : new PactlSystemVolumeBackend({}, this))
{
    m_clock.start();
    m_progressTimer.setInterval(250);
    m_progressTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_progressTimer, &QTimer::timeout, this, &MediaPlayerController::positionChanged);
    m_volumeVerificationTimer.setSingleShot(true);
    m_volumeVerificationTimer.setInterval(900);
    connect(&m_volumeVerificationTimer, &QTimer::timeout, this, [this] {
        if (m_pendingVolumeWrite) {
            requestVolumeReadback(*m_pendingVolumeWrite, true);
        }
    });
    connect(m_systemVolumeBackend, &SystemVolumeBackend::stateChanged, this, [this] {
        notifyVolumeStateChanged();
    });
    m_stoppedHideTimer.setSingleShot(true);
    m_stoppedHideTimer.setInterval(m_stoppedHideDelayMs);
    connect(&m_stoppedHideTimer, &QTimer::timeout, this, [this] {
        m_manualSelection = false;
        Q_EMIT selectionModeChanged();
        selectService({}, false);
        updateAutomaticSelection();
    });

    if (!m_bus.isConnected()) {
        qCWarning(lcMediaPlayer) << "The session D-Bus is unavailable; MPRIS discovery is disabled";
        return;
    }

    const bool connected = m_bus.connect(QString::fromLatin1(kBusService),
                                         QString::fromLatin1(kBusPath),
                                         QStringLiteral("org.freedesktop.DBus"),
                                         QStringLiteral("NameOwnerChanged"),
                                         this,
                                         SLOT(onNameOwnerChanged(QString,QString,QString)));
    if (!connected) {
        qCWarning(lcMediaPlayer) << "Could not subscribe to D-Bus owner changes" << m_bus.lastError().message();
    }
    enumerateServices();
}

MediaPlayerController::~MediaPlayerController()
{
    m_bus.disconnect(QString::fromLatin1(kBusService), QString::fromLatin1(kBusPath),
                     QStringLiteral("org.freedesktop.DBus"), QStringLiteral("NameOwnerChanged"),
                     this, SLOT(onNameOwnerChanged(QString,QString,QString)));
    for (const Session &session : std::as_const(m_sessions)) {
        m_bus.disconnect(session.service, QString::fromLatin1(kMprisPath),
                         QString::fromLatin1(kPropertiesInterface), QStringLiteral("PropertiesChanged"),
                         this, SLOT(onPropertiesChanged(QString,QVariantMap,QStringList,QDBusMessage)));
        m_bus.disconnect(session.service, QString::fromLatin1(kMprisPath),
                         QString::fromLatin1(kPlayerInterface), QStringLiteral("Seeked"),
                         this, SLOT(onSeeked(qlonglong,QDBusMessage)));
    }
}

int MediaPlayerController::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_sessions.size();
}

QAbstractItemModel *MediaPlayerController::sessions() { return this; }

QString MediaPlayerController::serviceAt(int row) const
{
    return row >= 0 && row < m_sessions.size() ? m_sessions.at(row).service : QString();
}

void MediaPlayerController::setProgressRequested(QObject *client, bool requested)
{
    if (!client) return;
    if (requested) {
        if (m_progressClients.contains(client)) return;
        m_progressClients.insert(client);
        connect(client, &QObject::destroyed, this, [this, client] {
            m_progressClients.remove(client);
            updateProgressTimer();
        });
    } else {
        m_progressClients.remove(client);
    }
    updateProgressTimer();
}

QVariant MediaPlayerController::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_sessions.size()) return {};
    const Session &session = m_sessions.at(index.row());
    switch (role) {
    case Qt::DisplayRole: return session.identity;
    case ServiceRole: return session.service;
    case IdentityRole: return session.identity;
    case DesktopEntryRole: return session.desktopEntry;
    case TitleRole: return session.title;
    case PlaybackStatusRole: return session.playbackStatus;
    case SelectedRole: return session.service == m_selectedService;
    default: return {};
    }
}

QHash<int, QByteArray> MediaPlayerController::roleNames() const
{
    return {{Qt::DisplayRole, "display"}, {ServiceRole, "service"}, {IdentityRole, "identity"},
            {DesktopEntryRole, "desktopEntry"}, {TitleRole, "title"},
            {PlaybackStatusRole, "playbackStatus"}, {SelectedRole, "selected"}};
}

bool MediaPlayerController::available() const { return m_available; }
bool MediaPlayerController::autoVisibility() const { return m_autoVisibility; }
bool MediaPlayerController::showPaused() const { return m_showPaused; }
int MediaPlayerController::stoppedHideDelayMs() const { return m_stoppedHideDelayMs; }
QString MediaPlayerController::selectedService() const { return m_selectedService; }

#define KDOCKW_CURRENT_GETTER(type, name, field, fallback) \
    type MediaPlayerController::name() const { const Session *s = selected(); return s ? s->field : fallback; }
KDOCKW_CURRENT_GETTER(QString, identity, identity, QString())
KDOCKW_CURRENT_GETTER(QString, desktopEntry, desktopEntry, QString())
KDOCKW_CURRENT_GETTER(QString, title, title, QString())
KDOCKW_CURRENT_GETTER(QString, artist, artist, QString())
KDOCKW_CURRENT_GETTER(QString, album, album, QString())
KDOCKW_CURRENT_GETTER(QString, playbackStatus, playbackStatus, QString())
KDOCKW_CURRENT_GETTER(QString, loopStatus, loopStatus, QStringLiteral("None"))
KDOCKW_CURRENT_GETTER(QString, trackId, trackId, QString())
KDOCKW_CURRENT_GETTER(QUrl, artUrl, artUrl, QUrl())
KDOCKW_CURRENT_GETTER(QUrl, mediaUrl, mediaUrl, QUrl())
KDOCKW_CURRENT_GETTER(qint64, durationUs, durationUs, qint64(-1))
KDOCKW_CURRENT_GETTER(double, rate, rate, 1.0)
KDOCKW_CURRENT_GETTER(bool, shuffle, shuffle, false)
KDOCKW_CURRENT_GETTER(bool, canControl, canControl, false)
KDOCKW_CURRENT_GETTER(bool, canPlay, canPlay, false)
KDOCKW_CURRENT_GETTER(bool, canPause, canPause, false)
KDOCKW_CURRENT_GETTER(bool, canGoPrevious, canGoPrevious, false)
KDOCKW_CURRENT_GETTER(bool, canGoNext, canGoNext, false)
KDOCKW_CURRENT_GETTER(bool, canSeek, canSeek, false)
KDOCKW_CURRENT_GETTER(bool, canRaise, canRaise, false)
#undef KDOCKW_CURRENT_GETTER

QString MediaPlayerController::resolvedVolumeSource() const
{
    const Session *session = selected();
    const bool playerVolumeReady = session && session->playerPropertiesLoaded
        && session->volumePropertyPresent
        && session->volumeWriteSupport != VolumeWriteSupport::Unsupported;
    const bool playerVolumeUnsupported = session && session->playerPropertiesLoaded
        && (!session->volumePropertyPresent || session->volumeWriteSupport == VolumeWriteSupport::Unsupported);

    if (m_volumeControlMode == 2) {
        return m_systemVolumeBackend && m_systemVolumeBackend->available() ? QStringLiteral("system") : QStringLiteral("unavailable");
    }
    if (m_volumeControlMode == 1) {
        return playerVolumeReady ? QStringLiteral("player") : QStringLiteral("unavailable");
    }
    if (playerVolumeReady) {
        return QStringLiteral("player");
    }
    if (playerVolumeUnsupported && m_systemVolumeBackend && m_systemVolumeBackend->available()) {
        return QStringLiteral("system");
    }
    return QStringLiteral("unavailable");
}

double MediaPlayerController::volume() const
{
    const QString source = resolvedVolumeSource();
    if (source == QLatin1String("system")) {
        return m_systemVolumeBackend ? m_systemVolumeBackend->volume() : 0.0;
    }
    if (source == QLatin1String("player")) {
        const Session *session = selected();
        return session ? session->volume : 0.0;
    }
    return 0.0;
}

QString MediaPlayerController::activeVolumeSource() const { return resolvedVolumeSource(); }
bool MediaPlayerController::volumeControlAvailable() const { return resolvedVolumeSource() != QLatin1String("unavailable"); }
bool MediaPlayerController::volumeMuted() const
{
    return resolvedVolumeSource() == QLatin1String("system") && m_systemVolumeBackend && m_systemVolumeBackend->muted();
}
int MediaPlayerController::volumeControlMode() const { return m_volumeControlMode; }

void MediaPlayerController::setVolumeControlMode(int mode)
{
    mode = std::clamp(mode, 0, 2);
    if (m_volumeControlMode == mode) return;
    m_volumeControlMode = mode;
    Q_EMIT volumeControlModeChanged();
    notifyVolumeStateChanged();
}

void MediaPlayerController::notifyVolumeStateChanged()
{
    const Session *session = selected();
    const bool automaticNeedsSystem = m_volumeControlMode == 0 && session && session->playerPropertiesLoaded
        && (!session->volumePropertyPresent || session->volumeWriteSupport == VolumeWriteSupport::Unsupported);
    if ((m_volumeControlMode == 2 || automaticNeedsSystem) && m_systemVolumeBackend) {
        m_systemVolumeBackend->startMonitoring();
    }
    Q_EMIT volumeChanged();
    Q_EMIT volumeControlStateChanged();
}

qint64 MediaPlayerController::positionUs() const
{
    const Session *session = selected();
    return session ? estimatedPosition(*session) : 0;
}

bool MediaPlayerController::manualSelection() const { return m_manualSelection; }

int MediaPlayerController::indexOf(const QString &service) const
{
    for (qsizetype i = 0; i < m_sessions.size(); ++i) {
        if (m_sessions.at(i).service == service) return int(i);
    }
    return -1;
}

MediaPlayerController::Session *MediaPlayerController::selected()
{
    const int row = indexOf(m_selectedService);
    return row >= 0 ? &m_sessions[row] : nullptr;
}

const MediaPlayerController::Session *MediaPlayerController::selected() const
{
    const int row = indexOf(m_selectedService);
    return row >= 0 ? &m_sessions.at(row) : nullptr;
}

void MediaPlayerController::enumerateServices()
{
    QDBusMessage message = QDBusMessage::createMethodCall(QString::fromLatin1(kBusService),
                                                           QString::fromLatin1(kBusPath),
                                                           QStringLiteral("org.freedesktop.DBus"),
                                                           QStringLiteral("ListNames"));
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *finished) {
        const QDBusPendingReply<QStringList> reply = *finished;
        finished->deleteLater();
        if (reply.isError()) {
            qCWarning(lcMediaPlayer) << "Could not enumerate MPRIS services:" << reply.error().message();
            return;
        }
        for (const QString &name : reply.value()) {
            if (!name.startsWith(QLatin1String(kMprisPrefix))) continue;
            QDBusMessage ownerRequest = QDBusMessage::createMethodCall(QString::fromLatin1(kBusService),
                QString::fromLatin1(kBusPath), QStringLiteral("org.freedesktop.DBus"), QStringLiteral("GetNameOwner"));
            ownerRequest << name;
            auto *ownerWatcher = new QDBusPendingCallWatcher(m_bus.asyncCall(ownerRequest), this);
            connect(ownerWatcher, &QDBusPendingCallWatcher::finished, this, [this, name](QDBusPendingCallWatcher *finishedOwner) {
                const QDBusPendingReply<QString> ownerReply = *finishedOwner;
                finishedOwner->deleteLater();
                if (!ownerReply.isError()) addService(name, ownerReply.value());
            });
        }
    });
}

void MediaPlayerController::onNameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner)
{
    if (!name.startsWith(QLatin1String(kMprisPrefix))) return;
    if (newOwner.isEmpty()) {
        removeService(name);
    } else {
        addService(name, newOwner);
    }
    Q_UNUSED(oldOwner)
}

void MediaPlayerController::addService(const QString &service, const QString &owner)
{
    if (!service.startsWith(QLatin1String(kMprisPrefix)) || owner.isEmpty()) return;
    const int existing = indexOf(service);
    if (existing >= 0 && m_sessions.at(existing).owner == owner) return;
    if (existing >= 0) removeService(service);

    Session session;
    session.service = service;
    session.owner = owner;
    const QString suffix = service.mid(int(strlen(kMprisPrefix)));
    session.identity = suffix;
    session.desktopEntry = suffix;
    session.generation = ++m_generations[service];
    const auto insertion = std::lower_bound(m_sessions.cbegin(), m_sessions.cend(), service,
        [](const Session &entry, const QString &key) { return entry.service < key; });
    const int row = int(std::distance(m_sessions.cbegin(), insertion));
    beginInsertRows({}, row, row);
    m_sessions.insert(row, session);
    endInsertRows();
    Q_EMIT countChanged();

    const bool propertiesConnected = m_bus.connect(service, QString::fromLatin1(kMprisPath),
        QString::fromLatin1(kPropertiesInterface), QStringLiteral("PropertiesChanged"),
        this, SLOT(onPropertiesChanged(QString,QVariantMap,QStringList,QDBusMessage)));
    const bool seekConnected = m_bus.connect(service, QString::fromLatin1(kMprisPath),
        QString::fromLatin1(kPlayerInterface), QStringLiteral("Seeked"), this, SLOT(onSeeked(qlonglong,QDBusMessage)));
    if (!propertiesConnected || !seekConnected) {
        qCDebug(lcMediaPlayer) << "Could not subscribe to all MPRIS signals for" << service << m_bus.lastError().message();
    }

    requestProperties(service, owner, session.generation, QString::fromLatin1(kPlayerInterface));
    requestProperties(service, owner, session.generation, QString::fromLatin1(kRootInterface));
    updateAutomaticSelection();
    logDiagnosticSources(QStringLiteral("service-added"));
}

void MediaPlayerController::removeService(const QString &service)
{
    const int row = indexOf(service);
    if (row < 0) return;
    m_bus.disconnect(service, QString::fromLatin1(kMprisPath), QString::fromLatin1(kPropertiesInterface),
                     QStringLiteral("PropertiesChanged"), this, SLOT(onPropertiesChanged(QString,QVariantMap,QStringList,QDBusMessage)));
    m_bus.disconnect(service, QString::fromLatin1(kMprisPath), QString::fromLatin1(kPlayerInterface),
                     QStringLiteral("Seeked"), this, SLOT(onSeeked(qlonglong,QDBusMessage)));
    beginRemoveRows({}, row, row);
    m_sessions.removeAt(row);
    endRemoveRows();
    ++m_generations[service];
    Q_EMIT countChanged();
    if (m_selectedService == service) {
        m_selectedService.clear();
        m_manualSelection = false;
        Q_EMIT selectionChanged();
        Q_EMIT selectionModeChanged();
        Q_EMIT currentSessionChanged();
        notifyVolumeStateChanged();
    }
    updateAutomaticSelection();
    logDiagnosticSources(QStringLiteral("service-removed"));
}

void MediaPlayerController::requestProperties(const QString &service, const QString &owner, quint64 generation, const QString &interfaceName)
{
    QDBusMessage message = QDBusMessage::createMethodCall(service, QString::fromLatin1(kMprisPath),
        QString::fromLatin1(kPropertiesInterface), QStringLiteral("GetAll"));
    message << interfaceName;
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, service, owner, generation, interfaceName](QDBusPendingCallWatcher *finished) {
        const QDBusPendingReply<QVariantMap> reply = *finished;
        finished->deleteLater();
        const int row = indexOf(service);
        if (row < 0 || m_sessions.at(row).owner != owner || m_sessions.at(row).generation != generation) return;
        if (reply.isError()) {
            qCDebug(lcMediaPlayer) << "GetAll failed for" << service << interfaceName << reply.error().message();
            return;
        }
        applyProperties(m_sessions[row], interfaceName, reply.value());
        if (interfaceName == QLatin1String(kPlayerInterface)) {
            Session &session = m_sessions[row];
            session.playerPropertiesLoaded = true;
            const bool hasVolume = reply.value().contains(QStringLiteral("Volume"));
            if (!hasVolume) {
                session.volumePropertyPresent = false;
                session.volumeWriteSupport = VolumeWriteSupport::Unsupported;
            } else {
                if (!session.volumePropertyPresent || session.volumeWriteSupport == VolumeWriteSupport::Unsupported) {
                    session.volumeWriteSupport = VolumeWriteSupport::Unknown;
                }
                session.volumePropertyPresent = true;
            }
        }
        notifySessionChanged(service);
        updateAutomaticSelection();
        logDiagnosticSources(QStringLiteral("initial-properties"));
    });
}

void MediaPlayerController::applyProperties(Session &session, const QString &interfaceName, const QVariantMap &properties)
{
    const bool player = interfaceName == QLatin1String(kPlayerInterface);
    qint64 preservedPosition = estimatedPosition(session);
    bool positionReplaced = false;
    for (auto it = properties.cbegin(); it != properties.cend(); ++it) {
        const QVariant value = unbox(it.value());
        const QString &key = it.key();
        if (player) {
            if (key == QLatin1String("PlaybackStatus")) session.playbackStatus = value.toString();
            else if (key == QLatin1String("Metadata")) {
                const QVariantMap metadata = variantMap(value);
                const QString newTrackId = objectPathString(unbox(metadata.value(QStringLiteral("mpris:trackid"))));
                if (session.trackId != newTrackId) {
                    session.positionUs = 0;
                    positionReplaced = true;
                }
                session.trackId = newTrackId;
                session.durationUs = metadata.contains(QStringLiteral("mpris:length"))
                    ? std::clamp(unbox(metadata.value(QStringLiteral("mpris:length"))).toLongLong(), qint64(-1), kPositionMaximumUs) : -1;
                session.artUrl = QUrl(unbox(metadata.value(QStringLiteral("mpris:artUrl"))).toString());
                session.mediaUrl = QUrl(unbox(metadata.value(QStringLiteral("xesam:url"))).toString());
                session.title = unbox(metadata.value(QStringLiteral("xesam:title"))).toString();
                const QVariant artist = unbox(metadata.value(QStringLiteral("xesam:artist")));
                session.artist = artist.metaType().id() == QMetaType::QStringList
                    ? artist.toStringList().join(QStringLiteral(", ")) : artist.toString();
                session.album = unbox(metadata.value(QStringLiteral("xesam:album"))).toString();
            }
            else if (key == QLatin1String("Position")) {
                session.positionUs = std::clamp(value.toLongLong(), qint64(0), kPositionMaximumUs);
                positionReplaced = true;
            }
            else if (key == QLatin1String("Rate")) {
                const double rate = value.toDouble();
                session.rate = std::isfinite(rate) ? std::clamp(rate, 0.01, 16.0) : 1.0;
            }
            else if (key == QLatin1String("Volume")) {
                const double volume = value.toDouble();
                session.volume = std::isfinite(volume) ? std::clamp(volume, 0.0, 1.0) : 1.0;
            }
            else if (key == QLatin1String("Shuffle")) session.shuffle = value.toBool();
            else if (key == QLatin1String("LoopStatus")) session.loopStatus = value.toString();
            else if (key == QLatin1String("CanControl")) session.canControl = value.toBool();
            else if (key == QLatin1String("CanPlay")) session.canPlay = value.toBool();
            else if (key == QLatin1String("CanPause")) session.canPause = value.toBool();
            else if (key == QLatin1String("CanGoPrevious")) session.canGoPrevious = value.toBool();
            else if (key == QLatin1String("CanGoNext")) session.canGoNext = value.toBool();
            else if (key == QLatin1String("CanSeek")) session.canSeek = value.toBool();
        } else {
            if (key == QLatin1String("Identity") && !value.toString().isEmpty()) session.identity = value.toString();
            else if (key == QLatin1String("DesktopEntry") && !value.toString().isEmpty()) session.desktopEntry = value.toString();
            else if (key == QLatin1String("CanRaise")) session.canRaise = value.toBool();
        }
    }
    if (!positionReplaced) session.positionUs = preservedPosition;
    session.positionTimestampMs = m_clock.elapsed();
}

void MediaPlayerController::onPropertiesChanged(const QString &interfaceName, const QVariantMap &changed,
                                                const QStringList &invalidated, const QDBusMessage &signalMessage)
{
    const QString sender = signalMessage.service();
    int row = indexOf(sender);
    if (row < 0) {
        for (qsizetype i = 0; i < m_sessions.size(); ++i) {
            if (m_sessions.at(i).owner == sender) { row = int(i); break; }
        }
    }
    if (row < 0) return;
    const QString service = m_sessions.at(row).service;
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    if (interfaceName == QLatin1String(kPlayerInterface)) {
        const auto volume = changed.constFind(QStringLiteral("Volume"));
        if (volume != changed.cend()) {
            const QVariant value = unbox(volume.value());
            bool ok = false;
            const double numericValue = value.toDouble(&ok);
            qCInfo(lcMediaPlayer).noquote()
                << QStringLiteral("MPRIS Volume trace t_ms=%1 event=properties-changed service=%2 valid=%3 value=%4")
                       .arg(m_clock.elapsed()).arg(service, ok ? QStringLiteral("true") : QStringLiteral("false"),
                                                   ok ? QString::number(numericValue, 'g', 12) : QStringLiteral("<invalid>"));
        }
        if (invalidated.contains(QStringLiteral("Volume"))) {
            qCInfo(lcMediaPlayer).noquote()
                << QStringLiteral("MPRIS Volume trace t_ms=%1 event=properties-invalidated service=%2 property=Volume")
                       .arg(m_clock.elapsed()).arg(service);
        }
    }
#endif
    applyProperties(m_sessions[row], interfaceName, changed);
    Session &session = m_sessions[row];
    const bool player = interfaceName == QLatin1String(kPlayerInterface);
    const auto changedVolume = player ? changed.constFind(QStringLiteral("Volume")) : changed.cend();
    const bool volumeWasChanged = changedVolume != changed.cend();
    if (volumeWasChanged) {
        session.volumePropertyPresent = true;
    }
    for (const QString &property : invalidated) {
        if (player) {
            if (property == QLatin1String("PlaybackStatus")) session.playbackStatus.clear();
            else if (property == QLatin1String("Metadata")) {
                session.trackId.clear();
                session.title.clear();
                session.artist.clear();
                session.album.clear();
                session.artUrl.clear();
                session.mediaUrl.clear();
                session.durationUs = -1;
                session.positionUs = 0;
            } else if (property == QLatin1String("Position")) session.positionUs = 0;
            else if (property == QLatin1String("Rate")) session.rate = 1.0;
            else if (property == QLatin1String("Volume")) session.volume = 1.0;
            else if (property == QLatin1String("Shuffle")) session.shuffle = false;
            else if (property == QLatin1String("LoopStatus")) session.loopStatus = QStringLiteral("None");
            else if (property == QLatin1String("CanControl")) session.canControl = false;
            else if (property == QLatin1String("CanPlay")) session.canPlay = false;
            else if (property == QLatin1String("CanPause")) session.canPause = false;
            else if (property == QLatin1String("CanGoPrevious")) session.canGoPrevious = false;
            else if (property == QLatin1String("CanGoNext")) session.canGoNext = false;
            else if (property == QLatin1String("CanSeek")) session.canSeek = false;
        } else {
            if (property == QLatin1String("Identity")) session.identity = session.service.mid(int(strlen(kMprisPrefix)));
            else if (property == QLatin1String("DesktopEntry")) session.desktopEntry.clear();
            else if (property == QLatin1String("CanRaise")) session.canRaise = false;
        }
    }
    session.positionTimestampMs = m_clock.elapsed();
    notifySessionChanged(service);
    if (volumeWasChanged && m_pendingVolumeWrite && m_pendingVolumeWrite->service == service
        && isCurrentVolumeWrite(*m_pendingVolumeWrite)
        && qAbs(session.volume - m_pendingVolumeWrite->requested) <= 0.02) {
        markVolumeWriteSupport(*m_pendingVolumeWrite, VolumeWriteSupport::Supported);
    }
    const auto diagnosticProperty = [](const QString &name) {
        return name == QLatin1String("Identity") || name == QLatin1String("PlaybackStatus")
            || name == QLatin1String("Metadata") || name.startsWith(QLatin1String("Can"));
    };
    const bool diagnosticsRelevant = std::any_of(changed.keyBegin(), changed.keyEnd(), diagnosticProperty)
        || std::any_of(invalidated.cbegin(), invalidated.cend(), diagnosticProperty);
    if (diagnosticsRelevant)
        logDiagnosticSources(QStringLiteral("properties-changed"));
    if (!invalidated.isEmpty()) {
        const Session &session = m_sessions.at(row);
        requestProperties(service, session.owner, session.generation, interfaceName);
    }
    updateAutomaticSelection();
}

void MediaPlayerController::onSeeked(qlonglong newPositionUs, const QDBusMessage &signalMessage)
{
    const QString sender = signalMessage.service();
    int row = indexOf(sender);
    if (row < 0) {
        for (qsizetype i = 0; i < m_sessions.size(); ++i) {
            if (m_sessions.at(i).owner == sender) { row = int(i); break; }
        }
    }
    if (row < 0) return;
    const QString service = m_sessions.at(row).service;
    Session &session = m_sessions[row];
    session.positionUs = std::clamp(qint64(newPositionUs), qint64(0), kPositionMaximumUs);
    session.positionTimestampMs = m_clock.elapsed();
    if (service == m_selectedService) Q_EMIT positionChanged();
}

void MediaPlayerController::notifySessionChanged(const QString &service, const QList<int> &roles)
{
    const int row = indexOf(service);
    if (row >= 0) Q_EMIT dataChanged(index(row), index(row), roles);
    if (service == m_selectedService) {
        Q_EMIT currentSessionChanged();
        notifyVolumeStateChanged();
        updateProgressTimer();
        Q_EMIT positionChanged();
    }
}

void MediaPlayerController::updateAutomaticSelection()
{
    QString nextService;
    for (const Session &session : std::as_const(m_sessions)) {
        if (session.playbackStatus == QLatin1String("Playing")) {
            nextService = session.service;
            break; // model order is deterministic (service names sorted below)
        }
        if (nextService.isEmpty() && m_showPaused && session.playbackStatus == QLatin1String("Paused")) nextService = session.service;
    }
    if (m_manualSelection && !m_selectedService.isEmpty() && indexOf(m_selectedService) >= 0) {
        const Session *manual = selected();
        if (manual && (manual->playbackStatus == QLatin1String("Playing")
                       || (m_showPaused && manual->playbackStatus == QLatin1String("Paused")))) {
            m_stoppedHideTimer.stop();
            updateVisibility();
            return;
        }
        // Keep a manual choice while the player is reporting an unknown status.
        // MPRIS may invalidate PlaybackStatus while refreshing it; treating that
        // transient empty value as a stopped player lets another source steal
        // the user's selection before the replacement properties arrive.
        if (manual && manual->playbackStatus.isEmpty()) {
            updateVisibility();
            return;
        }
        if (manual && manual->playbackStatus == QLatin1String("Stopped") && m_stoppedHideDelayMs > 0) {
            if (!m_stoppedHideTimer.isActive()) m_stoppedHideTimer.start(m_stoppedHideDelayMs);
            updateVisibility();
            return;
        }
        m_manualSelection = false;
        Q_EMIT selectionModeChanged();
    }
    if (!m_manualSelection) {
        const Session *current = selected();
        if (current && current->playbackStatus == QLatin1String("Playing")) {
            m_stoppedHideTimer.stop();
            updateVisibility();
            return;
        }
    }
    if (!nextService.isEmpty()) {
        m_stoppedHideTimer.stop();
        selectService(nextService, false);
    } else {
        const Session *current = selected();
        if (current && m_selectedService == current->service
            && (current->playbackStatus == QLatin1String("Stopped")
                || current->playbackStatus == QLatin1String("Paused"))) {
            if (m_stoppedHideDelayMs > 0) {
                if (!m_stoppedHideTimer.isActive()) m_stoppedHideTimer.start(m_stoppedHideDelayMs);
                updateVisibility();
                return;
            }
        }
        m_stoppedHideTimer.stop();
        selectService({}, false);
    }
    updateVisibility();
}

void MediaPlayerController::selectService(const QString &service, bool manual)
{
    if (!service.isEmpty() && indexOf(service) < 0) return;
    const QString oldService = m_selectedService;
    const bool oldManual = m_manualSelection;
    if (oldService == service && oldManual == manual) return;
    m_selectedService = service;
    m_manualSelection = manual;
    if (!oldService.isEmpty()) {
        const int oldRow = indexOf(oldService);
        if (oldRow >= 0) Q_EMIT dataChanged(index(oldRow), index(oldRow), {SelectedRole});
    }
    if (!service.isEmpty()) {
        const int row = indexOf(service);
        Q_EMIT dataChanged(index(row), index(row), {SelectedRole});
    }
    Q_EMIT selectionChanged();
    Q_EMIT selectionModeChanged();
    Q_EMIT currentSessionChanged();
    notifyVolumeStateChanged();
    Q_EMIT availabilityChanged();
    updateProgressTimer();
    updateVisibility();
    logDiagnosticSources(QStringLiteral("selection-changed"));
}

void MediaPlayerController::logDiagnosticSources(const QString &event) const
{
    if (!qEnvironmentVariableIsSet("KDOCKW_MEDIA_DIAGNOSTICS"))
        return;

    qCInfo(lcMediaPlayer).noquote() << "MPRIS sources" << event
                                   << "count=" << m_sessions.size()
                                   << "selected=" << m_selectedService;
    for (const Session &session : m_sessions) {
        qCInfo(lcMediaPlayer).noquote() << "MPRIS source"
                                        << "service=" << session.service
                                        << "identity=" << session.identity
                                        << "playbackStatus=" << session.playbackStatus
                                        << "selected=" << (session.service == m_selectedService)
                                        << "canControl=" << session.canControl
                                        << "canPlay=" << session.canPlay
                                        << "canPause=" << session.canPause
                                        << "canGoPrevious=" << session.canGoPrevious
                                        << "canGoNext=" << session.canGoNext
                                        << "canSeek=" << session.canSeek
                                        << "canRaise=" << session.canRaise;
    }
}

bool MediaPlayerController::selectSession(const QString &service)
{
    if (indexOf(service) < 0) return false;
    selectService(service, true);
    return true;
}

void MediaPlayerController::selectAutomatic()
{
    m_manualSelection = false;
    Q_EMIT selectionModeChanged();
    const QString old = m_selectedService;
    m_selectedService.clear();
    updateAutomaticSelection();
    if (old == m_selectedService) {
        Q_EMIT currentSessionChanged();
        notifyVolumeStateChanged();
    }
}

void MediaPlayerController::setVisibilityPolicy(bool autoVisibility, bool showPaused, int hideDelayMs)
{
    hideDelayMs = std::clamp(hideDelayMs, 0, 30'000);
    const bool changed = m_autoVisibility != autoVisibility || m_showPaused != showPaused
        || m_stoppedHideDelayMs != hideDelayMs;
    if (!changed) return;
    m_autoVisibility = autoVisibility;
    m_showPaused = showPaused;
    m_stoppedHideDelayMs = hideDelayMs;
    m_stoppedHideTimer.setInterval(hideDelayMs);
    Q_EMIT visibilityPolicyChanged();
    updateAutomaticSelection();
}

void MediaPlayerController::updateVisibility()
{
    const Session *session = selected();
    const bool visible = !m_autoVisibility || (session &&
        (session->playbackStatus == QLatin1String("Playing")
         || (m_showPaused && session->playbackStatus == QLatin1String("Paused"))
         || m_stoppedHideTimer.isActive()));
    if (m_available == visible) return;
    m_available = visible;
    Q_EMIT availabilityChanged();
}

bool MediaPlayerController::sendPlayerMethod(const QString &method, const QVariantList &arguments)
{
    const Session *session = selected();
    if (!session || !session->canControl) return false;
    const QString service = session->service;
    const QDBusMessage call = QDBusMessage::createMethodCall(session->owner, QString::fromLatin1(kMprisPath),
        QString::fromLatin1(kPlayerInterface), method);
    const QDBusMessage request = call;
    QDBusMessage withArgs = request;
    withArgs.setArguments(arguments);
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(withArgs), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, service, method](QDBusPendingCallWatcher *finished) {
        const QDBusPendingReply<> reply = *finished;
        finished->deleteLater();
        if (reply.isError()) Q_EMIT commandFailed(service, method + QStringLiteral(": ") + reply.error().message());
    });
    return true;
}

bool MediaPlayerController::playPause()
{
    const Session *s = selected();
    return s && s->canControl && (s->playbackStatus == QLatin1String("Playing") ? s->canPause : s->canPlay)
        ? sendPlayerMethod(QStringLiteral("PlayPause")) : false;
}

bool MediaPlayerController::previous() { const Session *s = selected(); return s && s->canGoPrevious && sendPlayerMethod(QStringLiteral("Previous")); }
bool MediaPlayerController::next() { const Session *s = selected(); return s && s->canGoNext && sendPlayerMethod(QStringLiteral("Next")); }

bool MediaPlayerController::seekTo(qint64 newPositionUs, const QString &expectedTrackId)
{
    const Session *s = selected();
    if (!s || !s->canSeek || expectedTrackId.isEmpty() || expectedTrackId != s->trackId || s->durationUs <= 0) return false;
    const qint64 bounded = std::clamp(newPositionUs, qint64(0), s->durationUs - 1);
    return sendPlayerMethod(QStringLiteral("SetPosition"), {QVariant::fromValue(QDBusObjectPath(s->trackId)), QVariant::fromValue(bounded)});
}

bool MediaPlayerController::setPlayerProperty(const QString &name, const QVariant &value)
{
    const Session *s = selected();
    if (!s || !s->canControl) return false;
    const QString service = s->service;
    const QString owner = s->owner;
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    const bool traceVolume = name == QLatin1String("Volume");
    if (traceVolume) {
        qCInfo(lcMediaPlayer).noquote()
            << QStringLiteral("MPRIS Volume trace t_ms=%1 event=properties-set-dispatch service=%2 owner=%3 value=%4")
                   .arg(m_clock.elapsed()).arg(service, owner, value.toString());
    }
#endif
    QDBusMessage call = QDBusMessage::createMethodCall(s->owner, QString::fromLatin1(kMprisPath),
        QString::fromLatin1(kPropertiesInterface), QStringLiteral("Set"));
    call << QString::fromLatin1(kPlayerInterface) << name << QVariant::fromValue(QDBusVariant(value));
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, service, name
#ifdef KDOCKW_DIAGNOSTIC_BUILD
                                                                 , owner, traceVolume
#endif
    ](QDBusPendingCallWatcher *finished) {
        const QDBusPendingReply<> reply = *finished;
        finished->deleteLater();
        if (reply.isError()) {
#ifdef KDOCKW_DIAGNOSTIC_BUILD
            if (traceVolume) {
                qCInfo(lcMediaPlayer).noquote()
                    << QStringLiteral("MPRIS Volume trace t_ms=%1 event=properties-set-error service=%2 error_name=%3 message=%4")
                           .arg(m_clock.elapsed()).arg(service, reply.error().name(), reply.error().message());
            }
#endif
            Q_EMIT commandFailed(service, name + QStringLiteral(": ") + reply.error().message());
        }
#ifdef KDOCKW_DIAGNOSTIC_BUILD
        else if (traceVolume) {
            qCInfo(lcMediaPlayer).noquote()
                << QStringLiteral("MPRIS Volume trace t_ms=%1 event=properties-set-success service=%2")
                       .arg(m_clock.elapsed()).arg(service);
        }
        if (traceVolume) diagnosticReadVolume(service, owner, QStringLiteral("after-set"));
#endif
    });
    return true;
}

bool MediaPlayerController::setVolume(double value)
{
    const double boundedValue = std::clamp(value, 0.0, 1.0);
    const QString source = resolvedVolumeSource();
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    const Session *s = selected();
    qCInfo(lcMediaPlayer).noquote()
        << QStringLiteral("MPRIS Volume trace t_ms=%1 event=set-volume-call source=%2 service=%3 owner=%4 can-control=%5 cached-volume=%6 requested=%7")
               .arg(m_clock.elapsed())
               .arg(source, s ? s->service : QStringLiteral("<none>"), s ? s->owner : QStringLiteral("<none>"))
               .arg(s && s->canControl ? QStringLiteral("true") : QStringLiteral("false"))
               .arg(s ? QString::number(s->volume, 'g', 12) : QStringLiteral("<none>"), QString::number(boundedValue, 'g', 12));
#endif
    const bool accepted = source == QLatin1String("player") ? setMprisVolume(boundedValue)
        : source == QLatin1String("system") && m_systemVolumeBackend ? (m_systemVolumeBackend->setVolume(boundedValue), true)
        : false;
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    qCInfo(lcMediaPlayer).noquote()
        << QStringLiteral("MPRIS Volume trace t_ms=%1 event=set-volume-return accepted=%2")
               .arg(m_clock.elapsed()).arg(accepted ? QStringLiteral("true") : QStringLiteral("false"));
#endif
    return accepted;
}

bool MediaPlayerController::setMprisVolume(double value)
{
    Session *session = selected();
    if (!session || !session->volumePropertyPresent
        || session->volumeWriteSupport == VolumeWriteSupport::Unsupported) {
        return false;
    }

    PendingVolumeWrite pending;
    pending.service = session->service;
    pending.owner = session->owner;
    pending.generation = session->generation;
    pending.request = ++m_nextVolumeWriteRequest;
    pending.requested = std::clamp(value, 0.0, 1.0);
    pending.previous = session->volume;
    session->volumeWriteRequest = pending.request;
    m_pendingVolumeWrite = pending;
    m_volumeVerificationTimer.stop();
    const bool changedEnoughToVerify = qAbs(pending.requested - pending.previous) > 0.02;
    const bool supportWasUnknown = session->volumeWriteSupport == VolumeWriteSupport::Unknown;

#ifdef KDOCKW_DIAGNOSTIC_BUILD
    qCInfo(lcMediaPlayer).noquote()
        << QStringLiteral("MPRIS Volume trace t_ms=%1 event=properties-set-dispatch service=%2 owner=%3 value=%4")
               .arg(m_clock.elapsed()).arg(pending.service, pending.owner,
                                            QString::number(pending.requested, 'g', 12));
#endif
    QDBusMessage call = QDBusMessage::createMethodCall(pending.owner, QString::fromLatin1(kMprisPath),
        QString::fromLatin1(kPropertiesInterface), QStringLiteral("Set"));
    call << QString::fromLatin1(kPlayerInterface) << QStringLiteral("Volume")
         << QVariant::fromValue(QDBusVariant(pending.requested));
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, pending, changedEnoughToVerify, supportWasUnknown](QDBusPendingCallWatcher *finished) {
        const QDBusPendingReply<> reply = *finished;
        finished->deleteLater();
        if (!isCurrentVolumeWrite(pending)) {
            return;
        }
        if (reply.isError()) {
#ifdef KDOCKW_DIAGNOSTIC_BUILD
            qCInfo(lcMediaPlayer).noquote()
                << QStringLiteral("MPRIS Volume trace t_ms=%1 event=properties-set-error service=%2 error_name=%3 message=%4")
                       .arg(m_clock.elapsed()).arg(pending.service, reply.error().name(), reply.error().message());
#endif
            if (reply.error().name() == QLatin1String("org.freedesktop.DBus.Error.UnknownProperty")
                || reply.error().name() == QLatin1String("org.freedesktop.DBus.Error.PropertyReadOnly")) {
                markVolumeWriteSupport(pending, VolumeWriteSupport::Unsupported);
            } else {
                m_pendingVolumeWrite.reset();
            }
            Q_EMIT commandFailed(pending.service, QStringLiteral("Volume: ") + reply.error().message());
            return;
        }
#ifdef KDOCKW_DIAGNOSTIC_BUILD
        qCInfo(lcMediaPlayer).noquote()
            << QStringLiteral("MPRIS Volume trace t_ms=%1 event=properties-set-success service=%2")
                   .arg(m_clock.elapsed()).arg(pending.service);
        diagnosticReadVolume(pending.service, pending.owner, QStringLiteral("after-set-response"));
#endif
        if (!changedEnoughToVerify && supportWasUnknown) {
            m_pendingVolumeWrite.reset();
            return;
        }
        requestVolumeReadback(pending, false);
    });
    return true;
}

bool MediaPlayerController::isCurrentVolumeWrite(const PendingVolumeWrite &pending) const
{
    const int row = indexOf(pending.service);
    return m_pendingVolumeWrite && m_pendingVolumeWrite->request == pending.request
        && row >= 0 && m_sessions.at(row).owner == pending.owner
        && m_sessions.at(row).generation == pending.generation
        && m_sessions.at(row).volumeWriteRequest == pending.request;
}

void MediaPlayerController::markVolumeWriteSupport(const PendingVolumeWrite &pending, VolumeWriteSupport support)
{
    if (!isCurrentVolumeWrite(pending)) return;
    const int row = indexOf(pending.service);
    if (row < 0) return;
    m_sessions[row].volumeWriteSupport = support;
    m_pendingVolumeWrite.reset();
    m_volumeVerificationTimer.stop();
    if (pending.service == m_selectedService) {
        notifyVolumeStateChanged();
    }
}

void MediaPlayerController::requestVolumeReadback(const PendingVolumeWrite &pending, bool finalCheck)
{
    if (!isCurrentVolumeWrite(pending)) return;
    QDBusMessage call = QDBusMessage::createMethodCall(pending.owner, QString::fromLatin1(kMprisPath),
        QString::fromLatin1(kPropertiesInterface), QStringLiteral("Get"));
    call << QString::fromLatin1(kPlayerInterface) << QStringLiteral("Volume");
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, pending, finalCheck](QDBusPendingCallWatcher *finished) {
        const QDBusMessage response = finished->reply();
        finished->deleteLater();
        if (!isCurrentVolumeWrite(pending)) return;
        if (response.type() == QDBusMessage::ErrorMessage) {
            const QDBusError error = response;
#ifdef KDOCKW_DIAGNOSTIC_BUILD
            qCInfo(lcMediaPlayer).noquote()
                << QStringLiteral("MPRIS Volume trace t_ms=%1 event=verification-get-error service=%2 final=%3 error_name=%4")
                       .arg(m_clock.elapsed()).arg(pending.service, finalCheck ? QStringLiteral("true") : QStringLiteral("false"), error.name());
#endif
            if (error.name() == QLatin1String("org.freedesktop.DBus.Error.UnknownProperty")
                || error.name() == QLatin1String("org.freedesktop.DBus.Error.PropertyReadOnly")) {
                markVolumeWriteSupport(pending, VolumeWriteSupport::Unsupported);
            } else if (finalCheck) {
                m_pendingVolumeWrite.reset();
            } else {
                m_volumeVerificationTimer.start();
            }
            return;
        }
        const QList<QVariant> arguments = response.arguments();
        if (arguments.isEmpty()) {
            if (finalCheck) m_pendingVolumeWrite.reset();
            else m_volumeVerificationTimer.start();
            return;
        }
        bool valid = false;
        const double readback = unbox(arguments.constFirst()).toDouble(&valid);
        if (!valid || !std::isfinite(readback)) {
            if (finalCheck) m_pendingVolumeWrite.reset();
            else m_volumeVerificationTimer.start();
            return;
        }
        const double boundedReadback = std::clamp(readback, 0.0, 1.0);
        const int row = indexOf(pending.service);
        if (row >= 0) m_sessions[row].volume = boundedReadback;
#ifdef KDOCKW_DIAGNOSTIC_BUILD
        qCInfo(lcMediaPlayer).noquote()
            << QStringLiteral("MPRIS Volume trace t_ms=%1 event=verification-get-result service=%2 final=%3 value=%4 requested=%5 previous=%6")
                   .arg(m_clock.elapsed())
                   .arg(pending.service, finalCheck ? QStringLiteral("true") : QStringLiteral("false"),
                        QString::number(boundedReadback, 'g', 12), QString::number(pending.requested, 'g', 12),
                        QString::number(pending.previous, 'g', 12));
#endif
        if (qAbs(boundedReadback - pending.requested) <= 0.02) {
            markVolumeWriteSupport(pending, VolumeWriteSupport::Supported);
        } else if (!finalCheck) {
            m_volumeVerificationTimer.start();
        } else if (qAbs(pending.requested - pending.previous) > 0.02
                   && qAbs(boundedReadback - pending.previous) <= 0.02) {
            markVolumeWriteSupport(pending, VolumeWriteSupport::Unsupported);
        } else {
            m_pendingVolumeWrite.reset();
        }
        if (pending.service == m_selectedService) {
            notifySessionChanged(pending.service);
        }
    });
}

void MediaPlayerController::diagnosticVolumeSliderEvent(const QString &event, double value)
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    qCInfo(lcMediaPlayer).noquote()
        << QStringLiteral("MPRIS Volume trace t_ms=%1 event=ui-slider-%2 value=%3")
               .arg(m_clock.elapsed()).arg(event, QString::number(std::clamp(value, 0.0, 1.0), 'g', 12));
#else
    Q_UNUSED(event);
    Q_UNUSED(value);
#endif
}

#ifdef KDOCKW_DIAGNOSTIC_BUILD
void MediaPlayerController::diagnosticReadVolume(const QString &service, const QString &owner, const QString &reason)
{
    QDBusMessage call = QDBusMessage::createMethodCall(owner, QString::fromLatin1(kMprisPath),
        QString::fromLatin1(kPropertiesInterface), QStringLiteral("Get"));
    call << QString::fromLatin1(kPlayerInterface) << QStringLiteral("Volume");
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, service, reason](QDBusPendingCallWatcher *finished) {
        const QDBusMessage response = finished->reply();
        finished->deleteLater();
        if (response.type() == QDBusMessage::ErrorMessage) {
            const QDBusError error = response;
            qCInfo(lcMediaPlayer).noquote()
                << QStringLiteral("MPRIS Volume trace t_ms=%1 event=properties-get-error reason=%2 service=%3 error_name=%4 message=%5")
                       .arg(m_clock.elapsed()).arg(reason, service, error.name(), error.message());
            return;
        }
        const QList<QVariant> arguments = response.arguments();
        if (arguments.isEmpty()) {
            qCInfo(lcMediaPlayer).noquote()
                << QStringLiteral("MPRIS Volume trace t_ms=%1 event=properties-get-empty reason=%2 service=%3")
                       .arg(m_clock.elapsed()).arg(reason, service);
            return;
        }
        const QVariant value = unbox(arguments.constFirst());
        bool ok = false;
        const double volume = value.toDouble(&ok);
        qCInfo(lcMediaPlayer).noquote()
            << QStringLiteral("MPRIS Volume trace t_ms=%1 event=properties-get-result reason=%2 service=%3 valid=%4 value=%5")
                   .arg(m_clock.elapsed()).arg(reason, service)
                   .arg(ok ? QStringLiteral("true") : QStringLiteral("false"),
                        ok ? QString::number(volume, 'g', 12) : QString::fromLatin1(value.metaType().name()));
    });
}
#endif

bool MediaPlayerController::setShuffle(bool value)
{
    const Session *s = selected();
    return s && s->canControl && setPlayerProperty(QStringLiteral("Shuffle"), value);
}

bool MediaPlayerController::setLoopStatus(const QString &value)
{
    if (value != QLatin1String("None") && value != QLatin1String("Track") && value != QLatin1String("Playlist")) return false;
    const Session *s = selected();
    return s && s->canControl && setPlayerProperty(QStringLiteral("LoopStatus"), value);
}

bool MediaPlayerController::raisePlayer()
{
    const Session *s = selected();
    if (!s || !s->canRaise) return false;
    QDBusMessage call = QDBusMessage::createMethodCall(s->owner, QString::fromLatin1(kMprisPath),
        QString::fromLatin1(kRootInterface), QStringLiteral("Raise"));
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    const QString service = s->service;
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, service](QDBusPendingCallWatcher *finished) {
        const QDBusPendingReply<> reply = *finished;
        finished->deleteLater();
        if (reply.isError()) Q_EMIT commandFailed(service, reply.error().message());
    });
    return true;
}

qint64 MediaPlayerController::estimatedPosition(const Session &session) const
{
    qint64 position = session.positionUs;
    if (session.playbackStatus == QLatin1String("Playing")) {
        const qint64 elapsedUs = std::max<qint64>(0, m_clock.elapsed() - session.positionTimestampMs) * 1000;
        position += qint64(double(elapsedUs) * session.rate);
    }
    if (session.durationUs > 0) position = std::min(position, session.durationUs);
    return std::max<qint64>(0, position);
}

void MediaPlayerController::updateProgressTimer()
{
    const Session *s = selected();
    if (s && s->playbackStatus == QLatin1String("Playing") && s->durationUs > 0
        && !m_progressClients.isEmpty()) m_progressTimer.start();
    else m_progressTimer.stop();
}

} // namespace kdockw
