// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

#include <functional>

class QProcess;
class QTimer;

namespace kdockw
{

/** Read/write access to the system's current default audio output. */
class SystemVolumeBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY stateChanged)
    Q_PROPERTY(double volume READ volume NOTIFY stateChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY stateChanged)
    Q_PROPERTY(QString defaultOutput READ defaultOutput NOTIFY stateChanged)

public:
    explicit SystemVolumeBackend(QObject *parent = nullptr);
    ~SystemVolumeBackend() override = default;

    bool available() const;
    double volume() const;
    bool muted() const;
    QString defaultOutput() const;

    virtual void startMonitoring() {}
    virtual void setVolume(double value) = 0;

Q_SIGNALS:
    void stateChanged();

protected:
    void publishState(bool available, double volume, bool muted, const QString &defaultOutput);

private:
    bool m_available = false;
    double m_volume = 0.0;
    bool m_muted = false;
    QString m_defaultOutput;
};

/**
 * Optional asynchronous adapter for the PulseAudio protocol exposed by
 * pipewire-pulse. A persistent subscription observes changes; pactl is invoked
 * only for event-driven reads and one user-committed slider value.
 */
class PactlSystemVolumeBackend final : public SystemVolumeBackend
{
public:
    explicit PactlSystemVolumeBackend(const QString &executable = {}, QObject *parent = nullptr);
    ~PactlSystemVolumeBackend() override;

    void startMonitoring() override;
    void setVolume(double value) override;

private:
    using CommandCallback = std::function<void(int, const QString &, const QString &)>;

    void startSubscription();
    void restartSubscription();
    void handleSubscriptionOutput();
    void requestRefresh();
    void beginRefresh();
    void finishRefresh(bool success);
    void beginPendingSet();
    void runCommand(const QStringList &arguments, CommandCallback callback);
    void completeCommand(int exitCode, const QString &standardOutput, const QString &standardError);
    void scheduleReconnect();

    QString m_executable;
    QString m_defaultOutput;
    QString m_volumeCommandOutput;
    QString m_muteCommandOutput;
    QProcess *m_subscription = nullptr;
    QProcess *m_command = nullptr;
    QTimer *m_refreshDebounce = nullptr;
    QTimer *m_reconnectTimer = nullptr;
    QTimer *m_commandTimeout = nullptr;
    CommandCallback m_commandCallback;
    QString m_commandOperation;
    bool m_busy = false;
    bool m_refreshing = false;
    bool m_refreshRequested = false;
    bool m_subscriptionFailed = false;
    bool m_subscriptionFailureLogged = false;
    bool m_started = false;
    bool m_hasPendingSet = false;
    double m_pendingSet = 0.0;
};

} // namespace kdockw
