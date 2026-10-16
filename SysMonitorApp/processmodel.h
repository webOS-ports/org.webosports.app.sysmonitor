/*
 * Copyright (c) 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef SYSMONITORAPP_PROCESSMODEL_H
#define SYSMONITORAPP_PROCESSMODEL_H

#include "procfs.h"

#include <QtCore/QAbstractListModel>
#include <QtCore/QHash>
#include <QtCore/QList>
#include <QtCore/QVariantMap>

#include <cstdint>
#include <utility>
#include <vector>

/*
 * The processes, for the list: what each one is (its app, its command
 * line), its share of the CPU since the last refresh() and its memory,
 * filtered and sorted.
 *
 *     ProcessModel {
 *         id: processes
 *         searchText: searchField.text
 *         sortKey: "cpu"          // "memory", "name", "pid"
 *         showKernelThreads: false
 *         apps: { "1234": { "id": "org.example.app", "instanceId": "..." } }
 *     }
 *     processes.refresh()         // on every reading
 *     processes.get(pid)          // one process, as a map
 *
 * The CPU share is of the whole device: the process's ticks over the ticks
 * every core passed (from /proc/stat, read with the processes), so 100 is
 * every core busy with it. A process seen for the first time has -1.
 *
 * This is C++ rather than JavaScript because it has to be cheap: on the
 * TouchPad (Linux 3.4, armv7, two cores) the same work in QML's JavaScript
 * took about 150 ms for 326 processes on every reading.
 *
 * Rows are updated in place - the first rows changed, rows added or taken
 * off the end - so the list neither jumps nor makes its delegates anew.
 */
class ProcessModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QString rootPath READ rootPath WRITE setRootPath NOTIFY rootPathChanged)
    Q_PROPERTY(QString searchText READ searchText WRITE setSearchText NOTIFY searchTextChanged)
    Q_PROPERTY(QString sortKey READ sortKey WRITE setSortKey NOTIFY sortKeyChanged)
    Q_PROPERTY(bool showKernelThreads READ showKernelThreads WRITE setShowKernelThreads NOTIFY showKernelThreadsChanged)
    Q_PROPERTY(QVariantMap apps READ apps WRITE setApps NOTIFY appsChanged)
    Q_PROPERTY(int ownPid READ ownPid WRITE setOwnPid NOTIFY ownPidChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
    Q_PROPERTY(int pageSize READ pageSize WRITE setPageSize NOTIFY pageSizeChanged)

public:
    enum Roles {
        PidRole = Qt::UserRole + 1,
        NameRole,
        DetailRole,
        CpuRole,
        RssRole,
        IsAppRole,
        IsSelfRole,
        KernelThreadRole
    };

    // How much of a command line a row shows (get() has all of it).
    static constexpr int MaxDetailLength = 160;

    explicit ProcessModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString rootPath() const { return m_rootPath; }
    void setRootPath(const QString &path);
    QString searchText() const { return m_searchText; }
    void setSearchText(const QString &text);
    QString sortKey() const { return m_sortKey; }
    void setSortKey(const QString &key);
    bool showKernelThreads() const { return m_showKernelThreads; }
    void setShowKernelThreads(bool show);
    QVariantMap apps() const { return m_apps; }
    void setApps(const QVariantMap &apps);
    int ownPid() const { return m_ownPid; }
    void setOwnPid(int pid);
    int count() const { return static_cast<int>(m_rows.size()); }
    int totalCount() const { return static_cast<int>(m_processes.size()); }
    int pageSize() const { return m_pageSize; }
    void setPageSize(int size);

    // Reads every process again.
    Q_INVOKABLE void refresh();
    // Forgets the last reading: the next refresh() has no CPU shares.
    Q_INVOKABLE void reset();
    /*
     * One process: { pid, name, comm, cmdline, appId, instanceId, state,
     * ppid, kernelThread, cpu, rss, threads, startTime }, or {} if it is not
     * in the last reading.
     */
    Q_INVOKABLE QVariantMap get(int pid) const;
    // The pid of the row, or -1.
    Q_INVOKABLE int pidAt(int row) const;

    // What a qml-runner command line says the app is ("--appid <id>"), or "".
    static QString appIdFromCmdline(const QString &cmdline);
    // The command line from /proc/<pid>/cmdline: NULs as spaces, trimmed.
    static QString cmdlineFromRaw(const QByteArray &raw);
    // What to call a process: its app, its program's file name, its comm.
    static QString displayName(const QString &comm, const QString &cmdline, const QString &appId, bool kernelThread);

Q_SIGNALS:
    void rootPathChanged();
    void searchTextChanged();
    void sortKeyChanged();
    void showKernelThreadsChanged();
    void appsChanged();
    void ownPidChanged();
    void countChanged();
    void totalCountChanged();
    void pageSizeChanged();

private:
    struct Process {
        int pid = 0;
        std::uint64_t startTime = 0;
        QString comm;
        char state = '?';
        int ppid = 0;
        bool kernelThread = false;
        std::uint64_t cpuTicks = 0;
        int threads = 0;
        std::uint64_t rss = 0; // bytes
        double cpu = -1;
        QString cmdline;
        QString cmdlineAppId;
        QString appId;
        QString instanceId;
        QString name;
    };

    static quint64 key(int pid, std::uint64_t startTime);
    // The ticks every core has passed since boot (the "cpu" line), or 0.
    std::uint64_t totalTicks() const;
    // Each process's app (m_apps, or its qml-runner command line) and name.
    void nameProcesses(std::vector<Process> *processes) const;
    // Makes processes the model's, filtered and sorted into m_rows, and tells
    // the view.
    void updateRows(std::vector<Process> processes);
    bool matches(const Process &p, const QString &needle) const;
    // The second line of a row: the app's id, or the command line.
    static QString detailOf(const Process &p);
    // The roles in which a row showing before would differ showing now.
    QList<int> changedRoles(const Process &before, const Process &now) const;
    bool lessThan(const Process &a, const Process &b) const;

    QString m_rootPath;
    ProcFs m_fs;
    QString m_searchText;
    QString m_sortKey = QStringLiteral("cpu");
    bool m_showKernelThreads = false;
    QVariantMap m_apps;
    int m_ownPid = 0;
    int m_pageSize = 4096;

    std::vector<Process> m_processes;
    // Indexes into m_processes, as shown.
    std::vector<int> m_rows;
    // What does not change while a process runs: read and worked out once.
    struct Fixed {
        QString cmdline;
        QString cmdlineAppId; // appIdFromCmdline(cmdline)
    };
    enum class Sort { Cpu, Memory, Name, Pid };

    // From the last refresh, by key(): each process's ticks and fixed facts.
    QHash<quint64, std::uint64_t> m_lastTicks;
    QHash<quint64, Fixed> m_fixed;
    // m_apps by pid.
    QHash<int, std::pair<QString, QString>> m_appByPid;
    Sort m_sort = Sort::Cpu;
    std::uint64_t m_lastTotalTicks = 0;
};

#endif // SYSMONITORAPP_PROCESSMODEL_H
