// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include "dockentriesmodel.h"

#include <QAbstractListModel>
#include <QVariantList>
#ifdef KDOCKW_DIAGNOSTIC_BUILD
#include <QElapsedTimer>
class QTimer;
#endif

namespace kdockw
{

/**
 * Presents pinned Task and FolderStack entries in their saved order, followed
 * by unpinned TaskManager rows when launcher separation is enabled. When it is
 * disabled, Task rows follow TaskManager order and FolderStacks stay anchored
 * to their neighboring saved launcher entries.
 *
 * TaskManager remains the source of all task/window data. This model only
 * adapts its root rows to the dock's mixed pinned sequence.
 */
class DockPresentationModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int pinnedEntryCount READ pinnedEntryCount NOTIFY pinnedEntryCountChanged)

public:
    enum Role {
        TaskIndexRole = Qt::UserRole + 256,
        EntryIdRole,
        EntryTypeRole,
        EntryUrlRole,
        IconNameRole,
        IconUrlRole,
        WidgetKindRole,
        PlacementSlotRole,
        IsPinnedRole,
        WidgetSizeRole,
        WidgetVisibleRole,
        IconIsCustomRole,
    };
    Q_ENUM(Role)

    DockPresentationModel(QAbstractItemModel *tasksModel, DockEntriesModel *entriesModel, QObject *parent = nullptr,
                         bool diagnosticsEnabled = false);

    [[nodiscard]] int rowCount(const QModelIndex &parent = {}) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;
    [[nodiscard]] int pinnedEntryCount() const;
    void setSeparateLaunchers(bool separate);
    void setMediaPlayerAvailable(bool available);
    void setMediaPlayerDisplayMode(int mode);
    void setMediaPlayerExpandedWidth(int width);

    Q_INVOKABLE int taskIndexForDockIndex(int dockIndex) const;
    Q_INVOKABLE int dockIndexForTaskIndex(int taskIndex) const;
    Q_INVOKABLE int dockIndexForEntryId(const QString &entryId) const;
    Q_INVOKABLE QString entryIdForDockIndex(int dockIndex) const;
    Q_INVOKABLE bool isPinnedDockIndex(int dockIndex) const;
    Q_INVOKABLE QVariantList zoomLayoutSpecs(int iconSize) const;

Q_SIGNALS:
    void pinnedEntryCountChanged();

private:
    struct Row {
        QString key;
        QString entryId;
        QString entryType;
        QUrl entryUrl;
        QString iconName;
        QUrl iconUrl;
        QString widgetKind;
        QString placementSlot = QStringLiteral("center");
        int widgetSize = 0;
        bool widgetVisible = true;
        bool iconIsCustom = false;
        int taskIndex = -1;
        bool pinned = false;

        bool operator==(const Row &) const = default;
    };

    [[nodiscard]] QList<Row> desiredRows() const;
    [[nodiscard]] QString taskKey(int taskIndex, const QString &entryId = {}) const;
    [[nodiscard]] int rowForTaskIndex(int taskIndex) const;
    void scheduleRebuild();
    void rebuild();
    void forwardTaskDataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight, const QList<int> &roles);
    void forwardTaskRowsChanged(const QModelIndex &parent, int first, int last);

    QAbstractItemModel *m_tasksModel = nullptr;
    DockEntriesModel *m_entriesModel = nullptr;
    bool m_diagnosticsEnabled = false;
    bool m_separateLaunchers = true;
    bool m_mediaPlayerAvailable = false;
    int m_mediaPlayerDisplayMode = 0;
    int m_mediaPlayerExpandedWidth = 250;
    QList<Row> m_rows;
    QVector<int> m_taskToDock;
    int m_pinnedEntryCount = 0;
    bool m_rebuildScheduled = false;
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    bool m_performanceDiagnosticsEnabled = false;
    QTimer *m_performanceReportTimer = nullptr;
    QElapsedTimer m_performanceClock;
    quint64 m_sourceDataChanges = 0;
    quint64 m_sourceRowsInserted = 0;
    quint64 m_sourceRowsRemoved = 0;
    quint64 m_sourceRowsMoved = 0;
    quint64 m_sourceLayoutChanges = 0;
    quint64 m_sourceModelResets = 0;
    quint64 m_rebuilds = 0;
    quint64 m_rebuildNanos = 0;
    quint64 m_rebuildMaxNanos = 0;
    quint64 m_forwardedRows = 0;
    quint64 m_dataHandlerNanos = 0;
    quint64 m_dataHandlerMaxNanos = 0;
    quint64 m_launcherRoleChanges = 0;
    quint64 m_identityRoleChanges = 0;
    quint64 m_decorationRoleChanges = 0;
    quint64 m_attentionRoleChanges = 0;
    quint64 m_otherRoleChanges = 0;
#endif
};

} // namespace kdockw
