// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include <QObject>
#include <QStringList>

class KDockWSettings;

namespace kdockw
{

/** Persisted launcher-wide style and Windows Start pin state. */
class ApplicationLauncherState final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString style READ style WRITE setStyle NOTIFY styleChanged)
    Q_PROPERTY(QStringList pinnedApplicationIds READ pinnedApplicationIds NOTIFY pinnedApplicationIdsChanged)
    Q_PROPERTY(bool startFavoritesImportAttempted READ startFavoritesImportAttempted CONSTANT)
    Q_PROPERTY(QString startFavoritesImportStatus READ startFavoritesImportStatus NOTIFY startFavoritesImportStatusChanged)

public:
    explicit ApplicationLauncherState(KDockWSettings *settings, QObject *parent = nullptr);

    [[nodiscard]] QString style() const;
    void setStyle(const QString &style);
    [[nodiscard]] QStringList pinnedApplicationIds() const;
    [[nodiscard]] bool startFavoritesImportAttempted() const;
    [[nodiscard]] QString startFavoritesImportStatus() const;

    Q_INVOKABLE bool isPinned(const QString &serviceId) const;
    Q_INVOKABLE void togglePinned(const QString &serviceId);
    Q_INVOKABLE bool movePinned(int fromIndex, int toIndex);
    Q_INVOKABLE bool importPlasmaFavorites(const QStringList &favoriteIds,
                                           const QStringList &availableApplicationIds,
                                           bool sourceAvailable);

Q_SIGNALS:
    void styleChanged();
    void pinnedApplicationIdsChanged();
    void startFavoritesImportStatusChanged();

private:
    QString m_style;
    QStringList m_pinnedApplicationIds;
    QString m_startFavoritesImportStatus = QStringLiteral("notAttempted");
    bool m_startFavoritesImportAttempted = false;
    KDockWSettings *m_settings = nullptr;
};

} // namespace kdockw
