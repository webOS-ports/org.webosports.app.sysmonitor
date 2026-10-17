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

#include <gtest/gtest.h>

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QTemporaryDir>

#include <cerrno>
#include <csignal>
#include <vector>

#include <sys/wait.h>
#include <unistd.h>

namespace {

// A made-up /proc and /sys under a temporary directory.
class FakeRoot
{
public:
    FakeRoot() { EXPECT_TRUE(m_dir.isValid()); }

    QString path() const { return m_dir.path(); }

    void write(const QString &relative, const QByteArray &data) const
    {
        const QString full = m_dir.path() + relative;
        ASSERT_TRUE(QDir().mkpath(QFileInfo(full).absolutePath()));
        QFile f(full);
        ASSERT_TRUE(f.open(QIODevice::WriteOnly));
        ASSERT_EQ(f.write(data), data.size());
    }

    void mkdir(const QString &relative) const { ASSERT_TRUE(QDir().mkpath(m_dir.path() + relative)); }

private:
    QTemporaryDir m_dir;
};

// A stat line as the kernel writes it, with the fields that matter set.
QByteArray statLine(int pid, const char *comm, unsigned long long flags, unsigned long long start)
{
    return QByteArray::number(pid) + " (" + comm + ") S 1 " + QByteArray::number(pid) + " 0 0 -1 "
            + QByteArray::number(flags) + " 10 0 0 0 5 7 0 0 20 0 1 0 " + QByteArray::number(start)
            + " 1000 25 4294967295 0 0 0\n";
}

struct KillCall {
    int pid;
    int sig;
};

} // namespace

TEST(ProcFsPath, AllowsOnlyProcAndSys)
{
    EXPECT_TRUE(ProcFs::isAllowedPath(QStringLiteral("/proc/stat")));
    EXPECT_TRUE(ProcFs::isAllowedPath(QStringLiteral("/proc")));
    EXPECT_TRUE(ProcFs::isAllowedPath(QStringLiteral("/sys/class/thermal/thermal_zone0/temp")));
    EXPECT_FALSE(ProcFs::isAllowedPath(QStringLiteral("/etc/passwd")));
    EXPECT_FALSE(ProcFs::isAllowedPath(QStringLiteral("/procfoo/x")));
    EXPECT_FALSE(ProcFs::isAllowedPath(QStringLiteral("/system/x")));
    EXPECT_FALSE(ProcFs::isAllowedPath(QStringLiteral("proc/stat")));
    EXPECT_FALSE(ProcFs::isAllowedPath(QString()));
}

TEST(ProcFsPath, RefusesDotDotAndNul)
{
    EXPECT_FALSE(ProcFs::isAllowedPath(QStringLiteral("/proc/../etc/shadow")));
    EXPECT_FALSE(ProcFs::isAllowedPath(QStringLiteral("/sys/class/..")));
    EXPECT_FALSE(ProcFs::isAllowedPath(QStringLiteral("/proc/./stat")));
    EXPECT_FALSE(ProcFs::isAllowedPath(QStringLiteral("/proc/stat") + QChar(0) + QStringLiteral("x")));
    // ".." inside a name is just a name.
    EXPECT_TRUE(ProcFs::isAllowedPath(QStringLiteral("/sys/a..b")));
}

TEST(ProcFsRead, ReadsUnderRoot)
{
    FakeRoot root;
    root.write(QStringLiteral("/proc/meminfo"), "MemTotal: 1 kB\n");
    const ProcFs fs(root.path());
    EXPECT_EQ(fs.readFile(QStringLiteral("/proc/meminfo")), QStringLiteral("MemTotal: 1 kB\n"));
    EXPECT_EQ(fs.readFile(QStringLiteral("/proc/missing")), QString());
}

TEST(ProcFsRead, RefusesOtherPathsEvenIfPresent)
{
    FakeRoot root;
    root.write(QStringLiteral("/etc/secret"), "no");
    root.write(QStringLiteral("/proc/x"), "yes");
    const ProcFs fs(root.path());
    EXPECT_EQ(fs.readFile(QStringLiteral("/etc/secret")), QString());
    EXPECT_EQ(fs.readFile(QStringLiteral("/proc/../etc/secret")), QString());
    EXPECT_EQ(fs.readFile(QStringLiteral("/proc/x")), QStringLiteral("yes"));
}

TEST(ProcFsRead, StopsAtTheLimit)
{
    FakeRoot root;
    root.write(QStringLiteral("/sys/big"), QByteArray(ProcFs::MaxFileSize + 5000, 'a'));
    const ProcFs fs(root.path());
    EXPECT_EQ(fs.readFile(QStringLiteral("/sys/big")).size(), static_cast<qsizetype>(ProcFs::MaxFileSize));
}

TEST(ProcFsRead, ReadsRealProcFilesThatReportNoSize)
{
    // /proc files say st_size 0; the whole text must come back anyway.
    const ProcFs fs;
    const QString stat = fs.readFile(QStringLiteral("/proc/self/stat"));
    EXPECT_TRUE(stat.startsWith(QString::number(::getpid()) + QStringLiteral(" (")));
    EXPECT_TRUE(fs.readFile(QStringLiteral("/proc/meminfo")).contains(QStringLiteral("MemTotal:")));
}

TEST(ProcFsList, SortedWithoutDots)
{
    FakeRoot root;
    root.write(QStringLiteral("/sys/class/thermal/thermal_zone1/temp"), "1");
    root.write(QStringLiteral("/sys/class/thermal/thermal_zone0/temp"), "1");
    root.write(QStringLiteral("/sys/class/thermal/cooling_device0"), "");
    const ProcFs fs(root.path());
    EXPECT_EQ(fs.listDirectory(QStringLiteral("/sys/class/thermal")),
              (QStringList{QStringLiteral("cooling_device0"), QStringLiteral("thermal_zone0"), QStringLiteral("thermal_zone1")}));
    EXPECT_TRUE(fs.listDirectory(QStringLiteral("/sys/none")).isEmpty());
}

TEST(ProcFsList, RefusesOtherPaths)
{
    FakeRoot root;
    root.write(QStringLiteral("/home/a"), "");
    const ProcFs fs(root.path());
    EXPECT_TRUE(fs.listDirectory(QStringLiteral("/home")).isEmpty());
}

TEST(ProcFsProcesses, EveryPidOnce)
{
    FakeRoot root;
    root.write(QStringLiteral("/proc/1/stat"), statLine(1, "systemd", 0, 1));
    // No newline at the end: one is added.
    root.write(QStringLiteral("/proc/22/stat"), statLine(22, "a b) (c", 0, 2).trimmed());
    root.write(QStringLiteral("/proc/333/stat"), statLine(333, "kworker/0:1", ProcFs::KernelThreadFlag, 3));
    // Not processes: a name with letters, a pid directory without stat, an
    // empty stat (the process ended), and a plain file named like a pid.
    root.write(QStringLiteral("/proc/acpi/stat"), "nope\n");
    root.mkdir(QStringLiteral("/proc/44"));
    root.write(QStringLiteral("/proc/55/stat"), "");
    root.write(QStringLiteral("/proc/66"), "file");
    root.write(QStringLiteral("/proc/stat"), "cpu 1 2 3\n");
    const ProcFs fs(root.path());
    QStringList lines = QString::fromUtf8(fs.processStats()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    lines.sort();
    ASSERT_EQ(lines.size(), 3);
    EXPECT_TRUE(lines.at(0).startsWith(QStringLiteral("1 (systemd)")));
    EXPECT_TRUE(lines.at(1).startsWith(QStringLiteral("22 (a b) (c)")));
    EXPECT_TRUE(lines.at(2).startsWith(QStringLiteral("333 (kworker/0:1)")));
}

TEST(ProcFsProcesses, RealProcHoldsThisProcess)
{
    const ProcFs fs;
    const QString all = QString::fromUtf8(fs.processStats());
    EXPECT_TRUE(all.contains(QLatin1Char('\n') + QString::number(::getpid()) + QStringLiteral(" (")) ||
                all.startsWith(QString::number(::getpid()) + QStringLiteral(" (")));
    EXPECT_TRUE(all.endsWith(QLatin1Char('\n')));
}

TEST(ProcFsProcesses, NoProcIsEmpty)
{
    FakeRoot root;
    const ProcFs fs(root.path());
    EXPECT_TRUE(fs.processStats().isEmpty());
}

TEST(ProcFsStorage, RealRoot)
{
    const ProcFs fs;
    const ProcFs::Storage s = fs.storage(QStringLiteral("/"));
    ASSERT_TRUE(s.ok);
    EXPECT_GT(s.total, 0u);
    EXPECT_LE(s.free, s.total);
    EXPECT_LE(s.available, s.free);
    EXPECT_FALSE(s.device.isEmpty());
}

TEST(ProcFsStorage, SameFileSystemSameDevice)
{
    FakeRoot root;
    root.mkdir(QStringLiteral("/a"));
    root.mkdir(QStringLiteral("/b"));
    const ProcFs fs(root.path());
    const ProcFs::Storage a = fs.storage(QStringLiteral("/a"));
    const ProcFs::Storage b = fs.storage(QStringLiteral("/b"));
    ASSERT_TRUE(a.ok);
    ASSERT_TRUE(b.ok);
    EXPECT_EQ(a.device, b.device);
    // /proc is a file system of its own.
    const ProcFs real;
    EXPECT_NE(real.storage(QStringLiteral("/proc")).device, real.storage(QStringLiteral("/")).device);
}

TEST(ProcFsStorage, MissingPath)
{
    FakeRoot root;
    const ProcFs fs(root.path());
    EXPECT_FALSE(fs.storage(QStringLiteral("/not/there")).ok);
}

TEST(ProcFsStat, Fields)
{
    const ProcFs::StatFields f = ProcFs::parseStatLine(statLine(4242, "qml-runner", 4210944, 6251));
    ASSERT_TRUE(f.ok);
    EXPECT_EQ(f.pid, 4242);
    EXPECT_EQ(f.comm, QByteArray("qml-runner"));
    EXPECT_EQ(f.state, 'S');
    EXPECT_EQ(f.ppid, 1);
    EXPECT_EQ(f.flags, 4210944u);
    // utime 5 + stime 7.
    EXPECT_EQ(f.cpuTicks, 12u);
    EXPECT_EQ(f.threads, 1);
    EXPECT_EQ(f.startTime, 6251u);
    EXPECT_EQ(f.rssPages, 25u);
    EXPECT_FALSE(ProcFs::isKernelThread(f));
}

TEST(ProcFsStat, NameWithParenthesesAndSpaces)
{
    const ProcFs::StatFields f = ProcFs::parseStatLine(statLine(7, ") (x) S 9 9", 1, 99));
    ASSERT_TRUE(f.ok);
    EXPECT_EQ(f.comm, QByteArray(") (x) S 9 9"));
    EXPECT_EQ(f.flags, 1u);
    EXPECT_EQ(f.startTime, 99u);
}

TEST(ProcFsStat, RealKernelLines)
{
    // From the devices (tests/fixtures): kthreadd on the mindphone, a
    // 64-bit kernel's line on the Q25.
    const ProcFs::StatFields k = ProcFs::parseStatLine(
        "2 (kthreadd) S 0 0 0 0 -1 2129984 0 0 0 0 0 18 0 0 20 0 1 0 8 0 0 4294967295 0 0 0 0 0 0 0 2147483647 0 1 0 0 0 2 0 0 0 0 0 0 0 0 0 0 0 0 0\n");
    ASSERT_TRUE(k.ok);
    EXPECT_NE(k.flags & ProcFs::KernelThreadFlag, 0u);
    EXPECT_TRUE(ProcFs::isKernelThread(k));
    EXPECT_EQ(k.ppid, 0);
    EXPECT_EQ(k.startTime, 8u);
    const ProcFs::StatFields q = ProcFs::parseStatLine(
        "1018 (scsi_eh_0) S 2 0 0 0 -1 2129984 0 0 0 0 0 0 0 0 20 0 1 0 394 0 0 18446744073709551615 0 0 0 0 0 0 0 2147483647 0 1 0 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n");
    ASSERT_TRUE(q.ok);
    EXPECT_EQ(q.startTime, 394u);
}

TEST(ProcFsStat, Garbage)
{
    EXPECT_FALSE(ProcFs::parseStatLine(QByteArray()).ok);
    EXPECT_FALSE(ProcFs::parseStatLine("x (a) S 1 2 3").ok);
    EXPECT_FALSE(ProcFs::parseStatLine("12 (short) S 1 2 3\n").ok);
    EXPECT_FALSE(ProcFs::parseStatLine("12 no parentheses at all S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20").ok);
    EXPECT_FALSE(ProcFs::parseStatLine("(a) S 1 1 0 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 5 0 0").ok);
    // A pid beyond int, and a number that overflows 64 bits.
    EXPECT_FALSE(ProcFs::parseStatLine(statLine(1, "x", 0, 0).replace(0, 1, "99999999999")).ok);
    EXPECT_FALSE(ProcFs::parseStatLine(
        "5 (x) S 1 1 0 0 -1 99999999999999999999999 0 0 0 0 0 0 0 0 20 0 1 0 5 0 0").ok);
    // A state of more than one letter, a field that is not a number.
    EXPECT_FALSE(ProcFs::parseStatLine("5 (x) SS 1 1 0 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 5 0 0").ok);
    EXPECT_FALSE(ProcFs::parseStatLine("5 (x) S 1 1 0 0 -1 0 0 0 0 0 a 0 0 0 20 0 1 0 5 0 0").ok);
}

class ProcFsSignal : public ::testing::Test
{
protected:
    void SetUp() override
    {
        root.write(QStringLiteral("/proc/500/stat"), statLine(500, "sleep", 4194560, 1234));
        root.write(QStringLiteral("/proc/2/stat"), statLine(2, "kthreadd", 0, 8));
        root.write(QStringLiteral("/proc/600/stat"), statLine(600, "kworker/0:1", 69238880, 50));
        root.write(QStringLiteral("/proc/700/stat"), statLine(700, "self", 0, 60));
    }

    ProcFs fs()
    {
        return ProcFs(root.path(), [this](int pid, int sig) {
            calls.push_back({pid, sig});
            errno = nextErrno;
            return nextErrno == 0 ? 0 : -1;
        });
    }

    FakeRoot root;
    std::vector<KillCall> calls;
    int nextErrno = 0;
};

TEST_F(ProcFsSignal, SendsToTheSameProcess)
{
    const ProcFs::SignalResult r = fs().sendSignal(500, 1234, SIGTERM, 700);
    EXPECT_TRUE(r.ok) << r.error.toStdString();
    ASSERT_EQ(calls.size(), 1u);
    EXPECT_EQ(calls[0].pid, 500);
    EXPECT_EQ(calls[0].sig, SIGTERM);
    EXPECT_TRUE(fs().sendSignal(500, 1234, SIGKILL, 700).ok);
    EXPECT_EQ(calls.back().sig, SIGKILL);
}

TEST_F(ProcFsSignal, OnlyTermAndKill)
{
    EXPECT_FALSE(fs().sendSignal(500, 1234, SIGHUP, 700).ok);
    EXPECT_FALSE(fs().sendSignal(500, 1234, SIGSTOP, 700).ok);
    EXPECT_FALSE(fs().sendSignal(500, 1234, 0, 700).ok);
    EXPECT_TRUE(calls.empty());
}

TEST_F(ProcFsSignal, NeverInitNorNegativePids)
{
    root.write(QStringLiteral("/proc/1/stat"), statLine(1, "systemd", 0, 1));
    EXPECT_FALSE(fs().sendSignal(1, 1, SIGTERM, 700).ok);
    EXPECT_FALSE(fs().sendSignal(0, 0, SIGTERM, 700).ok);
    // kill(-1) would signal every process.
    EXPECT_FALSE(fs().sendSignal(-1, 0, SIGKILL, 700).ok);
    EXPECT_FALSE(fs().sendSignal(-500, 1234, SIGKILL, 700).ok);
    EXPECT_TRUE(calls.empty());
}

TEST_F(ProcFsSignal, NeverKernelThreads)
{
    const ProcFs::SignalResult r = fs().sendSignal(600, 50, SIGKILL, 700);
    EXPECT_FALSE(r.ok);
    EXPECT_TRUE(r.error.contains(QStringLiteral("Kernel")));
    // kthreadd by its pid, even without the flag.
    EXPECT_FALSE(fs().sendSignal(2, 8, SIGKILL, 700).ok);
    EXPECT_TRUE(calls.empty());
}

TEST_F(ProcFsSignal, NeverItself)
{
    EXPECT_FALSE(fs().sendSignal(700, 60, SIGTERM, 700).ok);
    EXPECT_TRUE(calls.empty());
}

TEST_F(ProcFsSignal, NotAReusedPid)
{
    const ProcFs::SignalResult r = fs().sendSignal(500, 1233, SIGTERM, 700);
    EXPECT_FALSE(r.ok);
    EXPECT_TRUE(r.error.contains(QStringLiteral("another")));
    EXPECT_TRUE(calls.empty());
}

TEST_F(ProcFsSignal, EndedProcess)
{
    EXPECT_FALSE(fs().sendSignal(501, 1234, SIGTERM, 700).ok);
    nextErrno = ESRCH;
    const ProcFs::SignalResult r = fs().sendSignal(500, 1234, SIGTERM, 700);
    EXPECT_FALSE(r.ok);
    EXPECT_TRUE(r.error.contains(QStringLiteral("ended")));
}

TEST_F(ProcFsSignal, KillFailureSaysWhy)
{
    nextErrno = EPERM;
    const ProcFs::SignalResult r = fs().sendSignal(500, 1234, SIGTERM, 700);
    EXPECT_FALSE(r.ok);
    EXPECT_FALSE(r.error.isEmpty());
}

TEST(ProcFsRealSignal, EndsOwnChild)
{
    // A child of the test's own that just waits: the only process the
    // test signals for real.
    const pid_t child = ::fork();
    ASSERT_GE(child, 0);
    if (child == 0) {
        ::pause();
        ::_exit(3);
    }
    const ProcFs fs;
    ProcFs::StatFields f;
    for (int i = 0; i < 100 && !f.ok; ++i)
        f = ProcFs::parseStatLine(fs.readFile(QStringLiteral("/proc/%1/stat").arg(child)).toUtf8());
    ASSERT_TRUE(f.ok);
    // The wrong start time first: nothing may happen to it.
    EXPECT_FALSE(fs.sendSignal(child, f.startTime + 1, SIGTERM, ::getpid()).ok);
    const ProcFs::SignalResult r = fs.sendSignal(child, f.startTime, SIGTERM, ::getpid());
    EXPECT_TRUE(r.ok) << r.error.toStdString();
    int status = 0;
    ASSERT_EQ(::waitpid(child, &status, 0), child);
    EXPECT_TRUE(WIFSIGNALED(status));
    EXPECT_EQ(WTERMSIG(status), SIGTERM);
}
