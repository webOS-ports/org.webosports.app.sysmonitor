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

#include <gtest/gtest.h>

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QTemporaryDir>

#include <unistd.h>

namespace {

void writeFile(const QString &path, const QByteArray &data)
{
    ASSERT_TRUE(QDir().mkpath(QFileInfo(path).absolutePath()));
    QFile f(path);
    ASSERT_TRUE(f.open(QIODevice::WriteOnly));
    f.write(data);
}

} // namespace

TEST(ProcReader, Constants)
{
    const ProcReader reader;
    EXPECT_GT(reader.pageSize(), 0);
    EXPECT_GT(reader.clockTicks(), 0);
    EXPECT_EQ(reader.ownPid(), static_cast<int>(::getpid()));
}

TEST(ProcReader, ReadFilesKeepsOrderAndGaps)
{
    QTemporaryDir dir;
    ASSERT_TRUE(dir.isValid());
    writeFile(dir.path() + QStringLiteral("/proc/a"), "A");
    writeFile(dir.path() + QStringLiteral("/sys/b"), "B");
    ProcReader reader;
    int changes = 0;
    QObject::connect(&reader, &ProcReader::rootPathChanged, [&changes]() { ++changes; });
    reader.setRootPath(dir.path());
    reader.setRootPath(dir.path());
    EXPECT_EQ(changes, 1);
    EXPECT_EQ(reader.readFiles({QStringLiteral("/sys/b"), QStringLiteral("/proc/none"), QStringLiteral("/proc/a")}),
              (QStringList{QStringLiteral("B"), QString(), QStringLiteral("A")}));
    EXPECT_EQ(reader.readFile(QStringLiteral("/proc/a")), QStringLiteral("A"));
    EXPECT_EQ(reader.listDirectory(QStringLiteral("/proc")), QStringList{QStringLiteral("a")});
}

TEST(ProcReader, RootPathChangeTakesEffect)
{
    QTemporaryDir one, two;
    writeFile(one.path() + QStringLiteral("/proc/x"), "1");
    writeFile(two.path() + QStringLiteral("/proc/x"), "2");
    ProcReader reader;
    reader.setRootPath(one.path());
    EXPECT_EQ(reader.readFile(QStringLiteral("/proc/x")), QStringLiteral("1"));
    reader.setRootPath(two.path());
    EXPECT_EQ(reader.readFile(QStringLiteral("/proc/x")), QStringLiteral("2"));
}

TEST(ProcReader, StorageInfoMap)
{
    const ProcReader reader;
    const QVariantMap info = reader.storageInfo(QStringLiteral("/"));
    EXPECT_TRUE(info.value(QStringLiteral("ok")).toBool());
    EXPECT_GT(info.value(QStringLiteral("total")).toDouble(), 0.0);
    EXPECT_LE(info.value(QStringLiteral("available")).toDouble(), info.value(QStringLiteral("total")).toDouble());
    EXPECT_FALSE(info.value(QStringLiteral("device")).toString().isEmpty());
    EXPECT_FALSE(reader.storageInfo(QStringLiteral("/no/such/place")).value(QStringLiteral("ok")).toBool());
}

TEST(ProcReader, SignalRefusalsReachQml)
{
    const ProcReader reader;
    QVariantMap r = reader.sendSignal(1, 1, ProcReader::Terminate);
    EXPECT_FALSE(r.value(QStringLiteral("ok")).toBool());
    EXPECT_FALSE(r.value(QStringLiteral("error")).toString().isEmpty());
    r = reader.sendSignal(reader.ownPid(), 0, ProcReader::Kill);
    EXPECT_FALSE(r.value(QStringLiteral("ok")).toBool());
    // A start time QML cannot have meant.
    r = reader.sendSignal(12345, -1, ProcReader::Terminate);
    EXPECT_FALSE(r.value(QStringLiteral("ok")).toBool());
    r = reader.sendSignal(12345, 1e300, ProcReader::Terminate);
    EXPECT_FALSE(r.value(QStringLiteral("ok")).toBool());
}
