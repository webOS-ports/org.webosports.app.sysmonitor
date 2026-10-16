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

import QtQuick
import QtTest

import "../../qml/js/ProcParse.js" as ProcParse
import "../../qml/js/Format.js" as Format

/*
 * qml/js/ProcParse.js and Format.js against what the TouchPad (armv7,
 * Linux 3.4), the mindphone (armv7, 4.14) and the Q25 (aarch64, 5.10)
 * really wrote (tests/fixtures). The expected figures were worked out from
 * the same files with a separate script, not with this code.
 */
TestCase {
    name: "ProcParse"

    function fixture(device, file) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("../fixtures/" + device + "/" + file), false);
        xhr.send();
        verify(xhr.responseText.length > 0, "fixture " + device + "/" + file);
        return xhr.responseText;
    }

    function test_cpu_times_touchpad() {
        var a = ProcParse.parseCpuTimes(fixture("touchpad", "snap-stat-a"));
        var b = ProcParse.parseCpuTimes(fixture("touchpad", "snap-stat-b"));
        compare(a.coreCount, 2);
        var u = ProcParse.cpuUsage(a, b);
        fuzzyCompare(u.total, 3.3113, 0.001);
        compare(u.cores.length, 2);
        fuzzyCompare(u.cores[0], 2.6578, 0.001);
        fuzzyCompare(u.cores[1], 3.9604, 0.001);
        compare(u.ticks, 604);
    }

    function test_cpu_times_mindphone() {
        var u = ProcParse.cpuUsage(ProcParse.parseCpuTimes(fixture("mindphone", "snap-stat-a")),
                                   ProcParse.parseCpuTimes(fixture("mindphone", "snap-stat-b")));
        fuzzyCompare(u.total, 1.9608, 0.001);
        compare(u.cores.length, 4);
        fuzzyCompare(u.cores[0], 4.6358, 0.001);
        compare(u.cores[3], 0);
        compare(u.ticks, 1224);
    }

    function test_cpu_eight_cores_q25() {
        var t = ProcParse.parseCpuTimes(fixture("q25", "stat1"));
        compare(t.coreCount, 8);
        verify(t.total.total > t.total.busy);
    }

    function test_cpu_first_reading_unknown() {
        var u = ProcParse.cpuUsage(null, ProcParse.parseCpuTimes(fixture("touchpad", "stat1")));
        compare(u.total, -1);
        compare(u.cores, [-1, -1]);
        compare(u.ticks, 0);
    }

    function test_cpu_core_switched_off() {
        // Core 1 went away (hotplug) and core 2 came back with a smaller count.
        var a = ProcParse.parseCpuTimes("cpu  100 0 100 800 0 0 0 0 0 0\ncpu0 50 0 50 400 0 0 0 0\ncpu1 50 0 50 400 0 0 0 0\ncpu2 10 0 10 100 0 0 0 0\n");
        var b = ProcParse.parseCpuTimes("cpu  150 0 150 900 0 0 0 0 0 0\ncpu0 100 0 100 500 0 0 0 0\ncpu2 5 0 5 50 0 0 0 0\n");
        var u = ProcParse.cpuUsage(a, b);
        compare(u.cores.length, 3);
        fuzzyCompare(u.cores[0], 50, 0.001);
        compare(u.cores[1], -1);
        compare(u.cores[2], -1);
        fuzzyCompare(u.total, 50, 0.001);
    }

    function test_cpu_garbage() {
        var t = ProcParse.parseCpuTimes("");
        compare(t.total, null);
        compare(t.coreCount, 0);
        compare(ProcParse.cpuUsage(t, t).total, -1);
        compare(ProcParse.busyPercent({ busy: 10, total: 100 }, { busy: 10, total: 100 }), -1);
    }

    function test_meminfo() {
        var m = ProcParse.memorySummary(ProcParse.parseMeminfo(fixture("touchpad", "meminfo")));
        compare(m.total, 864444416);
        compare(m.available, 416366592);
        compare(m.used, 448077824);
        compare(m.swapUsed, 268853248);
        compare(m.cached, 396206080);
        var q = ProcParse.memorySummary(ProcParse.parseMeminfo(fixture("q25", "meminfo")));
        compare(q.total, 12344107008);
        compare(q.used, 2209726464);
        compare(q.swapUsed, 0);
        compare(ProcParse.memorySummary(ProcParse.parseMeminfo(fixture("mindphone", "meminfo"))).used, 845729792);
    }

    function test_meminfo_without_memavailable() {
        // Kernels before 3.14: free + buffers + cache.
        var m = ProcParse.memorySummary(ProcParse.parseMeminfo(
            "MemTotal: 1000 kB\nMemFree: 100 kB\nBuffers: 50 kB\nCached: 200 kB\nSReclaimable: 50 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n"));
        compare(m.available, 400 * 1024);
        compare(m.used, 600 * 1024);
        compare(ProcParse.memorySummary({}).total, 0);
    }

    function test_loadavg_uptime() {
        var l = ProcParse.parseLoadavg(fixture("mindphone", "loadavg"));
        compare(l.one, 18.61);
        compare(l.fifteen, 18.94);
        compare(l.running, 1);
        compare(l.tasks, 1168);
        compare(ProcParse.parseLoadavg(""), null);
        compare(ProcParse.parseUptime(fixture("touchpad", "uptime")), 20602.10);
        compare(ProcParse.parseUptime(""), -1);
        compare(ProcParse.parseUptime("x y"), -1);
    }

    function test_net_dev() {
        var a = ProcParse.parseNetDev(fixture("touchpad", "netdev1"));
        compare(a.length, 5);
        compare(a[0].name, "lo");
        var r = ProcParse.netRates(a, ProcParse.parseNetDev(fixture("touchpad", "netdev2")), 2);
        compare(r.rx, 7881 / 2);
        compare(r.tx, 2072 / 2);
        compare(r.interfaces.length, 1);
        compare(r.interfaces[0].name, "wlan0");
        compare(ProcParse.parseNetDev(fixture("mindphone", "netdev1")).length, 32);
        var m = ProcParse.netRates(ProcParse.parseNetDev(fixture("mindphone", "netdev1")),
                                   ProcParse.parseNetDev(fixture("mindphone", "netdev2")), 1);
        compare(m.rx, 20535);
        compare(m.tx, 66);
    }

    function test_net_dev_odd_lines() {
        // A name run into its first number, a counter that went back, loopback.
        var a = ProcParse.parseNetDev("Inter-|\n face |\n  eth0:1000 1 0 0 0 0 0 0 500 1 0 0 0 0 0 0\n    lo: 9 1 0 0 0 0 0 0 9 1 0 0 0 0 0 0\n");
        var b = ProcParse.parseNetDev("  eth0:400 1 0 0 0 0 0 0 1500 1 0 0 0 0 0 0\n    lo: 99999 1 0 0 0 0 0 0 99999 1 0 0 0 0 0 0\n");
        compare(a.length, 2);
        compare(a[0].rx, 1000);
        var r = ProcParse.netRates(a, b, 2);
        compare(r.rx, 0);
        compare(r.tx, 500);
        compare(ProcParse.netRates(a, b, 0).tx, 0);
    }

    function test_apps_by_pid() {
        var m = ProcParse.appsByPid(JSON.parse(fixture("mindphone", "sam-running.json")));
        compare(m[7241].id, "org.webosports.app.phone");
        compare(m[7305].id, "com.palm.app.email");
        compare(m[7305].type, "web");
        verify(m[7241].instanceId.length > 0);
        compare(Object.keys(m).length, 8);
        // The Q25's Files app has no renderer: no pid to map.
        var q = ProcParse.appsByPid(JSON.parse(fixture("q25", "sam-running.json")));
        compare(Object.keys(q).length, 8);
        compare(Object.keys(ProcParse.appsByPid(null)).length, 0);
    }

    function test_signal_refusal() {
        verify(ProcParse.signalRefusal({ pid: 1, kernelThread: false }, 50) !== "");
        verify(ProcParse.signalRefusal({ pid: 2, kernelThread: true }, 50) !== "");
        verify(ProcParse.signalRefusal({ pid: 50, kernelThread: false }, 50) !== "");
        verify(ProcParse.signalRefusal(null, 50) !== "");
        compare(ProcParse.signalRefusal({ pid: 51, kernelThread: false }, 50), "");
    }

    function test_storage() {
        var mounts = ProcParse.parseMounts(fixture("touchpad", "mounts"));
        verify(mounts.some(function(m) { return m.path === "/media/internal" && m.type === "vfat"; }));
        var c = ProcParse.storageCandidates(mounts);
        compare(c.map(function(e) { return e.path; }), ["/", "/media/internal", "/var"]);
        // A memory card under /media, and a space written as \040.
        var withCard = ProcParse.storageCandidates(ProcParse.parseMounts(
            "/dev/mmcblk1p1 /media/ext vfat rw 0 0\n/dev/x /media/cryptofs ext4 rw 0 0\n/dev/y /media/my\\040card vfat rw 0 0\ntmpfs /media/ram tmpfs rw 0 0\n"));
        compare(withCard.map(function(e) { return e.path; }), ["/", "/media/internal", "/var", "/media/ext", "/media/my card"]);
        var u = ProcParse.uniqueStorage([
            { path: "/", info: { device: "1", total: 10 } },
            { path: "/media/internal", info: { device: "2", total: 20 } },
            { path: "/var", info: { device: "2", total: 20 } },
            { path: "/gone", info: null }
        ]);
        compare(u.map(function(e) { return e.path; }), ["/", "/media/internal"]);
    }

    function test_temperatures() {
        var zones = fixture("mindphone", "thermal").split("\n").filter(function(l) { return l !== ""; });
        var valid = zones.filter(function(l) { return !isNaN(ProcParse.parseTemperature(l.split(" ")[2])); });
        // 28 zones, of which the -127000 ones have no sensor behind them.
        compare(zones.length, 28);
        compare(valid.length, zones.filter(function(l) { return l.indexOf("-127000") < 0; }).length);
        compare(ProcParse.parseTemperature("33600\n"), 33.6);
        compare(ProcParse.parseTemperature("45"), 45);
        verify(isNaN(ProcParse.parseTemperature("-274000")));
        verify(isNaN(ProcParse.parseTemperature("")));
        verify(isNaN(ProcParse.parseTemperature(undefined)));
        verify(isNaN(ProcParse.parseTemperature("abc")));
        compare(ProcParse.thermalZones(["thermal_zone10", "cooling_device0", "thermal_zone2", "thermal_zone0"]),
                ["thermal_zone0", "thermal_zone2", "thermal_zone10"]);
    }

    function test_frequencies() {
        compare(ProcParse.parseFrequency("1728000\n"), 1728);
        compare(ProcParse.parseFrequency(""), 0);
        compare(ProcParse.cpuDirs(["cpu1", "cpufreq", "cpu0", "cpuidle", "cpu10", "online"]), [0, 1, 10]);
    }

    function test_battery() {
        var b = ProcParse.batteryFromStatus(JSON.parse(fixture("mindphone", "battery.json")));
        compare(b.percent, 100);
        compare(b.current_mA, -206);
        compare(b.charging, false);
        compare(b.voltage_mV, 4221);
        compare(b.temperature_C, 26);
        compare(ProcParse.batteryFromStatus({ returnValue: false, errorText: "Denied" }), null);
        var u = ProcParse.batteryFromUevent(fixture("mindphone", "battery-uevent"));
        compare(u.percent, 100);
        compare(u.charging, true);
        compare(u.voltage_mV, 4221);
        compare(u.temperature_C, 26.4);
        compare(ProcParse.batteryFromUevent(""), null);
    }

    function test_memory_level() {
        var m = ProcParse.memoryLevel(JSON.parse(fixture("touchpad", "memstatus.json")));
        compare(m.level, "normal");
        compare(m.totalMB, 824);
        compare(ProcParse.memoryLevel({ returnValue: false }), null);
    }

    function test_history() {
        var h = [];
        for (var i = 0; i < 5; i++)
            h = ProcParse.pushHistory(h, i, 3);
        compare(h, [2, 3, 4]);
    }

    function test_format() {
        compare(Format.bytes(0), "0 B");
        compare(Format.bytes(1536), "1.5 KB");
        compare(Format.bytes(864444416), "824 MB");
        compare(Format.bytes(12344107008), "11.5 GB");
        compare(Format.bytes(-1), "–");
        compare(Format.rate(2048), "2.0 KB/s");
        compare(Format.percent(-1), "–");
        compare(Format.percent(3.3113), "3.3%");
        compare(Format.percent(42.6), "43%");
        compare(Format.duration(20602.1), "5 h 43 min");
        compare(Format.duration(176690.36), "2 d 1 h");
        compare(Format.duration(59), "59 s");
        compare(Format.frequency(1728), "1.73 GHz");
        compare(Format.frequency(384), "384 MHz");
        compare(Format.frequency(0), "off");
        compare(Format.temperature(33.6), "33.6 °C");
        compare(Format.processState("S"), "Sleeping");
        compare(Format.memoryLevel("critical"), "Critical");
    }
}
