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
