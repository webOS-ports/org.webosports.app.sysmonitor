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

#ifndef SYSMONITORAPP_PROCREADER_H
#define SYSMONITORAPP_PROCREADER_H

#include "procfs.h"

#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QVariantMap>

/*
 * ProcFs for QML:
 *
 *     ProcReader { id: proc }
 *     var text = proc.readFile("/proc/meminfo");
 *     var all = proc.readFiles(["/proc/stat", "/proc/loadavg"]);
 *     var info = proc.storageInfo("/media/internal"); // { ok, device, total, free, available }
 *     var r = proc.sendSignal(pid, startTime, ProcReader.Terminate); // { ok, error }
 *
 * rootPath puts every path under another directory, for the tests.
 */
class ProcReader : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString rootPath READ rootPath WRITE setRootPath NOTIFY rootPathChanged)
    Q_PROPERTY(int pageSize READ pageSize CONSTANT)
    Q_PROPERTY(int clockTicks READ clockTicks CONSTANT)
    Q_PROPERTY(int ownPid READ ownPid CONSTANT)

public:
    enum Signal { Terminate = 15, Kill = 9 };
    Q_ENUM(Signal)

    explicit ProcReader(QObject *parent = nullptr);

    QString rootPath() const { return m_rootPath; }
    void setRootPath(const QString &path);

    int pageSize() const;
    int clockTicks() const;
    int ownPid() const;

    Q_INVOKABLE QString readFile(const QString &path) const;
    Q_INVOKABLE QStringList readFiles(const QStringList &paths) const;
    Q_INVOKABLE QStringList listDirectory(const QString &path) const;
    Q_INVOKABLE QVariantMap storageInfo(const QString &path) const;
    // startTime is a double: QML numbers are, and start times do not need
    // more than its 53 bits.
    Q_INVOKABLE QVariantMap sendSignal(int pid, double startTime, int sig) const;

Q_SIGNALS:
    void rootPathChanged();

private:
    QString m_rootPath;
    ProcFs m_fs;
};

#endif // SYSMONITORAPP_PROCREADER_H
