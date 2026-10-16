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

#include <gtest/gtest.h>

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QTemporaryDir>
#include <QtTest/QAbstractItemModelTester>
#include <QtTest/QSignalSpy>

#include <memory>

/*
 * ProcessModel against the processes captured on the devices
 * (tests/fixtures/<device>/snap-*: /proc/stat and every /proc/<pid>/stat,
 * twice, three seconds apart), laid out as a /proc under a temporary
 * directory. The figures expected were worked out from the same files with
 * a separate script.
 */
namespace {

QByteArray fixture(const QString &device, const QString &name)
{
    QFile f(QStringLiteral(FIXTURES_DIR "/") + device + QLatin1Char('/') + name);
    EXPECT_TRUE(f.open(QIODevice::ReadOnly)) << f.fileName().toStdString();
    return f.readAll();
}

void writeFile(const QString &path, const QByteArray &data)
{
    ASSERT_TRUE(QDir().mkpath(QFileInfo(path).absolutePath()));
    QFile f(path);
    ASSERT_TRUE(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
    ASSERT_EQ(f.write(data), data.size());
}

class FakeProc
{
public:
    QString path() const { return m_dir.path(); }

    // A /proc as it was: /proc/stat, each process's stat, and the command
    // lines (NUL-separated, as the kernel writes them) of those still known.
    void load(const QString &device, const QString &phase)
    {
        QDir(m_dir.path() + QStringLiteral("/proc")).removeRecursively();
        writeFile(m_dir.path() + QStringLiteral("/proc/stat"), fixture(device, QStringLiteral("snap-stat-") + phase));
        QHash<QByteArray, QByteArray> cmdlines;
        for (const QByteArray &line : fixture(device, QStringLiteral("cmdlines")).split('\n')) {
            const qsizetype tab = line.indexOf('\t');
            if (tab > 0)
                cmdlines.insert(line.left(tab), line.mid(tab + 1).trimmed().replace(' ', '\0') + '\0');
        }
        for (const QByteArray &line : fixture(device, QStringLiteral("snap-pids-") + phase).split('\n')) {
            const qsizetype open = line.indexOf(" (");
            if (open <= 0)
                continue;
            const QByteArray pid = line.left(open);
            const QString dir = m_dir.path() + QStringLiteral("/proc/") + QString::fromLatin1(pid);
            writeFile(dir + QStringLiteral("/stat"), line + '\n');
            writeFile(dir + QStringLiteral("/cmdline"), cmdlines.value(pid));
        }
    }

    void write(const QString &relative, const QByteArray &data) const { writeFile(m_dir.path() + relative, data); }

private:
    QTemporaryDir m_dir;
};

// The stat line of pid in a device's snapshot.
QByteArray fixtureLine(const QString &device, const QString &file, int pid)
{
    const QByteArray prefix = QByteArray::number(pid) + " (";
    for (const QByteArray &line : fixture(device, file).split('\n')) {
        if (line.startsWith(prefix))
            return line;
    }
    return QByteArray();
}

// The same line with another rss (field 24).
QByteArray rssChanged(const QByteArray &line, int pages)
{
    const qsizetype close = line.lastIndexOf(')');
    QList<QByteArray> fields = line.mid(close + 2).split(' ');
    fields[21] = QByteArray::number(pages);
    return line.left(close + 2) + fields.join(' ') + '\n';
}

class ProcessModelTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        model = std::make_unique<ProcessModel>();
        // Every change the model announces is checked against what it then
        // holds.
        tester = std::make_unique<QAbstractItemModelTester>(model.get(), QAbstractItemModelTester::FailureReportingMode::Fatal);
        model->setRootPath(proc.path());
        model->setPageSize(4096);
        model->setOwnPid(1);
    }

    // Two readings, three seconds apart.
    void readTwice(const QString &device)
    {
        proc.load(device, QStringLiteral("a"));
        model->refresh();
        proc.load(device, QStringLiteral("b"));
        model->refresh();
    }

    int rowOf(int pid) const
    {
        for (int i = 0; i < model->rowCount(); ++i) {
            if (model->pidAt(i) == pid)
                return i;
        }
        return -1;
    }

    QVariant value(int row, int role) const { return model->data(model->index(row), role); }

    FakeProc proc;
    std::unique_ptr<ProcessModel> model;
    std::unique_ptr<QAbstractItemModelTester> tester;
};

} // namespace

TEST_F(ProcessModelTest, TouchPadProcesses)
{
    readTwice(QStringLiteral("touchpad"));
    // 325 processes, 176 of them kernel threads, left out by default.
    EXPECT_EQ(model->totalCount(), 325);
    EXPECT_EQ(model->count(), 149);
    model->setShowKernelThreads(true);
    EXPECT_EQ(model->count(), 325);
}

TEST_F(ProcessModelTest, CpuShareOfTheWholeDevice)
{
    readTwice(QStringLiteral("touchpad"));
    // dbus-daemon took 4 of the 604 ticks both cores passed.
    EXPECT_EQ(model->pidAt(0), 756);
    EXPECT_NEAR(value(0, ProcessModel::CpuRole).toDouble(), 0.6623, 0.001);
    EXPECT_EQ(value(0, ProcessModel::NameRole).toString(), QStringLiteral("dbus-daemon"));
    // Then avahi-daemon: 2 ticks, as two others, and the lowest pid of them.
    EXPECT_EQ(model->pidAt(1), 742);
    model->setShowKernelThreads(true);
    EXPECT_EQ(model->pidAt(1), 1758);
    EXPECT_NEAR(model->get(1758).value(QStringLiteral("cpu")).toDouble(), 0.4967, 0.001);
}

TEST_F(ProcessModelTest, MindphoneProcesses)
{
    readTwice(QStringLiteral("mindphone"));
    model->setShowKernelThreads(true);
    EXPECT_EQ(model->totalCount(), 576);
    EXPECT_EQ(model->pidAt(0), 6476);
    EXPECT_NEAR(value(0, ProcessModel::CpuRole).toDouble(), 0.3268, 0.001);
}

TEST_F(ProcessModelTest, FirstReadingHasNoShares)
{
    proc.load(QStringLiteral("touchpad"), QStringLiteral("a"));
    model->refresh();
    EXPECT_EQ(model->get(756).value(QStringLiteral("cpu")).toDouble(), -1.0);
    // Sorted by pid when nothing is known.
    EXPECT_EQ(model->pidAt(0), 1);
}

TEST_F(ProcessModelTest, ResetForgetsTheLastReading)
{
    proc.load(QStringLiteral("touchpad"), QStringLiteral("a"));
    model->refresh();
    model->reset();
    proc.load(QStringLiteral("touchpad"), QStringLiteral("b"));
    model->refresh();
    EXPECT_EQ(model->get(756).value(QStringLiteral("cpu")).toDouble(), -1.0);
}

TEST_F(ProcessModelTest, ReusedPidIsANewProcess)
{
    readTwice(QStringLiteral("touchpad"));
    // dbus-daemon gone, another process under its number.
    proc.write(QStringLiteral("/proc/756/stat"),
               "756 (other) S 1 756 756 0 -1 4194560 0 0 0 0 900 900 0 0 20 0 1 0 2000000 1000 25 4294967295 0 0 0\n");
    model->refresh();
    EXPECT_EQ(model->get(756).value(QStringLiteral("cpu")).toDouble(), -1.0);
    EXPECT_EQ(model->get(756).value(QStringLiteral("startTime")).toDouble(), 2000000.0);
}

TEST_F(ProcessModelTest, MemoryAndOtherSorts)
{
    readTwice(QStringLiteral("touchpad"));
    model->setSortKey(QStringLiteral("memory"));
    EXPECT_EQ(model->pidAt(0), 2540);
    EXPECT_EQ(value(0, ProcessModel::NameRole).toString(), QStringLiteral("surface-manager"));
    EXPECT_EQ(value(0, ProcessModel::RssRole).toDouble(), 103350272.0);
    model->setSortKey(QStringLiteral("pid"));
    EXPECT_EQ(model->pidAt(0), 1);
    for (int i = 1; i < model->count(); ++i)
        EXPECT_LT(model->pidAt(i - 1), model->pidAt(i));
    model->setSortKey(QStringLiteral("name"));
    for (int i = 1; i < model->count(); ++i) {
        EXPECT_LE(value(i - 1, ProcessModel::NameRole).toString().compare(value(i, ProcessModel::NameRole).toString(), Qt::CaseInsensitive), 0);
    }
}

TEST_F(ProcessModelTest, Search)
{
    readTwice(QStringLiteral("touchpad"));
    model->setSearchText(QStringLiteral("  DBUS "));
    ASSERT_GE(model->count(), 1);
    for (int i = 0; i < model->count(); ++i) {
        const QVariantMap p = model->get(model->pidAt(i));
        EXPECT_TRUE(p.value(QStringLiteral("name")).toString().contains(QStringLiteral("dbus"), Qt::CaseInsensitive)
                    || p.value(QStringLiteral("cmdline")).toString().contains(QStringLiteral("dbus"), Qt::CaseInsensitive));
    }
    // A number finds that process only, not every pid with those digits.
    model->setSearchText(QStringLiteral("756"));
    EXPECT_EQ(model->count(), 1);
    EXPECT_EQ(model->pidAt(0), 756);
    // Two pids hold "66" and no name or command line does: no match.
    model->setSearchText(QStringLiteral("66"));
    EXPECT_EQ(model->count(), 0);
    model->setSearchText(QStringLiteral("no such thing"));
    EXPECT_EQ(model->count(), 0);
    model->setSearchText(QString());
    EXPECT_EQ(model->count(), 149);
}

TEST_F(ProcessModelTest, AppsFromSamAndQmlRunner)
{
    readTwice(QStringLiteral("touchpad"));
    // The phone is a qml-runner: known from its command line alone.
    EXPECT_EQ(model->get(3335).value(QStringLiteral("appId")).toString(), QStringLiteral("org.webosports.app.phone"));
    EXPECT_TRUE(value(rowOf(3335), ProcessModel::IsAppRole).toBool());
    // A web app's renderer only from SAM.
    EXPECT_EQ(model->get(3565).value(QStringLiteral("appId")).toString(), QString());
    model->setApps({{QStringLiteral("3565"), QVariantMap{{QStringLiteral("id"), QStringLiteral("com.palm.app.email")},
                                                         {QStringLiteral("instanceId"), QStringLiteral("i-1")}}}});
    const QVariantMap email = model->get(3565);
    EXPECT_EQ(email.value(QStringLiteral("appId")).toString(), QStringLiteral("com.palm.app.email"));
    EXPECT_EQ(email.value(QStringLiteral("instanceId")).toString(), QStringLiteral("i-1"));
    EXPECT_EQ(email.value(QStringLiteral("name")).toString(), QStringLiteral("com.palm.app.email"));
    // The renderer's command line, cut short for the row.
    EXPECT_EQ(value(rowOf(3565), ProcessModel::DetailRole).toString(),
              email.value(QStringLiteral("cmdline")).toString().left(ProcessModel::MaxDetailLength));
    model->setSearchText(QStringLiteral("palm.app.email"));
    EXPECT_EQ(model->count(), 1);
}

TEST_F(ProcessModelTest, KernelThreadsAndSelf)
{
    readTwice(QStringLiteral("touchpad"));
    model->setShowKernelThreads(true);
    const QVariantMap kthreadd = model->get(2);
    EXPECT_TRUE(kthreadd.value(QStringLiteral("kernelThread")).toBool());
    EXPECT_EQ(kthreadd.value(QStringLiteral("name")).toString(), QStringLiteral("[kthreadd]"));
    EXPECT_EQ(value(rowOf(2), ProcessModel::DetailRole).toString(), QStringLiteral("kernel"));
    EXPECT_TRUE(value(rowOf(1), ProcessModel::IsSelfRole).toBool());
    model->setOwnPid(756);
    EXPECT_FALSE(value(rowOf(1), ProcessModel::IsSelfRole).toBool());
    EXPECT_TRUE(value(rowOf(756), ProcessModel::IsSelfRole).toBool());
}

TEST_F(ProcessModelTest, LongCommandLinesCutShortInRows)
{
    proc.load(QStringLiteral("touchpad"), QStringLiteral("a"));
    const QByteArray longLine = "/usr/bin/WebAppMgr" + QByteArray(1000, 'x');
    proc.write(QStringLiteral("/proc/756/cmdline"), longLine);
    model->refresh();
    EXPECT_EQ(value(rowOf(756), ProcessModel::DetailRole).toString().size(), ProcessModel::MaxDetailLength);
    EXPECT_EQ(model->get(756).value(QStringLiteral("cmdline")).toString().size(), longLine.size());
}

TEST_F(ProcessModelTest, CommandLineReadOnce)
{
    proc.load(QStringLiteral("touchpad"), QStringLiteral("a"));
    model->refresh();
    proc.write(QStringLiteral("/proc/756/cmdline"), QByteArray("/changed\0", 9));
    model->refresh();
    EXPECT_TRUE(model->get(756).value(QStringLiteral("cmdline")).toString().startsWith(QStringLiteral("/usr/bin/dbus-daemon --system")));
}

TEST_F(ProcessModelTest, ProcessesComeAndGo)
{
    proc.load(QStringLiteral("touchpad"), QStringLiteral("a"));
    model->refresh();
    const int before = model->count();
    proc.write(QStringLiteral("/proc/40000/stat"),
               "40000 (newcomer) R 1 40000 40000 0 -1 4194560 0 0 0 0 1 1 0 0 20 0 1 0 2100000 1000 25 4294967295 0 0 0\n");
    model->refresh();
    EXPECT_EQ(model->count(), before + 1);
    QDir(proc.path() + QStringLiteral("/proc/40000")).removeRecursively();
    QDir(proc.path() + QStringLiteral("/proc/756")).removeRecursively();
    model->refresh();
    EXPECT_EQ(model->count(), before - 1);
    EXPECT_TRUE(model->get(756).isEmpty());
    EXPECT_TRUE(model->get(40000).isEmpty());
    EXPECT_EQ(model->pidAt(-1), -1);
    EXPECT_EQ(model->pidAt(model->count()), -1);
    EXPECT_FALSE(model->data(model->index(model->count()), ProcessModel::PidRole).isValid());
}

TEST_F(ProcessModelTest, OnlyChangedRowsAreAnnounced)
{
    readTwice(QStringLiteral("touchpad"));
    // The same files again: no time passed, so no shares; once that is
    // shown, nothing is left to tell.
    model->refresh();
    QSignalSpy changes(model.get(), &QAbstractItemModel::dataChanged);
    model->refresh();
    EXPECT_EQ(changes.count(), 0);

    // One process uses more memory: its row, its memory, nothing else.
    model->setSortKey(QStringLiteral("pid"));
    changes.clear();
    const int row = rowOf(1157);
    ASSERT_GE(row, 0);
    proc.write(QStringLiteral("/proc/1157/stat"),
               rssChanged(fixtureLine(QStringLiteral("touchpad"), QStringLiteral("snap-pids-b"), 1157), 999));
    model->refresh();
    ASSERT_EQ(changes.count(), 1);
    const QList<QVariant> args = changes.at(0);
    EXPECT_EQ(args.at(0).toModelIndex().row(), row);
    EXPECT_EQ(args.at(1).toModelIndex().row(), row);
    EXPECT_EQ(args.at(2).value<QList<int>>(), QList<int>{ProcessModel::RssRole});
    EXPECT_EQ(value(row, ProcessModel::RssRole).toDouble(), 999.0 * 4096);
}

TEST_F(ProcessModelTest, RoleNamesForQml)
{
    const QHash<int, QByteArray> roles = model->roleNames();
    EXPECT_EQ(roles.value(ProcessModel::PidRole), QByteArray("pid"));
    EXPECT_EQ(roles.value(ProcessModel::CpuRole), QByteArray("cpu"));
    EXPECT_EQ(roles.value(ProcessModel::IsSelfRole), QByteArray("isSelf"));
    EXPECT_EQ(roles.size(), 8);
}

TEST_F(ProcessModelTest, NoProc)
{
    QTemporaryDir empty;
    model->setRootPath(empty.path());
    model->refresh();
    EXPECT_EQ(model->count(), 0);
    EXPECT_EQ(model->totalCount(), 0);
}

TEST(ProcessModelFixtures, EveryLineOfEveryDevice)
{
    // Every process line the three devices wrote parses, and the kernel
    // threads are the ones the separate script counted.
    const struct {
        const char *device;
        int lines;
        int kernelThreads;
    } devices[] = {{"touchpad", 318, 173}, {"mindphone", 577, 388}, {"q25", 659, 456}};
    for (const auto &d : devices) {
        int lines = 0;
        int ok = 0;
        int kernel = 0;
        for (const QByteArray &line : fixture(QString::fromLatin1(d.device), QStringLiteral("pid-stats")).split('\n')) {
            if (line.isEmpty())
                continue;
            ++lines;
            const ProcFs::StatFields f = ProcFs::parseStatLine(line);
            ok += f.ok ? 1 : 0;
            kernel += f.ok && ProcFs::isKernelThread(f) ? 1 : 0;
        }
        EXPECT_EQ(lines, d.lines) << d.device;
        EXPECT_EQ(ok, d.lines) << d.device;
        EXPECT_EQ(kernel, d.kernelThreads) << d.device;
    }
}

TEST(ProcessModelText, AppIdFromCmdline)
{
    EXPECT_EQ(ProcessModel::appIdFromCmdline(QStringLiteral("/usr/bin/qml-runner --appid org.webosports.app.phone {\"x\":1}")),
              QStringLiteral("org.webosports.app.phone"));
    EXPECT_EQ(ProcessModel::appIdFromCmdline(QStringLiteral("qml-runner -v --appid=org.x.y")), QStringLiteral("org.x.y"));
    EXPECT_EQ(ProcessModel::appIdFromCmdline(QStringLiteral("/usr/bin/WebAppMgr --type=renderer")), QString());
    EXPECT_EQ(ProcessModel::appIdFromCmdline(QStringLiteral("/usr/bin/not-qml-runner2 --appid x")), QString());
    EXPECT_EQ(ProcessModel::appIdFromCmdline(QStringLiteral("/usr/bin/qml-runner --appid")), QString());
    EXPECT_EQ(ProcessModel::appIdFromCmdline(QStringLiteral("sh -c qml-runner --appid x")), QString());
    EXPECT_EQ(ProcessModel::appIdFromCmdline(QString()), QString());
}

TEST(ProcessModelText, CmdlineFromRaw)
{
    EXPECT_EQ(ProcessModel::cmdlineFromRaw(QByteArray("/bin/a\0-x\0b c\0", 13)), QStringLiteral("/bin/a -x b c"));
    EXPECT_EQ(ProcessModel::cmdlineFromRaw(QByteArray()), QString());
}

TEST(ProcessModelText, DisplayName)
{
    EXPECT_EQ(ProcessModel::displayName(QStringLiteral("luna-next-cards"), QStringLiteral("/usr/bin/luna-next-cardshell -x"), QString(), false),
              QStringLiteral("luna-next-cardshell"));
    EXPECT_EQ(ProcessModel::displayName(QStringLiteral("Chrome_ChildIOT"), QStringLiteral("/usr/bin/WebAppMgr --type=renderer"), QString(), false),
              QStringLiteral("Chrome_ChildIOT"));
    EXPECT_EQ(ProcessModel::displayName(QStringLiteral("kworker/0:1"), QString(), QString(), true), QStringLiteral("[kworker/0:1]"));
    EXPECT_EQ(ProcessModel::displayName(QStringLiteral("zombie"), QString(), QString(), false), QStringLiteral("zombie"));
    EXPECT_EQ(ProcessModel::displayName(QStringLiteral("qml-runner"), QStringLiteral("/usr/bin/qml-runner"), QStringLiteral("org.x"), false),
              QStringLiteral("org.x"));
}
