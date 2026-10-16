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

#include "processmodel.h"

#include <QtCore/QList>
#include <QtCore/QStringList>

#include <algorithm>
#include <utility>

#include <unistd.h>

ProcessModel::ProcessModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_ownPid(static_cast<int>(::getpid()))
{
    const long size = ::sysconf(_SC_PAGESIZE);
    if (size > 0)
        m_pageSize = static_cast<int>(size);
}

int ProcessModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : count();
}

QVariant ProcessModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= count())
        return QVariant();
    const int at = m_rows[static_cast<std::size_t>(index.row())];
    if (at < 0 || at >= totalCount())
        return QVariant();
    const Process &p = m_processes[static_cast<std::size_t>(at)];
    switch (role) {
    case PidRole:
        return p.pid;
    case Qt::DisplayRole:
    case NameRole:
        return p.name;
    case DetailRole:
        return detailOf(p);
    case CpuRole:
        return p.cpu;
    case RssRole:
        return static_cast<double>(p.rss);
    case IsAppRole:
        return !p.appId.isEmpty();
    case IsSelfRole:
        return p.pid == m_ownPid;
    case KernelThreadRole:
        return p.kernelThread;
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> ProcessModel::roleNames() const
{
    return {
        {PidRole, "pid"},
        {NameRole, "name"},
        {DetailRole, "detail"},
        {CpuRole, "cpu"},
        {RssRole, "rss"},
        {IsAppRole, "isApp"},
        {IsSelfRole, "isSelf"},
        {KernelThreadRole, "kernelThread"},
    };
}

void ProcessModel::setRootPath(const QString &path)
{
    if (path == m_rootPath)
        return;
    m_rootPath = path;
    m_fs = ProcFs(path);
    m_fixed.clear();
    reset();
    Q_EMIT rootPathChanged();
}

void ProcessModel::setSearchText(const QString &text)
{
    if (text == m_searchText)
        return;
    m_searchText = text;
    std::vector<Process> same = m_processes;
    updateRows(std::move(same));
    Q_EMIT searchTextChanged();
}

void ProcessModel::setSortKey(const QString &key)
{
    if (key == m_sortKey)
        return;
    m_sortKey = key;
    m_sort = key == QLatin1String("memory") ? Sort::Memory
           : key == QLatin1String("name") ? Sort::Name
           : key == QLatin1String("pid") ? Sort::Pid : Sort::Cpu;
    std::vector<Process> same = m_processes;
    updateRows(std::move(same));
    Q_EMIT sortKeyChanged();
}

void ProcessModel::setShowKernelThreads(bool show)
{
    if (show == m_showKernelThreads)
        return;
    m_showKernelThreads = show;
    std::vector<Process> same = m_processes;
    updateRows(std::move(same));
    Q_EMIT showKernelThreadsChanged();
}

void ProcessModel::setApps(const QVariantMap &apps)
{
    if (apps == m_apps)
        return;
    m_apps = apps;
    m_appByPid.clear();
    for (auto it = apps.constBegin(); it != apps.constEnd(); ++it) {
        bool ok = false;
        const int pid = it.key().toInt(&ok);
        const QVariantMap app = it.value().toMap();
        if (ok)
            m_appByPid.insert(pid, {app.value(QStringLiteral("id")).toString(), app.value(QStringLiteral("instanceId")).toString()});
    }
    std::vector<Process> same = m_processes;
    nameProcesses(&same);
    updateRows(std::move(same));
    Q_EMIT appsChanged();
}

void ProcessModel::setOwnPid(int pid)
{
    if (pid == m_ownPid)
        return;
    m_ownPid = pid;
    if (count() > 0)
        Q_EMIT dataChanged(index(0), index(count() - 1), {IsSelfRole});
    Q_EMIT ownPidChanged();
}

void ProcessModel::setPageSize(int size)
{
    if (size <= 0 || size == m_pageSize)
        return;
    m_pageSize = size;
    Q_EMIT pageSizeChanged();
}

quint64 ProcessModel::key(int pid, std::uint64_t startTime)
{
    // Start times are ticks since boot: 2^40 of them is over 300 years at
    // 100 Hz, so pid and start time fit side by side.
    return (static_cast<quint64>(static_cast<std::uint32_t>(pid)) << 40) ^ startTime;
}

std::uint64_t ProcessModel::totalTicks() const
{
    const QByteArray stat = m_fs.readBytes(QStringLiteral("/proc/stat"));
    if (!stat.startsWith("cpu "))
        return 0;
    const qsizetype end = stat.indexOf('\n');
    const QList<QByteArray> fields = stat.left(end < 0 ? stat.size() : end).simplified().split(' ');
    std::uint64_t total = 0;
    // user nice system idle iowait irq softirq steal; guest is in user already.
    for (qsizetype i = 1; i <= 8 && i < fields.size(); ++i) {
        bool ok = false;
        const qulonglong v = fields.at(i).toULongLong(&ok);
        if (ok)
            total += v;
    }
    return total;
}

void ProcessModel::refresh()
{
    const std::uint64_t total = totalTicks();
    const std::uint64_t elapsed = m_lastTotalTicks > 0 && total > m_lastTotalTicks ? total - m_lastTotalTicks : 0;
    const QByteArray all = m_fs.processStats();

    std::vector<Process> processes;
    processes.reserve(m_processes.size() + 16);
    QHash<quint64, std::uint64_t> ticks;
    QHash<quint64, Fixed> fixed;
    ticks.reserve(static_cast<qsizetype>(m_processes.size()) + 16);
    fixed.reserve(static_cast<qsizetype>(m_processes.size()) + 16);

    const QByteArrayView view(all);
    qsizetype start = 0;
    while (start < view.size()) {
        qsizetype end = view.indexOf('\n', start);
        if (end < 0)
            end = view.size();
        const ProcFs::StatFields f = ProcFs::parseStatLine(view.sliced(start, end - start));
        start = end + 1;
        if (!f.ok)
            continue;
        Process p;
        p.pid = static_cast<int>(f.pid);
        p.startTime = f.startTime;
        p.comm = QString::fromUtf8(f.comm);
        p.state = f.state;
        p.ppid = static_cast<int>(f.ppid);
        p.kernelThread = ProcFs::isKernelThread(f);
        p.cpuTicks = f.cpuTicks;
        p.threads = static_cast<int>(f.threads);
        p.rss = f.rssPages * static_cast<std::uint64_t>(m_pageSize);

        const quint64 k = key(p.pid, p.startTime);
        const auto before = m_lastTicks.constFind(k);
        if (before != m_lastTicks.constEnd() && elapsed > 0 && p.cpuTicks >= before.value())
            p.cpu = std::min(100.0, static_cast<double>(p.cpuTicks - before.value()) * 100.0 / static_cast<double>(elapsed));
        ticks.insert(k, p.cpuTicks);

        // A process's command line does not change once it runs: read once.
        const auto known = m_fixed.constFind(k);
        Fixed facts;
        if (known != m_fixed.constEnd()) {
            facts = known.value();
        } else if (!p.kernelThread) {
            facts.cmdline = cmdlineFromRaw(m_fs.readBytes(QStringLiteral("/proc/%1/cmdline").arg(p.pid)));
            facts.cmdlineAppId = appIdFromCmdline(facts.cmdline);
        }
        p.cmdline = facts.cmdline;
        p.cmdlineAppId = facts.cmdlineAppId;
        fixed.insert(k, facts);
        processes.push_back(std::move(p));
    }

    m_lastTicks = std::move(ticks);
    m_fixed = std::move(fixed);
    m_lastTotalTicks = total;
    nameProcesses(&processes);
    const int oldTotal = totalCount();
    updateRows(std::move(processes));
    if (totalCount() != oldTotal)
        Q_EMIT totalCountChanged();
}

void ProcessModel::reset()
{
    m_lastTicks.clear();
    m_lastTotalTicks = 0;
}

void ProcessModel::nameProcesses(std::vector<Process> *processes) const
{
    for (Process &p : *processes) {
        const auto app = m_appByPid.constFind(p.pid);
        if (app != m_appByPid.constEnd()) {
            p.appId = app.value().first;
            p.instanceId = app.value().second;
        } else {
            p.appId = p.cmdlineAppId;
            p.instanceId.clear();
        }
        p.name = displayName(p.comm, p.cmdline, p.appId, p.kernelThread);
    }
}

bool ProcessModel::matches(const Process &p, const QString &needle) const
{
    if (p.kernelThread && !m_showKernelThreads)
        return false;
    if (needle.isEmpty())
        return true;
    return QString::number(p.pid) == needle
            || p.name.contains(needle, Qt::CaseInsensitive)
            || p.cmdline.contains(needle, Qt::CaseInsensitive)
            || p.appId.contains(needle, Qt::CaseInsensitive);
}

bool ProcessModel::lessThan(const Process &a, const Process &b) const
{
    switch (m_sort) {
    case Sort::Memory:
        if (a.rss != b.rss)
            return a.rss > b.rss;
        break;
    case Sort::Name: {
        const int c = a.name.compare(b.name, Qt::CaseInsensitive);
        if (c != 0)
            return c < 0;
        break;
    }
    case Sort::Pid:
        break;
    case Sort::Cpu:
        if (a.cpu != b.cpu)
            return a.cpu > b.cpu;
        break;
    }
    return a.pid < b.pid;
}

void ProcessModel::updateRows(std::vector<Process> processes)
{
    const QString needle = m_searchText.trimmed();
    std::vector<int> rows;
    rows.reserve(processes.size());
    for (std::size_t i = 0; i < processes.size(); ++i) {
        if (matches(processes[i], needle))
            rows.push_back(static_cast<int>(i));
    }
    std::sort(rows.begin(), rows.end(), [this, &processes](int a, int b) {
        return lessThan(processes[static_cast<std::size_t>(a)], processes[static_cast<std::size_t>(b)]);
    });

    // In place: rows off the end first (while the old rows still point into
    // the old processes), then the new processes and the rows both have,
    // then rows onto the end.
    const int oldCount = count();
    const int newCount = static_cast<int>(rows.size());
    if (newCount < oldCount) {
        beginRemoveRows(QModelIndex(), newCount, oldCount - 1);
        m_rows.resize(static_cast<std::size_t>(newCount));
        endRemoveRows();
    }
    const int kept = std::min(oldCount, newCount);
    // Only the rows that changed, and only what changed in them: on the
    // TouchPad telling the list that all of them had took 50-100 ms.
    std::vector<QList<int>> changed(static_cast<std::size_t>(kept));
    for (int i = 0; i < kept; ++i) {
        const auto row = static_cast<std::size_t>(i);
        changed[row] = changedRoles(m_processes[static_cast<std::size_t>(m_rows[row])],
                                    processes[static_cast<std::size_t>(rows[row])]);
    }
    m_processes = std::move(processes);
    m_rows.assign(rows.begin(), rows.begin() + kept);
    for (int first = 0; first < kept;) {
        if (changed[static_cast<std::size_t>(first)].isEmpty()) {
            ++first;
            continue;
        }
        QList<int> roles = changed[static_cast<std::size_t>(first)];
        int last = first;
        while (last + 1 < kept && !changed[static_cast<std::size_t>(last) + 1].isEmpty()) {
            ++last;
            for (const int role : changed[static_cast<std::size_t>(last)]) {
                if (!roles.contains(role))
                    roles.append(role);
            }
        }
        Q_EMIT dataChanged(index(first), index(last), roles);
        first = last + 1;
    }
    if (newCount > oldCount) {
        beginInsertRows(QModelIndex(), oldCount, newCount - 1);
        m_rows = std::move(rows);
        endInsertRows();
    }
    if (newCount != oldCount)
        Q_EMIT countChanged();
}

QString ProcessModel::detailOf(const Process &p)
{
    if (!p.appId.isEmpty() && p.appId != p.name)
        return p.appId;
    if (p.kernelThread)
        return QStringLiteral("kernel");
    // A row shows the start of it, cut short: laying out all of a renderer's
    // two-kilobyte command line to elide it cost the TouchPad a lot.
    return p.cmdline.size() > MaxDetailLength ? p.cmdline.left(MaxDetailLength) : p.cmdline;
}

QList<int> ProcessModel::changedRoles(const Process &before, const Process &now) const
{
    QList<int> roles;
    if (before.pid != now.pid) {
        roles.append(PidRole);
        if ((before.pid == m_ownPid) != (now.pid == m_ownPid))
            roles.append(IsSelfRole);
    }
    if (before.name != now.name) {
        roles.append(NameRole);
        roles.append(Qt::DisplayRole);
    }
    if (detailOf(before) != detailOf(now))
        roles.append(DetailRole);
    if (before.cpu != now.cpu)
        roles.append(CpuRole);
    if (before.rss != now.rss)
        roles.append(RssRole);
    if (before.appId.isEmpty() != now.appId.isEmpty())
        roles.append(IsAppRole);
    if (before.kernelThread != now.kernelThread)
        roles.append(KernelThreadRole);
    return roles;
}

QVariantMap ProcessModel::get(int pid) const
{
    for (const Process &p : m_processes) {
        if (p.pid != pid)
            continue;
        return {
            {QStringLiteral("pid"), p.pid},
            {QStringLiteral("name"), p.name},
            {QStringLiteral("comm"), p.comm},
            {QStringLiteral("cmdline"), p.cmdline},
            {QStringLiteral("appId"), p.appId},
            {QStringLiteral("instanceId"), p.instanceId},
            {QStringLiteral("state"), QString(QLatin1Char(p.state))},
            {QStringLiteral("ppid"), p.ppid},
            {QStringLiteral("kernelThread"), p.kernelThread},
            {QStringLiteral("cpu"), p.cpu},
            {QStringLiteral("rss"), static_cast<double>(p.rss)},
            {QStringLiteral("threads"), p.threads},
            // Exact in a double for over 2^53 ticks.
            {QStringLiteral("startTime"), static_cast<double>(p.startTime)},
        };
    }
    return QVariantMap();
}

int ProcessModel::pidAt(int row) const
{
    if (row < 0 || row >= count())
        return -1;
    return m_processes[static_cast<std::size_t>(m_rows[static_cast<std::size_t>(row)])].pid;
}

QString ProcessModel::appIdFromCmdline(const QString &cmdline)
{
    const QStringList args = cmdline.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    if (args.isEmpty() || args.first().section(QLatin1Char('/'), -1) != QLatin1String("qml-runner"))
        return QString();
    for (qsizetype i = 1; i < args.size(); ++i) {
        if (args.at(i) == QLatin1String("--appid"))
            return i + 1 < args.size() ? args.at(i + 1) : QString();
        if (args.at(i).startsWith(QLatin1String("--appid=")))
            return args.at(i).mid(8);
    }
    return QString();
}

QString ProcessModel::cmdlineFromRaw(const QByteArray &raw)
{
    QString text = QString::fromUtf8(raw);
    text.replace(QChar(0), QLatin1Char(' '));
    return text.trimmed();
}

QString ProcessModel::displayName(const QString &comm, const QString &cmdline, const QString &appId, bool kernelThread)
{
    if (!appId.isEmpty())
        return appId;
    if (kernelThread)
        return QLatin1Char('[') + comm + QLatin1Char(']');
    if (cmdline.isEmpty())
        return comm;
    // The program's file name, if the kernel's (at most 15 characters) name
    // is the start of it; otherwise - a renamed thread such as
    // "Chrome_ChildIOT", or an interpreter - the kernel's name says more.
    const QString first = cmdline.section(QLatin1Char(' '), 0, 0);
    const QString base = first.section(QLatin1Char('/'), -1);
    return !base.isEmpty() && base.startsWith(comm) ? base : comm;
}
