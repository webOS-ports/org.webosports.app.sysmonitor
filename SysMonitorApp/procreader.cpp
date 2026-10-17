/*
 * Copyright (c) 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "procreader.h"

#include <unistd.h>

ProcReader::ProcReader(QObject *parent)
    : QObject(parent)
{
}

void ProcReader::setRootPath(const QString &path)
{
    if (path == m_rootPath)
        return;
    m_rootPath = path;
    m_fs = ProcFs(path);
    Q_EMIT rootPathChanged();
}

int ProcReader::pageSize() const
{
    const long size = ::sysconf(_SC_PAGESIZE);
    return size > 0 ? static_cast<int>(size) : 4096;
}

int ProcReader::clockTicks() const
{
    const long ticks = ::sysconf(_SC_CLK_TCK);
    return ticks > 0 ? static_cast<int>(ticks) : 100;
}

int ProcReader::ownPid() const
{
    return static_cast<int>(::getpid());
}

QString ProcReader::readFile(const QString &path) const
{
    return m_fs.readFile(path);
}

QStringList ProcReader::readFiles(const QStringList &paths) const
{
    QStringList result;
    result.reserve(paths.size());
    for (const QString &path : paths)
        result.append(m_fs.readFile(path));
    return result;
}

QStringList ProcReader::listDirectory(const QString &path) const
{
    return m_fs.listDirectory(path);
}

QVariantMap ProcReader::storageInfo(const QString &path) const
{
    const ProcFs::Storage s = m_fs.storage(path);
    QVariantMap result;
    result.insert(QStringLiteral("ok"), s.ok);
    result.insert(QStringLiteral("device"), s.device);
    // As doubles: exact up to 8 PiB, and what QML gets anyway.
    result.insert(QStringLiteral("total"), static_cast<double>(s.total));
    result.insert(QStringLiteral("free"), static_cast<double>(s.free));
    result.insert(QStringLiteral("available"), static_cast<double>(s.available));
    return result;
}

QVariantMap ProcReader::sendSignal(int pid, double startTime, int sig) const
{
    QVariantMap result;
    ProcFs::SignalResult r;
    if (!(startTime >= 0) || startTime > 9007199254740992.0) {
        r.error = QStringLiteral("The process has already ended.");
    } else {
        r = m_fs.sendSignal(pid, static_cast<std::uint64_t>(startTime), sig, ownPid());
    }
    result.insert(QStringLiteral("ok"), r.ok);
    result.insert(QStringLiteral("error"), r.error);
    return result;
}
