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

.pragma library

/*
 * What the kernel says in /proc and /sys, turned into numbers, and the
 * numbers turned into rates and percentages, for the overview. No QML and
 * no I/O here: the text comes in, plain objects go out, so all of it is
 * tested against samples taken from real devices (tests/fixtures).
 *
 * The processes are not here: working them out in JavaScript took the
 * TouchPad about 150 ms on every reading, so the plugin's ProcessModel
 * does it.
 *
 * Every parser takes what a read returned, which is "" when the file could
 * not be read, and gives back something empty rather than throwing.
 */

function _lines(text) {
    return typeof text === "string" && text !== "" ? text.split("\n") : [];
}

function _words(line) {
    return line.trim().split(/\s+/);
}

/*
 * /proc/stat: the CPU time lines. Returns
 *   { total: { busy, total }, cores: { <index>: { busy, total } }, coreCount }
 * in clock ticks since boot. "busy" is everything but idle and iowait.
 * guest and guest_nice are left out: the kernel counts them in user and nice
 * already. A core that is switched off (CPU hotplug) has no line at all, so
 * cores is keyed by the core's number rather than an array.
 */
function parseCpuTimes(text) {
    var result = { total: null, cores: {}, coreCount: 0 };
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line.lastIndexOf("cpu", 0) !== 0)
            continue;
        var w = _words(line);
        var total = 0;
        for (var j = 1; j <= 8 && j < w.length; j++)
            total += Number(w[j]) || 0;
        var idle = (Number(w[4]) || 0) + (Number(w[5]) || 0);
        var times = { busy: total - idle, total: total };
        if (w[0] === "cpu") {
            result.total = times;
        } else {
            var index = parseInt(w[0].substring(3), 10);
            if (!isNaN(index)) {
                result.cores[index] = times;
                result.coreCount = Math.max(result.coreCount, index + 1);
            }
        }
    }
    return result;
}

/*
 * The busy share (0..100) between two readings of the same counter, or -1
 * when there is nothing to compare: no earlier reading, no time passed, or
 * the counter went backwards (a core that was switched off and on again
 * starts counting from where the kernel left it, which is not always more).
 */
function busyPercent(prev, cur) {
    if (!prev || !cur)
        return -1;
    var dt = cur.total - prev.total;
    var db = cur.busy - prev.busy;
    if (dt <= 0 || db < 0)
        return -1;
    return Math.min(100, Math.max(0, db * 100 / dt));
}

/*
 * The total and per-core load between two parseCpuTimes() results:
 *   { total: percent, cores: [percent per core 0..n-1], ticks: total ticks
 *     passed on all cores }
 * A core without a figure (off, or no earlier reading) gets -1.
 */
function cpuUsage(prev, cur) {
    var n = cur ? cur.coreCount : 0;
    if (prev)
        n = Math.max(n, prev.coreCount);
    var cores = [];
    for (var i = 0; i < n; i++)
        cores.push(busyPercent(prev ? prev.cores[i] : null, cur ? cur.cores[i] : null));
    var ticks = prev && prev.total && cur && cur.total ? cur.total.total - prev.total.total : 0;
    return {
        total: busyPercent(prev ? prev.total : null, cur ? cur.total : null),
        cores: cores,
        ticks: ticks > 0 ? ticks : 0
    };
}

/*
 * /proc/meminfo as { Key: bytes }. The kernel writes kB (KiB, really);
 * the few unitless lines (HugePages_Total) are kept as they are.
 */
function parseMeminfo(text) {
    var result = {};
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var m = /^([^:]+):\s+(\d+)(\s+kB)?/.exec(lines[i]);
        if (m)
            result[m[1]] = Number(m[2]) * (m[3] ? 1024 : 1);
    }
    return result;
}

/*
 * What the memory panel shows, in bytes. "available" is the kernel's own
 * estimate (MemAvailable, since Linux 3.14); without it free + buffers +
 * page cache stands in. "used" is total less available: what programs hold
 * and could not give back on demand.
 */
function memorySummary(info) {
    var total = info.MemTotal || 0;
    var cache = (info.Cached || 0) + (info.SReclaimable || 0);
    var available = info.MemAvailable !== undefined
            ? info.MemAvailable
            : (info.MemFree || 0) + (info.Buffers || 0) + cache;
    available = Math.min(available, total);
    var swapTotal = info.SwapTotal || 0;
    var swapFree = Math.min(info.SwapFree || 0, swapTotal);
    return {
        total: total,
        available: available,
        used: total - available,
        free: info.MemFree || 0,
        buffers: info.Buffers || 0,
        cached: cache,
        swapTotal: swapTotal,
        swapUsed: swapTotal - swapFree
    };
}

// /proc/loadavg: "0.44 0.53 0.53 1/661 19903"
function parseLoadavg(text) {
    var w = typeof text === "string" ? _words(text) : [];
    if (w.length < 4)
        return null;
    var tasks = w[3].split("/");
    return {
        one: Number(w[0]),
        five: Number(w[1]),
        fifteen: Number(w[2]),
        running: Number(tasks[0]) || 0,
        tasks: Number(tasks[1]) || 0
    };
}

// /proc/uptime: seconds since boot, or -1.
function parseUptime(text) {
    var w = typeof text === "string" ? _words(text) : [];
    var s = Number(w[0]);
    return w.length > 0 && w[0] !== "" && !isNaN(s) ? s : -1;
}

/*
 * /proc/net/dev as [{ name, rx, tx }] in bytes. The interface name and the
 * first number can run together ("eth0:123") on old kernels when the number
 * is long, so the line is split at the colon first.
 */
function parseNetDev(text) {
    var result = [];
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var colon = lines[i].indexOf(":");
        if (colon < 0)
            continue;
        var name = lines[i].substring(0, colon).trim();
        var w = _words(lines[i].substring(colon + 1));
        if (name === "" || w.length < 9)
            continue;
        result.push({ name: name, rx: Number(w[0]) || 0, tx: Number(w[8]) || 0 });
    }
    return result;
}

/*
 * Bytes per second per interface between two parseNetDev() results taken
 * seconds apart, and the sum over every interface but loopback:
 *   { rx, tx, interfaces: [{ name, rx, tx }] }
 * A counter that went backwards (the interface was re-created, or a 32-bit
 * counter wrapped) counts as nothing rather than as a huge jump. Interfaces
 * that moved nothing are left out of the list.
 */
function netRates(prev, cur, seconds) {
    var result = { rx: 0, tx: 0, interfaces: [] };
    if (!prev || !cur || !(seconds > 0))
        return result;
    var before = {};
    for (var i = 0; i < prev.length; i++)
        before[prev[i].name] = prev[i];
    for (var j = 0; j < cur.length; j++) {
        var p = before[cur[j].name];
        if (!p)
            continue;
        var rx = cur[j].rx >= p.rx ? (cur[j].rx - p.rx) / seconds : 0;
        var tx = cur[j].tx >= p.tx ? (cur[j].tx - p.tx) / seconds : 0;
        if (cur[j].name === "lo")
            continue;
        result.rx += rx;
        result.tx += tx;
        if (rx > 0 || tx > 0)
            result.interfaces.push({ name: cur[j].name, rx: rx, tx: tx });
    }
    return result;
}

/*
 * SAM's "running" reply as { <pid>: { id, instanceId, type } }. Native and
 * QML apps have their own process ("processid"); web apps run in a
 * WebAppMgr renderer ("webprocessid") and say "processid": "-1".
 */
function appsByPid(running) {
    var result = {};
    var list = running && running.running ? running.running : [];
    for (var i = 0; i < list.length; i++) {
        var app = list[i];
        var pid = parseInt(app.processid, 10);
        if (!(pid > 0))
            pid = parseInt(app.webprocessid, 10);
        if (pid > 0)
            result[pid] = { id: app.id, instanceId: app.instanceId || "", type: app.appType || "" };
    }
    return result;
}

/*
 * Why a process (ProcessModel.get()) may not be signalled, or "" if it
 * may: the user can end any process but init, the kernel's own threads and
 * this app itself. The plugin checks the same again before it sends
 * anything.
 */
function signalRefusal(p, ownPid) {
    if (!p)
        return "The process has ended.";
    if (p.pid <= 1)
        return "init (process 1) runs the system; ending it would stop the device.";
    if (p.kernelThread)
        return "This is a thread of the kernel itself; it cannot be ended.";
    if (p.pid === ownPid)
        return "This is System Monitor itself; close its card instead.";
    return "";
}

/*
 * /proc/mounts as [{ device, path, type }]. Spaces in paths are written
 * as \040.
 */
function parseMounts(text) {
    var result = [];
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var w = _words(lines[i]);
        if (w.length < 3)
            continue;
        result.push({ device: w[0], path: w[1].replace(/\\040/g, " "), type: w[2] });
    }
    return result;
}

/*
 * The places worth showing the size of: the system, the user's storage,
 * /var and any other storage mounted under /media (a memory card). Not
 * the installer's view of the user's storage (/media/cryptofs), which is
 * the same file system again. Each comes once, labelled; the plugin's
 * device numbers weed out the rest of the doubles.
 */
function storageCandidates(mounts) {
    var result = [
        { path: "/", label: "System" },
        { path: "/media/internal", label: "Internal storage" },
        { path: "/var", label: "/var" }
    ];
    for (var i = 0; i < mounts.length; i++) {
        var m = mounts[i];
        if (m.path.lastIndexOf("/media/", 0) === 0 && m.path !== "/media/internal"
                && m.path !== "/media/cryptofs" && m.path.indexOf("/", 7) < 0
                && m.device.lastIndexOf("/dev/", 0) === 0)
            result.push({ path: m.path, label: m.path.substring(7) });
    }
    return result;
}

/*
 * Drops the storage entries that are the same file system as one before
 * them (same device number from ProcReader.storageInfo()) or that could not
 * be looked at. Each entry: { path, label, info: { device, total, available } }.
 */
function uniqueStorage(entries) {
    var seen = {};
    return entries.filter(function(e) {
        if (!e.info || !(e.info.total > 0))
            return false;
        var dev = String(e.info.device);
        if (seen[dev])
            return false;
        seen[dev] = true;
        return true;
    });
}

/*
 * A thermal zone's temp file in degrees Celsius, or NaN for a zone that
 * reads nothing, an error, or one of the "no sensor" values (-127000 and
 * -274000 on the MediaTek phones). Millidegrees normally; a few old
 * drivers give whole degrees.
 */
function parseTemperature(text) {
    if (typeof text !== "string" || text.trim() === "")
        return NaN;
    var v = Number(text.trim());
    if (isNaN(v))
        return NaN;
    var c = Math.abs(v) >= 1000 ? v / 1000 : v;
    return c > -40 && c < 200 ? c : NaN;
}

// A cpufreq file (kHz) in MHz, or 0.
function parseFrequency(text) {
    var v = typeof text === "string" ? parseInt(text.trim(), 10) : NaN;
    return v > 0 ? v / 1000 : 0;
}

// The numbers of the cpuN directories in a listing of /sys/devices/system/cpu.
function cpuDirs(names) {
    var result = [];
    for (var i = 0; i < names.length; i++) {
        var m = /^cpu(\d+)$/.exec(names[i]);
        if (m)
            result.push(Number(m[1]));
    }
    return result.sort(function(a, b) { return a - b; });
}

// The thermal_zoneN directories in a listing of /sys/class/thermal, in order.
function thermalZones(names) {
    var result = [];
    for (var i = 0; i < names.length; i++) {
        var m = /^thermal_zone(\d+)$/.exec(names[i]);
        if (m)
            result.push(Number(m[1]));
    }
    return result.sort(function(a, b) { return a - b; }).map(function(n) { return "thermal_zone" + n; });
}

/*
 * batteryd's batteryStatusQuery reply, or a power_supply uevent file as
 * the stand-in when the bus will not answer, as
 *   { percent, charging, current_mA, voltage_mV, temperature_C, health }
 * with -1 / "" where not known. Returns null if there is no battery.
 */
function batteryFromStatus(reply) {
    if (!reply || reply.returnValue === false || reply.percent === undefined)
        return null;
    var current = Number(reply.current_mA);
    return {
        percent: Number(reply.percent_ui !== undefined ? reply.percent_ui : reply.percent),
        // batteryd's sign: positive into the battery.
        charging: current > 0,
        current_mA: isNaN(current) ? -1 : current,
        voltage_mV: reply.voltage_mV !== undefined ? Number(reply.voltage_mV) : -1,
        temperature_C: reply.temperature_C !== undefined ? Number(reply.temperature_C) : -1,
        health: reply.health || ""
    };
}

function batteryFromUevent(text) {
    var v = {};
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var eq = lines[i].indexOf("=");
        if (eq > 0)
            v[lines[i].substring(0, eq)] = lines[i].substring(eq + 1);
    }
    if (v.POWER_SUPPLY_CAPACITY === undefined)
        return null;
    var status = v.POWER_SUPPLY_STATUS || "";
    return {
        percent: Number(v.POWER_SUPPLY_CAPACITY),
        charging: status === "Charging",
        current_mA: -1,
        voltage_mV: v.POWER_SUPPLY_VOLTAGE_NOW !== undefined ? Math.round(Number(v.POWER_SUPPLY_VOLTAGE_NOW) / 1000) : -1,
        // Tenths of a degree.
        temperature_C: v.POWER_SUPPLY_TEMP !== undefined ? Number(v.POWER_SUPPLY_TEMP) / 10 : -1,
        health: (v.POWER_SUPPLY_HEALTH || "").toLowerCase()
    };
}

// memorymanager's getMemoryStatus reply: { level, availableMB, totalMB } or null.
function memoryLevel(reply) {
    if (!reply || reply.returnValue === false || !reply.system)
        return null;
    return {
        level: String(reply.system.level || ""),
        availableMB: Number(reply.system.available),
        totalMB: Number(reply.system.total)
    };
}

// A list of at most max numbers with value added at the end.
function pushHistory(history, value, max) {
    var next = history.length >= max ? history.slice(history.length - max + 1) : history.slice();
    next.push(value);
    return next;
}
