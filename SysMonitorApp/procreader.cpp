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
