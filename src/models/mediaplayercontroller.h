// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QAbstractListModel>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QElapsedTimer>
#include <QHash>
#include <QSet>
#include <QTimer>
#include <QUrl>

namespace kdockw
{

/** One shared, asynchronous MPRIS2 client for the dock's built-in media item. */
class MediaPlayerController final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(QAbstractItemModel *sessions READ sessions CONSTANT)
    Q_PROPERTY(bool available READ available NOTIFY availabilityChanged)
    Q_PROPERTY(bool autoVisibility READ autoVisibility NOTIFY visibilityPolicyChanged)
    Q_PROPERTY(bool showPaused READ showPaused NOTIFY visibilityPolicyChanged)
    Q_PROPERTY(int stoppedHideDelayMs READ stoppedHideDelayMs NOTIFY visibilityPolicyChanged)
    Q_PROPERTY(QString selectedService READ selectedService NOTIFY selectionChanged)
    Q_PROPERTY(QString identity READ identity NOTIFY currentSessionChanged)
    Q_PROPERTY(QString desktopEntry READ desktopEntry NOTIFY currentSessionChanged)
    Q_PROPERTY(QString title READ title NOTIFY currentSessionChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY currentSessionChanged)
    Q_PROPERTY(QString album READ album NOTIFY currentSessionChanged)
    Q_PROPERTY(QString playbackStatus READ playbackStatus NOTIFY currentSessionChanged)
    Q_PROPERTY(QString loopStatus READ loopStatus NOTIFY currentSessionChanged)
    Q_PROPERTY(QString trackId READ trackId NOTIFY currentSessionChanged)
    Q_PROPERTY(QUrl artUrl READ artUrl NOTIFY currentSessionChanged)
    Q_PROPERTY(QUrl mediaUrl READ mediaUrl NOTIFY currentSessionChanged)
    Q_PROPERTY(qint64 durationUs READ durationUs NOTIFY currentSessionChanged)
    Q_PROPERTY(qint64 positionUs READ positionUs NOTIFY positionChanged)
    Q_PROPERTY(double rate READ rate NOTIFY currentSessionChanged)
    Q_PROPERTY(double volume READ volume NOTIFY currentSessionChanged)
    Q_PROPERTY(bool shuffle READ shuffle NOTIFY currentSessionChanged)
    Q_PROPERTY(bool canControl READ canControl NOTIFY currentSessionChanged)
    Q_PROPERTY(bool canPlay READ canPlay NOTIFY currentSessionChanged)
    Q_PROPERTY(bool canPause READ canPause NOTIFY currentSessionChanged)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY currentSessionChanged)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY currentSessionChanged)
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY currentSessionChanged)
    Q_PROPERTY(bool canRaise READ canRaise NOTIFY currentSessionChanged)
    Q_PROPERTY(bool manualSelection READ manualSelection NOTIFY selectionModeChanged)

public:
    enum Role {
        ServiceRole = Qt::UserRole + 1,
        IdentityRole,
        DesktopEntryRole,
        TitleRole,
        PlaybackStatusRole,
        SelectedRole,
    };
    Q_ENUM(Role)

    explicit MediaPlayerController(QObject *parent = nullptr);
    ~MediaPlayerController() override;

    int rowCount(const QModelIndex &parent = {}) const override;
    QAbstractItemModel *sessions();
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool available() const;
    bool autoVisibility() const;
    bool showPaused() const;
    int stoppedHideDelayMs() const;
    QString selectedService() const;
    QString identity() const;
    QString desktopEntry() const;
    QString title() const;
    QString artist() const;
    QString album() const;
    QString playbackStatus() const;
    QString loopStatus() const;
    QString trackId() const;
    QUrl artUrl() const;
    QUrl mediaUrl() const;
    qint64 durationUs() const;
    qint64 positionUs() const;
    double rate() const;
    double volume() const;
    bool shuffle() const;
    bool canControl() const;
    bool canPlay() const;
    bool canPause() const;
    bool canGoPrevious() const;
    bool canGoNext() const;
    bool canSeek() const;
    bool canRaise() const;
    bool manualSelection() const;

    Q_INVOKABLE bool selectSession(const QString &service);
    Q_INVOKABLE QString serviceAt(int row) const;
    Q_INVOKABLE void setProgressRequested(QObject *client, bool requested);
    Q_INVOKABLE void selectAutomatic();
    Q_INVOKABLE bool playPause();
    Q_INVOKABLE bool previous();
    Q_INVOKABLE bool next();
    Q_INVOKABLE bool seekTo(qint64 positionUs, const QString &expectedTrackId);
    Q_INVOKABLE bool setVolume(double value);
    Q_INVOKABLE bool setShuffle(bool value);
    Q_INVOKABLE bool setLoopStatus(const QString &value);
    Q_INVOKABLE bool raisePlayer();
    void setVisibilityPolicy(bool autoVisibility, bool showPaused, int stoppedHideDelayMs);

Q_SIGNALS:
    void countChanged();
    void availabilityChanged();
    void visibilityPolicyChanged();
    void selectionChanged();
    void selectionModeChanged();
    void currentSessionChanged();
    void positionChanged();
    void commandFailed(const QString &service, const QString &message);

private Q_SLOTS:
    void onNameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void onPropertiesChanged(const QString &interfaceName, const QVariantMap &changed,
                             const QStringList &invalidated, const QDBusMessage &message);
    void onSeeked(qlonglong positionUs, const QDBusMessage &message);

private:
    struct Session {
        QString service;
        QString owner;
        QString identity;
        QString desktopEntry;
        QString title;
        QString artist;
        QString album;
        QString trackId;
        QString playbackStatus;
        QString loopStatus = QStringLiteral("None");
        QUrl artUrl;
        QUrl mediaUrl;
        qint64 durationUs = -1;
        qint64 positionUs = 0;
        qint64 positionTimestampMs = 0;
        double rate = 1.0;
        double volume = 1.0;
        bool shuffle = false;
        bool canControl = false;
        bool canPlay = false;
        bool canPause = false;
        bool canGoPrevious = false;
        bool canGoNext = false;
        bool canSeek = false;
        bool canRaise = false;
        quint64 generation = 0;
    };

    int indexOf(const QString &service) const;
    Session *selected();
    const Session *selected() const;
    void enumerateServices();
    void addService(const QString &service, const QString &owner);
    void removeService(const QString &service);
    void requestProperties(const QString &service, const QString &owner, quint64 generation, const QString &interfaceName);
    void applyProperties(Session &session, const QString &interfaceName, const QVariantMap &properties);
    void updateAutomaticSelection();
    void selectService(const QString &service, bool manual);
    bool sendPlayerMethod(const QString &method, const QVariantList &arguments = {});
    bool setPlayerProperty(const QString &name, const QVariant &value);
    qint64 estimatedPosition(const Session &session) const;
    void updateProgressTimer();
    void updateVisibility();
    void notifySessionChanged(const QString &service, const QList<int> &roles = {});
    void logDiagnosticSources(const QString &event) const;

    QDBusConnection m_bus;
    QList<Session> m_sessions;
    QHash<QString, quint64> m_generations;
    QString m_selectedService;
    bool m_manualSelection = false;
    bool m_available = false;
    bool m_autoVisibility = true;
    bool m_showPaused = true;
    int m_stoppedHideDelayMs = 5000;
    QElapsedTimer m_clock;
    QTimer m_progressTimer;
    QTimer m_stoppedHideTimer;
    QSet<QObject *> m_progressClients;
};

} // namespace kdockw
