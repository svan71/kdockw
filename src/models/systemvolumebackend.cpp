// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "systemvolumebackend.h"

#include <QProcess>
#include <QProcessEnvironment>
#include <QLoggingCategory>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>

#include <algorithm>
#include <cmath>

namespace kdockw
{

Q_LOGGING_CATEGORY(lcSystemVolume, "kdockw.media-player.volume")

SystemVolumeBackend::SystemVolumeBackend(QObject *parent)
    : QObject(parent)
{
}

bool SystemVolumeBackend::available() const
{
    return m_available;
}

double SystemVolumeBackend::volume() const
{
    return m_volume;
}

bool SystemVolumeBackend::muted() const
{
    return m_muted;
}

QString SystemVolumeBackend::defaultOutput() const
{
    return m_defaultOutput;
}

void SystemVolumeBackend::publishState(bool available, double volume, bool muted, const QString &defaultOutput)
{
    volume = std::isfinite(volume) ? std::clamp(volume, 0.0, 1.0) : 0.0;
    if (m_available == available && qAbs(m_volume - volume) < 0.0001 && m_muted == muted
        && m_defaultOutput == defaultOutput) {
        return;
    }
    m_available = available;
    m_volume = volume;
    m_muted = muted;
    m_defaultOutput = defaultOutput;
    Q_EMIT stateChanged();
}

PactlSystemVolumeBackend::PactlSystemVolumeBackend(const QString &executable, QObject *parent)
    : SystemVolumeBackend(parent)
    , m_executable(executable.isEmpty() ? QStandardPaths::findExecutable(QStringLiteral("pactl")) : executable)
    , m_refreshDebounce(new QTimer(this))
    , m_reconnectTimer(new QTimer(this))
    , m_commandTimeout(new QTimer(this))
{
    m_refreshDebounce->setSingleShot(true);
    m_refreshDebounce->setInterval(75);
    connect(m_refreshDebounce, &QTimer::timeout, this, &PactlSystemVolumeBackend::requestRefresh);

    m_reconnectTimer->setSingleShot(true);
    m_reconnectTimer->setInterval(5000);
    connect(m_reconnectTimer, &QTimer::timeout, this, &PactlSystemVolumeBackend::restartSubscription);

    m_commandTimeout->setSingleShot(true);
    m_commandTimeout->setInterval(2000);
    connect(m_commandTimeout, &QTimer::timeout, this, [this] {
        if (m_command && m_command->state() != QProcess::NotRunning) {
            m_command->kill();
        }
    });

}

PactlSystemVolumeBackend::~PactlSystemVolumeBackend()
{
    if (m_subscription && m_subscription->state() != QProcess::NotRunning) {
        m_subscription->terminate();
        if (!m_subscription->waitForFinished(250)) {
            m_subscription->kill();
            m_subscription->waitForFinished(250);
        }
    }
    if (m_command && m_command->state() != QProcess::NotRunning) {
        m_command->kill();
        m_command->waitForFinished(250);
    }
}

void PactlSystemVolumeBackend::startSubscription()
{
    if (m_executable.isEmpty()) {
        return;
    }
    if (m_subscription) {
        m_subscription->deleteLater();
    }
    m_subscription = new QProcess(this);
    connect(m_subscription, &QProcess::readyReadStandardOutput, this, &PactlSystemVolumeBackend::handleSubscriptionOutput);
    connect(m_subscription, &QProcess::started, this, [this] {
        m_subscriptionFailed = false;
        m_subscriptionFailureLogged = false;
        m_reconnectTimer->stop();
        requestRefresh();
    });
    connect(m_subscription, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) {
            return;
        }
        m_subscriptionFailed = true;
        publishState(false, volume(), muted(), m_defaultOutput);
        if (!m_subscriptionFailureLogged) {
            qCWarning(lcSystemVolume) << "pactl event subscription could not start";
            m_subscriptionFailureLogged = true;
        }
        scheduleReconnect();
    });
    connect(m_subscription, &QProcess::finished, this, [this] {
        m_subscriptionFailed = true;
        publishState(false, volume(), muted(), m_defaultOutput);
        if (!m_subscriptionFailureLogged) {
            qCWarning(lcSystemVolume) << "pactl event subscription stopped";
            m_subscriptionFailureLogged = true;
        }
        scheduleReconnect();
    });

    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    m_subscription->setProcessEnvironment(environment);
    m_subscription->setProgram(m_executable);
    m_subscription->setArguments({QStringLiteral("subscribe")});
    m_subscription->start();
}

void PactlSystemVolumeBackend::startMonitoring()
{
    if (m_started || m_executable.isEmpty()) {
        return;
    }
    m_started = true;
    startSubscription();
}

void PactlSystemVolumeBackend::restartSubscription()
{
    if (m_subscriptionFailed) {
        startSubscription();
    }
}

void PactlSystemVolumeBackend::handleSubscriptionOutput()
{
    const QByteArray output = m_subscription->readAllStandardOutput();
    const QList<QByteArray> lines = output.split('\n');
    for (const QByteArray &line : lines) {
        // Server events include default-output changes. Sink events include
        // external volume and mute changes; unrelated stream events are ignored.
        if (line.contains(" on server") || line.contains(" on sink")) {
            m_refreshDebounce->start();
        }
    }
}

void PactlSystemVolumeBackend::requestRefresh()
{
    if (m_executable.isEmpty()) {
        return;
    }
    if (m_busy || m_refreshing) {
        m_refreshRequested = true;
        return;
    }
    beginRefresh();
}

void PactlSystemVolumeBackend::beginRefresh()
{
    if (m_busy || m_refreshing) {
        m_refreshRequested = true;
        return;
    }
    m_refreshRequested = false;
    m_refreshing = true;
    runCommand({QStringLiteral("get-default-sink")}, [this](int exitCode, const QString &output, const QString &) {
        const QString outputName = exitCode == 0 ? output.trimmed() : QString{};
        if (outputName.isEmpty()) {
            finishRefresh(false);
            return;
        }
        m_defaultOutput = outputName;
        runCommand({QStringLiteral("get-sink-volume"), QStringLiteral("@DEFAULT_SINK@")} ,
                   [this](int volumeExitCode, const QString &volumeOutput, const QString &) {
            if (volumeExitCode != 0) {
                finishRefresh(false);
                return;
            }
            m_volumeCommandOutput = volumeOutput;
            runCommand({QStringLiteral("get-sink-mute"), QStringLiteral("@DEFAULT_SINK@")} ,
                       [this](int muteExitCode, const QString &muteOutput, const QString &) {
                if (muteExitCode != 0) {
                    finishRefresh(false);
                    return;
                }
                m_muteCommandOutput = muteOutput;
                static const QRegularExpression percentPattern(QStringLiteral("/\\s*([0-9]+(?:\\.[0-9]+)?)%\\s*/"));
                const QRegularExpressionMatchIterator matches = percentPattern.globalMatch(m_volumeCommandOutput);
                double volumePercent = 0.0;
                int channelCount = 0;
                auto match = matches;
                while (match.hasNext()) {
                    bool ok = false;
                    const double channelPercent = match.next().captured(1).toDouble(&ok);
                    if (ok && std::isfinite(channelPercent)) {
                        volumePercent += channelPercent;
                        ++channelCount;
                    }
                }
                const QString muteText = m_muteCommandOutput.trimmed();
                const bool muteValid = muteText.startsWith(QStringLiteral("Mute:"), Qt::CaseInsensitive);
                const bool volumeValid = channelCount > 0;
                if (!muteValid || !volumeValid) {
                    finishRefresh(false);
                    return;
                }
                const bool isMuted = muteText.mid(muteText.indexOf(QLatin1Char(':')) + 1).trimmed().compare(QStringLiteral("yes"), Qt::CaseInsensitive) == 0;
                const double normalized = std::clamp((volumePercent / channelCount) / 100.0, 0.0, 1.0);
                publishState(true, normalized, isMuted, m_defaultOutput);
                finishRefresh(true);
            });
        });
    });
}

void PactlSystemVolumeBackend::finishRefresh(bool success)
{
    m_refreshing = false;
    if (!success) {
        // Never apply a delayed slider request after the output server became
        // unavailable while its state was being refreshed.
        m_hasPendingSet = false;
        publishState(false, volume(), muted(), m_defaultOutput);
    }
    if (m_refreshRequested) {
        m_refreshDebounce->start();
    }
}

void PactlSystemVolumeBackend::beginPendingSet()
{
    if (!m_hasPendingSet || !available() || m_busy || m_refreshing) {
        return;
    }
    const double requested = std::clamp(m_pendingSet, 0.0, 1.0);
    m_hasPendingSet = false;
    const QString percentage = QString::number(qRound(requested * 100.0)) + QLatin1Char('%');
    runCommand({QStringLiteral("set-sink-volume"), QStringLiteral("@DEFAULT_SINK@"), percentage},
               [this](int exitCode, const QString &, const QString &) {
        if (exitCode == 0) {
            requestRefresh();
        } else {
            publishState(false, volume(), muted(), m_defaultOutput);
        }
    });
}

void PactlSystemVolumeBackend::setVolume(double value)
{
    if (!available()) {
        return;
    }
    m_pendingSet = std::clamp(value, 0.0, 1.0);
    m_hasPendingSet = true;
    if (!m_busy && !m_refreshing) {
        beginPendingSet();
    }
}

void PactlSystemVolumeBackend::runCommand(const QStringList &arguments, CommandCallback callback)
{
    if (m_busy || m_executable.isEmpty()) {
        return;
    }
    m_busy = true;
    m_commandCallback = std::move(callback);
    m_commandOperation = arguments.value(0);
    m_command = new QProcess(this);
    connect(m_command, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus) {
        const QString standardOutput = QString::fromLocal8Bit(m_command->readAllStandardOutput());
        const QString standardError = QString::fromLocal8Bit(m_command->readAllStandardError());
        completeCommand(exitCode, standardOutput, standardError);
    });
    connect(m_command, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            completeCommand(-1, {}, m_command ? m_command->errorString() : QString{});
        }
    });
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    m_command->setProcessEnvironment(environment);
    m_command->setProgram(m_executable);
    m_command->setArguments(arguments);
    m_command->start();
    m_commandTimeout->start();
}

void PactlSystemVolumeBackend::completeCommand(int exitCode, const QString &standardOutput,
                                                const QString &standardError)
{
    if (!m_busy) {
        return;
    }
    m_commandTimeout->stop();
    m_busy = false;
    if (exitCode != 0) {
        qCWarning(lcSystemVolume) << "pactl operation failed:" << m_commandOperation << "exit code:" << exitCode;
    }
    m_commandOperation.clear();
    QProcess *finished = m_command;
    m_command = nullptr;
    if (finished) {
        finished->deleteLater();
    }
    CommandCallback callback = std::move(m_commandCallback);
    m_commandCallback = {};
    if (callback) {
        callback(exitCode, standardOutput, standardError);
    }
    if (m_busy || m_refreshing) {
        return;
    }
    if (m_refreshRequested) {
        m_refreshDebounce->start();
    } else if (m_hasPendingSet) {
        beginPendingSet();
    }
}

void PactlSystemVolumeBackend::scheduleReconnect()
{
    if (!m_executable.isEmpty() && !m_reconnectTimer->isActive()) {
        m_reconnectTimer->start();
    }
}

} // namespace kdockw
