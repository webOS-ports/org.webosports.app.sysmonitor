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

#include "procfs.h"


#include <algorithm>
#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <utility>

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

namespace {

// RAII for a file descriptor.
class Fd
{
public:
    explicit Fd(int fd) : m_fd(fd) {}
    ~Fd()
    {
        if (m_fd >= 0)
            ::close(m_fd);
    }
    Fd(const Fd &) = delete;
    Fd &operator=(const Fd &) = delete;
    int get() const { return m_fd; }

private:
    int m_fd;
};

// RAII for a directory stream.
class Dir
{
public:
    explicit Dir(DIR *dir) : m_dir(dir) {}
    ~Dir()
    {
        if (m_dir)
            ::closedir(m_dir);
    }
    Dir(const Dir &) = delete;
    Dir &operator=(const Dir &) = delete;
    DIR *get() const { return m_dir; }

private:
    DIR *m_dir;
};

bool isPidName(const char *name)
{
    if (*name == '\0')
        return false;
    for (const char *c = name; *c != '\0'; ++c) {
        if (*c < '0' || *c > '9')
            return false;
    }
    return true;
}

// The n bytes at s as an unsigned number, or false.
bool parseUnsigned(const char *s, qsizetype n, std::uint64_t *out)
{
    if (n <= 0)
        return false;
    std::uint64_t v = 0;
    for (qsizetype i = 0; i < n; ++i) {
        const char c = s[i];
        if (c < '0' || c > '9')
            return false;
        const std::uint64_t digit = static_cast<std::uint64_t>(c - '0');
        if (v > (UINT64_MAX - digit) / 10)
            return false;
        v = v * 10 + digit;
    }
    *out = v;
    return true;
}

// The n bytes at s as a number that may be negative, or false.
bool parseSigned(const char *s, qsizetype n, std::int64_t *out)
{
    const bool negative = n > 0 && s[0] == '-';
    std::uint64_t v = 0;
    if (!parseUnsigned(negative ? s + 1 : s, negative ? n - 1 : n, &v) || v > static_cast<std::uint64_t>(INT64_MAX))
        return false;
    *out = negative ? -static_cast<std::int64_t>(v) : static_cast<std::int64_t>(v);
    return true;
}

bool isBlank(char c)
{
    return c == ' ' || c == '\n' || c == '\t' || c == '\r';
}

} // namespace

ProcFs::ProcFs(QString root, KillFunction kill)
    : m_root(std::move(root))
    , m_kill(kill ? std::move(kill) : KillFunction([](int pid, int sig) { return ::kill(pid, sig); }))
{
}

bool ProcFs::isAllowedPath(const QString &path)
{
    if (!path.startsWith(QLatin1String("/proc/")) && !path.startsWith(QLatin1String("/sys/"))
            && path != QLatin1String("/proc") && path != QLatin1String("/sys"))
        return false;
    if (path.contains(QChar(0)))
        return false;
    const QStringList parts = path.split(QLatin1Char('/'));
    return std::none_of(parts.cbegin(), parts.cend(), [](const QString &part) {
        return part == QLatin1String(".") || part == QLatin1String("..");
    });
}

QByteArray ProcFs::localPath(const QString &path) const
{
    return (m_root + path).toLocal8Bit();
}

bool ProcFs::readAll(int fd, QByteArray *out, std::size_t limit)
{
    // Each read() asks for at most sizeof(buffer) bytes.
    char buffer[4096]; // Flawfinder: ignore
    while (static_cast<std::size_t>(out->size()) < limit) {
        const std::size_t want = std::min(sizeof(buffer), limit - static_cast<std::size_t>(out->size()));
        const ssize_t n = ::read(fd, buffer, want); // Flawfinder: ignore (want <= sizeof(buffer))
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return false;
        }
        if (n == 0)
            break;
        out->append(buffer, static_cast<qsizetype>(n));
    }
    return true;
}

QByteArray ProcFs::readBytes(const QString &path) const
{
    if (!isAllowedPath(path))
        return QByteArray();
    // Read-only, under /proc or /sys only (isAllowedPath), never a symlink
    // at the end, nothing checked first that could change before the open.
    const Fd fd(::open(localPath(path).constData(), O_RDONLY | O_CLOEXEC | O_NOCTTY | O_NOFOLLOW)); // Flawfinder: ignore
    if (fd.get() < 0)
        return QByteArray();
    QByteArray data;
    if (!readAll(fd.get(), &data, MaxFileSize))
        return QByteArray();
    return data;
}

QString ProcFs::readFile(const QString &path) const
{
    return QString::fromUtf8(readBytes(path));
}

QStringList ProcFs::listDirectory(const QString &path) const
{
    QStringList names;
    if (!isAllowedPath(path))
        return names;
    const Dir dir(::opendir(localPath(path).constData()));
    if (!dir.get())
        return names;
    // readdir() is safe on a stream no other thread uses, as this one is.
    while (const struct dirent *entry = ::readdir(dir.get())) { // NOLINT(concurrency-mt-unsafe)
        if (std::strcmp(entry->d_name, ".") == 0 || std::strcmp(entry->d_name, "..") == 0)
            continue;
        names.append(QString::fromLocal8Bit(entry->d_name));
    }
    names.sort();
    return names;
}

QByteArray ProcFs::processStats() const
{
    const Dir proc(::opendir(localPath(QStringLiteral("/proc")).constData()));
    if (!proc.get())
        return QByteArray();
    const int procFd = ::dirfd(proc.get());
    if (procFd < 0)
        return QByteArray();
    QByteArray all;
    all.reserve(qsizetype(64) * 1024);
    QByteArray one;
    // readdir() is safe on a stream no other thread uses, as this one is.
    while (const struct dirent *entry = ::readdir(proc.get())) { // NOLINT(concurrency-mt-unsafe)
        if (!isPidName(entry->d_name))
            continue;
        // A pid and "/stat"; snprintf is bounded and its result checked.
        char name[64]; // Flawfinder: ignore
        const int len = std::snprintf(name, sizeof(name), "%s/stat", entry->d_name);
        if (len <= 0 || static_cast<std::size_t>(len) >= sizeof(name))
            continue;
        const Fd fd(::openat(procFd, name, O_RDONLY | O_CLOEXEC | O_NOCTTY | O_NOFOLLOW));
        if (fd.get() < 0)
            continue; // ended meanwhile
        one.clear();
        if (!readAll(fd.get(), &one, 4096) || one.isEmpty())
            continue;
        all.append(one);
        if (!one.endsWith('\n'))
            all.append('\n');
    }
    return all;
}

ProcFs::Storage ProcFs::storage(const QString &path) const
{
    Storage result;
    const QByteArray local = localPath(path);
    struct statvfs fs;
    struct stat st;
    if (::statvfs(local.constData(), &fs) != 0 || ::stat(local.constData(), &st) != 0)
        return result;
    const std::uint64_t unit = fs.f_frsize ? fs.f_frsize : fs.f_bsize;
    result.ok = true;
    result.device = QString::number(static_cast<quint64>(st.st_dev));
    result.total = static_cast<std::uint64_t>(fs.f_blocks) * unit;
    result.free = static_cast<std::uint64_t>(fs.f_bfree) * unit;
    result.available = static_cast<std::uint64_t>(fs.f_bavail) * unit;
    return result;
}

ProcFs::StatFields ProcFs::parseStatLine(QByteArrayView line)
{
    // Read in place, field by field: this runs for every process on every
    // reading, so no copies and no lists.
    StatFields result;
    const qsizetype nameStart = line.indexOf('(');
    const qsizetype nameEnd = line.lastIndexOf(')');
    if (nameStart < 1 || nameEnd < nameStart || nameEnd + 2 > line.size())
        return result;
    const char *data = line.data();
    qsizetype pidStart = 0;
    qsizetype pidEnd = nameStart;
    while (pidStart < pidEnd && isBlank(data[pidStart]))
        ++pidStart;
    while (pidEnd > pidStart && isBlank(data[pidEnd - 1]))
        --pidEnd;
    std::uint64_t pid = 0;
    if (!parseUnsigned(data + pidStart, pidEnd - pidStart, &pid) || pid > INT32_MAX)
        return result;

    // Field 3 (the state) onwards, separated by single spaces; field n is
    // number n - 3 here.
    qsizetype pos = nameEnd + 2;
    qsizetype end = line.size();
    while (pos < end && isBlank(data[pos]))
        ++pos;
    while (end > pos && isBlank(data[end - 1]))
        --end;
    std::uint64_t utime = 0;
    std::uint64_t stime = 0;
    int field = 0;
    qsizetype start = pos;
    for (qsizetype i = pos; field < 22; ++i) {
        if (i < end && data[i] != ' ')
            continue;
        const char *token = data + start;
        const qsizetype n = i - start;
        bool ok = true;
        switch (field) {
        case 0:
            ok = n == 1;
            if (ok)
                result.state = token[0];
            break;
        case 1: ok = parseSigned(token, n, &result.ppid); break;
        case 6: ok = parseUnsigned(token, n, &result.flags); break;
        case 11: ok = parseUnsigned(token, n, &utime); break;
        case 12: ok = parseUnsigned(token, n, &stime); break;
        case 17: ok = parseSigned(token, n, &result.threads); break;
        case 19: ok = parseUnsigned(token, n, &result.startTime); break;
        case 21: ok = parseUnsigned(token, n, &result.rssPages); break;
        default: break;
        }
        if (!ok)
            return result;
        ++field;
        if (i >= end)
            break;
        start = i + 1;
    }
    if (field < 22)
        return result;
    result.pid = static_cast<std::int64_t>(pid);
    result.comm = line.sliced(nameStart + 1, nameEnd - nameStart - 1).toByteArray();
    result.cpuTicks = utime + stime;
    result.ok = true;
    return result;
}

ProcFs::SignalResult ProcFs::sendSignal(int pid, std::uint64_t startTime, int sig, int ownPid) const
{
    SignalResult result;
    if (sig != SIGTERM && sig != SIGKILL) {
        result.error = QStringLiteral("Only ending (SIGTERM) and killing (SIGKILL) are offered.");
        return result;
    }
    if (pid <= 1) {
        result.error = QStringLiteral("init (process 1) cannot be ended.");
        return result;
    }
    if (pid == ownPid) {
        result.error = QStringLiteral("System Monitor does not end itself.");
        return result;
    }
    const StatFields fields = parseStatLine(readBytes(QStringLiteral("/proc/%1/stat").arg(pid)));
    if (!fields.ok || fields.pid != pid) {
        result.error = QStringLiteral("The process has already ended.");
        return result;
    }
    if (isKernelThread(fields)) {
        result.error = QStringLiteral("Kernel threads cannot be ended.");
        return result;
    }
    if (fields.startTime != startTime) {
        result.error = QStringLiteral("The process has already ended; its number now belongs to another one.");
        return result;
    }
    if (m_kill(pid, sig) != 0) {
        const int err = errno;
        result.error = err == ESRCH ? QStringLiteral("The process has already ended.")
                                    : qt_error_string(err);
        return result;
    }
    result.ok = true;
    return result;
}
