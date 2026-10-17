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

#ifndef SYSMONITORAPP_PROCFS_H
#define SYSMONITORAPP_PROCFS_H

#include <QtCore/QByteArray>
#include <QtCore/QByteArrayView>
#include <QtCore/QString>
#include <QtCore/QStringList>

#include <cstdint>
#include <functional>

/*
 * The few things the app cannot do from QML: read /proc and /sys files that
 * report a size of 0, list a directory, read every process's stat file in
 * one go, ask how full a file system is, and send a process a signal.
 *
 * The overview's files are handed to QML as text and parsed there
 * (qml/js/ProcParse.js); the processes are worked out in C++
 * (ProcessModel), which is what made them cheap enough. Only paths under /proc and /sys can be read or listed. Everything is
 * looked up under root, which is "" on a device and a directory of made-up
 * files in the tests.
 */
class ProcFs
{
public:
    // What the app uses of a /proc/<pid>/stat line.
    struct StatFields {
        bool ok = false;
        std::int64_t pid = 0;
        QByteArray comm;            // the kernel's name, at most 15 bytes
        char state = '?';
        std::int64_t ppid = 0;
        std::uint64_t flags = 0;
        std::uint64_t cpuTicks = 0; // utime + stime
        std::int64_t threads = 0;
        std::uint64_t startTime = 0; // clock ticks after boot
        std::uint64_t rssPages = 0;
    };

    struct Storage {
        bool ok = false;
        QString device;          // st_dev, to tell file systems apart
        std::uint64_t total = 0; // bytes
        std::uint64_t free = 0;  // bytes, root's reserve included
        std::uint64_t available = 0; // bytes an ordinary user could still write
    };

    struct SignalResult {
        bool ok = false;
        QString error;
    };

    // How a signal is sent: ::kill on a device, a recorder in the tests.
    using KillFunction = std::function<int(int pid, int sig)>;

    // PF_KTHREAD (include/linux/sched.h, unchanged since Linux 2.6.27).
    static constexpr std::uint64_t KernelThreadFlag = 0x00200000;
    // Larger than any /proc or /sys text file the app reads.
    static constexpr std::size_t MaxFileSize = 256 * 1024;

    explicit ProcFs(QString root = QString(), KillFunction kill = KillFunction());

    // Whether path is an absolute path under /proc or /sys with no "." or
    // ".." components.
    static bool isAllowedPath(const QString &path);

    // The file's contents (at most MaxFileSize bytes), or "" when it is not
    // allowed or cannot be read.
    QString readFile(const QString &path) const;

    // The names in a directory, sorted, without "." and ".."; empty when it is
    // not allowed or cannot be read.
    QStringList listDirectory(const QString &path) const;

    // Every /proc/<pid>/stat, one line each, in /proc's order. Processes that
    // end while this runs are left out.
    QByteArray processStats() const;

    // A file as bytes (at most MaxFileSize), under the same rules as readFile().
    QByteArray readBytes(const QString &path) const;

    // How full the file system holding path is. Any path may be asked about.
    Storage storage(const QString &path) const;

    // The fields of one stat line, counted from the last ")" as the name may
    // hold spaces and parentheses. ok is false for anything else.
    static StatFields parseStatLine(QByteArrayView line);

    static bool isKernelThread(const StatFields &fields)
    {
        return (fields.flags & KernelThreadFlag) != 0 || fields.pid == 2;
    }

    /*
     * Sends SIGTERM or SIGKILL to pid, only if it is still the process that
     * started at startTime (pids are reused) and is neither init, a kernel
     * thread nor ownPid. error says why not.
     */
    SignalResult sendSignal(int pid, std::uint64_t startTime, int sig, int ownPid) const;

private:
    QByteArray localPath(const QString &path) const;
    static bool readAll(int fd, QByteArray *out, std::size_t limit);

    QString m_root;
    KillFunction m_kill;
};

#endif // SYSMONITORAPP_PROCFS_H
