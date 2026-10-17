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

import QtQuick
import QtTest

import SysMonitorApp 1.0

import "file:///media/cryptofs/apps/usr/palm/applications/org.webosports.app.sysmonitor/qml/js/ProcParse.js" as ProcParse

/*
 * The plugin and the parsing on a real device, against its real /proc and
 * /sys: run by tools/test-device.sh with qmltestrunner on the device, with
 * the installed app's plugin. It signals one process only: a "sleep 600"
 * the script starts for it, whose pid it reads from sleep.pid next to this file.
 */
TestCase {
    name: "SysMonitorDevice"

    ProcReader {
        id: proc
    }

    ProcessModel {
        id: model
        showKernelThreads: true
    }

    function sleepPid() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("sleep.pid"), false);
        xhr.send();
        var pid = parseInt(xhr.responseText, 10);
        verify(pid > 1, "no sleep.pid");
        return pid;
    }

    function test_overview_files() {
        var t = proc.readFiles(["/proc/stat", "/proc/meminfo", "/proc/loadavg", "/proc/uptime", "/proc/net/dev"]);
        var cpu = ProcParse.parseCpuTimes(t[0]);
        verify(cpu.total !== null && cpu.total.total > 0);
        var cpus = ProcParse.cpuDirs(proc.listDirectory("/sys/devices/system/cpu"));
        verify(cpus.length >= 1 && cpus.length >= cpu.coreCount, cpus.length + " " + cpu.coreCount);
        var mem = ProcParse.memorySummary(ProcParse.parseMeminfo(t[1]));
        verify(mem.total > 64 * 1024 * 1024 && mem.used > 0 && mem.available > 0, JSON.stringify(mem));
        verify(ProcParse.parseLoadavg(t[2]).tasks > 10);
        verify(ProcParse.parseUptime(t[3]) > 0);
        verify(ProcParse.parseNetDev(t[4]).some(function(i) { return i.name === "lo"; }));
        console.info("cores " + cpus.length + ", memory " + mem.total + ", uptime " + ProcParse.parseUptime(t[3]));
    }

    function test_cpu_figures_over_a_second() {
        var a = ProcParse.parseCpuTimes(proc.readFile("/proc/stat"));
        wait(1000);
        var u = ProcParse.cpuUsage(a, ProcParse.parseCpuTimes(proc.readFile("/proc/stat")));
        verify(u.total >= 0 && u.total <= 100, u.total);
        verify(u.ticks > 0);
    }

    function test_thermal_and_frequencies() {
        var zones = ProcParse.thermalZones(proc.listDirectory("/sys/class/thermal"));
        var temps = proc.readFiles(zones.map(function(z) { return "/sys/class/thermal/" + z + "/temp"; }));
        var valid = temps.filter(function(x) { return !isNaN(ProcParse.parseTemperature(x)); });
        console.info(zones.length + " thermal zones, " + valid.length + " with a temperature");
        var cpus = ProcParse.cpuDirs(proc.listDirectory("/sys/devices/system/cpu"));
        var f = proc.readFiles(cpus.map(function(c) { return "/sys/devices/system/cpu/cpu" + c + "/cpufreq/scaling_cur_freq"; }))
            .map(ProcParse.parseFrequency);
        verify(f.some(function(mhz) { return mhz > 0; }), JSON.stringify(f));
    }

    function test_storage() {
        var root = proc.storageInfo("/");
        verify(root.ok && root.total > 0 && root.available <= root.total, JSON.stringify(root));
        var internal = proc.storageInfo("/media/internal");
        verify(internal.ok && internal.total > 0, JSON.stringify(internal));
        var list = ProcParse.uniqueStorage(ProcParse.storageCandidates(ProcParse.parseMounts(proc.readFile("/proc/mounts")))
            .map(function(s) { var i = proc.storageInfo(s.path); return { path: s.path, info: i.ok ? i : null }; }));
        console.info("storage shown: " + list.map(function(s) { return s.path; }).join(", "));
        verify(list.length >= 1);
    }

    function test_reads_only_proc_and_sys() {
        compare(proc.readFile("/etc/passwd"), "");
        compare(proc.readFile("/proc/../etc/passwd"), "");
        compare(proc.listDirectory("/home").length, 0);
    }

    function test_process_model() {
        model.refresh();
        var pids = proc.listDirectory("/proc").filter(function(n) { return /^\d+$/.test(n); }).length;
        // Processes start and end in between: close, not equal.
        verify(Math.abs(model.totalCount - pids) < 20, model.totalCount + " vs " + pids);
        compare(model.get(1).pid, 1);
        verify(model.get(2).kernelThread);
        var self = model.get(proc.ownPid);
        verify(self.cmdline.indexOf("qmltestrunner") >= 0, self.cmdline);
        var s = model.get(sleepPid());
        compare(s.cmdline, "sleep 600");
        compare(s.name, "sleep");
        wait(1000);
        model.refresh();
        verify(model.get(proc.ownPid).cpu >= 0);
        console.info(model.totalCount + " processes, " + model.count + " shown");
    }

    function test_refusals() {
        verify(!proc.sendSignal(1, 0, ProcReader.Terminate).ok);
        var kthreadd = model.get(2);
        verify(!proc.sendSignal(2, kthreadd.startTime, ProcReader.Kill).ok);
        verify(!proc.sendSignal(proc.ownPid, model.get(proc.ownPid).startTime, ProcReader.Kill).ok);
        var pid = sleepPid();
        model.refresh();
        var s = model.get(pid);
        // The wrong start time: a reused pid. Nothing is sent.
        verify(!proc.sendSignal(pid, s.startTime + 1, ProcReader.Terminate).ok);
        wait(200);
        verify(proc.readFile("/proc/" + pid + "/stat") !== "", "the sleep was hit");
    }

    // Last (the test functions run in order of name): ends the sleep.
    function test_zz_end_the_sleep() {
        var pid = sleepPid();
        model.refresh();
        var s = model.get(pid);
        var r = proc.sendSignal(pid, s.startTime, ProcReader.Terminate);
        verify(r.ok, r.error);
        tryVerify(function() {
            var stat = proc.readFile("/proc/" + pid + "/stat");
            return stat === "" || stat.indexOf(") Z ") > 0;
        }, 3000, "the sleep is still running");
    }
}
