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

/*
 * A stand-in for the plugin's ProcReader over files captured on the
 * devices (tests/fixtures/<device>): what the app reads is served from
 * there, and signals are recorded rather than sent.
 *
 * Two readings of /proc/stat and the processes were taken three seconds
 * apart on each device; phase "a" serves the first, "b" the second.
 */
QtObject {
    id: reader

    property string rootPath: ""
    readonly property int pageSize: 4096
    readonly property int clockTicks: 100
    property int ownPid: 99999

    property string device: "touchpad"
    property string phase: "a"
    // Paths whose text a test has set, ahead of the device's.
    property var overrides: ({})
    // Paths that read nothing (a file that went away).
    property var missing: ({})
    // Every sendSignal(): { pid, startTime, sig }.
    property var signalsSent: []
    // The reply sendSignal() gives.
    property var signalReply: ({ ok: true, error: "" })
    // How many times each kind of read happened, to see what is polled.
    property int processReads: 0
    property int fileReads: 0
    // Reads by path.
    property var reads: ({})

    function fixture(name) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("../../../fixtures/" + device + "/" + name), false);
        xhr.send();
        return xhr.status === 200 || xhr.status === 0 ? xhr.responseText : "";
    }

    property var _cache: ({})
    function cached(name) {
        var key = device + "/" + name;
        if (_cache[key] === undefined)
            _cache[key] = fixture(name);
        return _cache[key];
    }

    // "cpu0 1 384000 1782000 192000" lines: name, online, current, max, min.
    function cpufreqLines() {
        return cached("cpufreq").split("\n").filter(function(l) { return l.trim() !== ""; })
            .map(function(l) { return l.trim().split(/\s+/); });
    }

    // "thermal_zone0 mtktsbattery 26000" lines; the temperature can be missing.
    function thermalLines() {
        return cached("thermal").split("\n").filter(function(l) { return l.trim() !== ""; })
            .map(function(l) { return l.trim().split(/\s+/); });
    }

    function hasSnapshot() {
        return cached("snap-stat-a") !== "";
    }

    function cmdlineOf(pid) {
        var lines = cached("cmdlines").split("\n");
        for (var i = 0; i < lines.length; i++) {
            var tab = lines[i].indexOf("\t");
            if (tab > 0 && lines[i].substring(0, tab) === String(pid))
                return lines[i].substring(tab + 1);
        }
        return "";
    }

    function readsOf(path) {
        return reads[path] || 0;
    }

    function readFile(path) {
        fileReads++;
        reads[path] = (reads[path] || 0) + 1;
        if (missing[path])
            return "";
        if (overrides[path] !== undefined)
            return overrides[path];
        var snap = hasSnapshot();
        switch (path) {
        case "/proc/stat":
            return snap ? cached("snap-stat-" + phase) : cached(phase === "a" ? "stat1" : "stat2");
        case "/proc/meminfo": return cached("meminfo");
        case "/proc/loadavg": return cached("loadavg");
        case "/proc/uptime": return cached("uptime");
        case "/proc/net/dev": return cached(phase === "a" ? "netdev1" : "netdev2");
        case "/proc/mounts": return cached("mounts");
        case "/sys/class/power_supply/battery/uevent": return cached("battery-uevent");
        }
        var m = /^\/sys\/devices\/system\/cpu\/(cpu\d+)\/cpufreq\/scaling_cur_freq$/.exec(path);
        if (m) {
            var cpus = cpufreqLines();
            for (var i = 0; i < cpus.length; i++) {
                // The mindphone's cpu0 has no "online" file: three fields.
                if (cpus[i][0] === m[1])
                    return cpus[i].length >= 5 ? cpus[i][2] + "\n" : cpus[i][1] + "\n";
            }
            return "";
        }
        m = /^\/sys\/class\/thermal\/(thermal_zone\d+)\/(type|temp)$/.exec(path);
        if (m) {
            var zones = thermalLines();
            for (var j = 0; j < zones.length; j++) {
                if (zones[j][0] === m[1])
                    return m[2] === "type" ? zones[j][1] + "\n" : (zones[j][2] !== undefined ? zones[j][2] + "\n" : "");
            }
            return "";
        }
        m = /^\/proc\/(\d+)\/cmdline$/.exec(path);
        if (m)
            return cmdlineOf(Number(m[1])).replace(/ /g, "\u0000");
        return "";
    }

    function readFiles(paths) {
        return paths.map(readFile);
    }

    function listDirectory(path) {
        if (path === "/sys/devices/system/cpu")
            return cpufreqLines().map(function(c) { return c[0]; }).concat(["cpufreq", "cpuidle", "online"]).sort();
        if (path === "/sys/class/thermal")
            return thermalLines().map(function(z) { return z[0]; }).concat(["cooling_device0"]).sort();
        return [];
    }

    // The TouchPad's / and /media/internal as its df showed them, in bytes
    // (df gives used and available; free is total less used). /var is on /
    // there. The device numbers are made up: only equal or not matters.
    property var storage: ({
        "/": { ok: true, device: "64768", total: 3123494912, free: 154505216, available: 154505216 },
        "/media/internal": { ok: true, device: "64769", total: 26325352448, free: 10158276608, available: 10158276608 },
        "/var": { ok: true, device: "64768", total: 3123494912, free: 154505216, available: 154505216 }
    })

    function storageInfo(path) {
        return storage[path] || { ok: false, device: "", total: 0, free: 0, available: 0 };
    }

    // For the ProcessModel stand-in.
    function readProcessStats() {
        processReads++;
        if (overrides["processes"] !== undefined)
            return overrides["processes"];
        return hasSnapshot() ? cached("snap-pids-" + phase) : cached("pid-stats");
    }

    function sendSignal(pid, startTime, sig) {
        var list = signalsSent.slice();
        list.push({ pid: pid, startTime: startTime, sig: sig });
        signalsSent = list;
        return signalReply;
    }
}
