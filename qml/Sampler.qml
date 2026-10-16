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

import "js/ProcParse.js" as ProcParse

/*
 * Reads the system every interval while running is true, and keeps what it
 * found in properties the pages bind to. Nothing is read while the card is
 * in the background (running false): the readings are what costs battery.
 *
 * Each reading is one call into the plugin for the files read every time
 * (CPU, memory, load, uptime, network, CPU clocks); temperatures and storage
 * every fifth reading, memorymanager and the battery every tenth. The
 * processes are the Processes page's (ProcessModel), refreshed on updated();
 * while they are shown only the uptime is read here (light).
 */
Item {
    id: sampler

    // ProcReader (the plugin), and a LunaService for the bus.
    property var reader: null
    property var bus: null

    property int interval: 2000
    property bool running: false
    // Only the uptime, while the overview is out of sight (the processes are
    // shown): its figures would be worked out and laid out for nothing,
    // which cost the TouchPad more than the processes themselves.
    property bool light: false
    // How many readings the graphs keep.
    property int historyLength: 60

    // CPU: total and per core in percent (-1 unknown), the clocks in MHz.
    property real cpuTotal: -1
    property var cpuCores: []
    property var cpuFrequencies: []
    property var cpuHistory: []
    // Per core, a history each.
    property var coreHistories: []

    // ProcParse.memorySummary(), and memorymanager's view (memoryLevel()).
    property var memory: null
    property var memoryHistory: []
    property var memoryManager: null

    property var load: null
    property real uptime: -1

    // Bytes per second: { rx, tx, interfaces }, and the two histories.
    property var network: ({ rx: 0, tx: 0, interfaces: [] })
    property var rxHistory: []
    property var txHistory: []

    // [{ path, label, info: { device, total, free, available } }]
    property var storage: []
    // ProcParse.batteryFromStatus() or null.
    property var battery: null
    // [{ name, celsius }], zones that read a plausible temperature.
    property var thermal: []

    // SAM's running apps by pid (ProcParse.appsByPid()).
    property var appsByPid: ({})

    // How long the last reading took, in milliseconds, and how many there
    // have been: for the preferences, and for measuring the app's cost.
    property int lastReadingMs: 0
    property int readings: 0

    signal updated()
    // Reading again after a pause: what was compared with is stale.
    signal resumed()

    // Between readings: the previous raw figures the next one is compared with.
    property var _prevCpu: null
    property var _prevNet: null
    property real _prevNetTime: 0
    // Found once: CPU numbers, thermal zones and their names, where to look
    // for storage.
    property var _cpus: null
    property var _zones: []
    property var _zoneNames: []
    property var _storageCandidates: []
    property var _runningCall: null
    // Readings since the last reset: the slower figures come on every fifth
    // and tenth, and on the first after a pause.
    property int _cycle: 0

    readonly property bool _pollNow: running && reader !== null

    on_PollNowChanged: {
        if (_pollNow) {
            // After a pause the rates start afresh rather than averaging
            // over the time the card was in the background.
            reset();
            resumed();
            poll();
            subscribeRunning();
        } else {
            unsubscribeRunning();
        }
    }

    // Back to the full readings: the rates start afresh.
    onLightChanged: reset()

    Timer {
        id: timer
        interval: Math.max(500, sampler.interval)
        repeat: true
        running: sampler._pollNow
        onTriggered: sampler.poll()
    }

    function reset() {
        _prevCpu = null;
        _prevNet = null;
        _cycle = 0;
    }

    function discover() {
        _cpus = ProcParse.cpuDirs(reader.listDirectory("/sys/devices/system/cpu"));
        _zones = ProcParse.thermalZones(reader.listDirectory("/sys/class/thermal"));
        _zoneNames = reader.readFiles(_zones.map(function(z) { return "/sys/class/thermal/" + z + "/type"; }))
            .map(function(t, i) { return t.trim() || _zones[i]; });
        _storageCandidates = ProcParse.storageCandidates(ProcParse.parseMounts(reader.readFile("/proc/mounts")));
    }

    function poll() {
        var started = Date.now();
        if (light) {
            uptime = ProcParse.parseUptime(reader.readFile("/proc/uptime"));
            readings++;
            lastReadingMs = Date.now() - started;
            updated();
            return;
        }
        if (_cpus === null)
            discover();
        var fixed = ["/proc/stat", "/proc/meminfo", "/proc/loadavg", "/proc/uptime", "/proc/net/dev"];
        var paths = fixed.concat(_cpus.map(function(c) {
            return "/sys/devices/system/cpu/cpu" + c + "/cpufreq/scaling_cur_freq";
        }));
        var texts = reader.readFiles(paths);

        var cpuNow = ProcParse.parseCpuTimes(texts[0]);
        var usage = ProcParse.cpuUsage(_prevCpu, cpuNow);
        _prevCpu = cpuNow;
        cpuTotal = usage.total;
        cpuCores = usage.cores;
        cpuFrequencies = texts.slice(fixed.length).map(ProcParse.parseFrequency);
        if (usage.total >= 0) {
            cpuHistory = ProcParse.pushHistory(cpuHistory, usage.total, historyLength);
            var histories = [];
            for (var i = 0; i < usage.cores.length; i++)
                histories.push(ProcParse.pushHistory(coreHistories[i] || [], Math.max(0, usage.cores[i]), historyLength));
            coreHistories = histories;
        }

        memory = ProcParse.memorySummary(ProcParse.parseMeminfo(texts[1]));
        if (memory.total > 0)
            memoryHistory = ProcParse.pushHistory(memoryHistory, memory.used * 100 / memory.total, historyLength);
        load = ProcParse.parseLoadavg(texts[2]);
        uptime = ProcParse.parseUptime(texts[3]);

        var netNow = ProcParse.parseNetDev(texts[4]);
        if (_prevNet) {
            network = ProcParse.netRates(_prevNet, netNow, (started - _prevNetTime) / 1000);
            rxHistory = ProcParse.pushHistory(rxHistory, network.rx, historyLength);
            txHistory = ProcParse.pushHistory(txHistory, network.tx, historyLength);
        }
        _prevNet = netNow;
        _prevNetTime = started;

        if (_cycle % 5 === 0) {
            readThermal();
            readStorage();
        }
        if (_cycle % 10 === 0) {
            askMemoryManager();
            askBattery();
        }
        readings++;
        _cycle++;
        lastReadingMs = Date.now() - started;
        updated();
    }

    function readThermal() {
        var temps = reader.readFiles(_zones.map(function(z) { return "/sys/class/thermal/" + z + "/temp"; }));
        var result = [];
        for (var i = 0; i < temps.length; i++) {
            var c = ProcParse.parseTemperature(temps[i]);
            if (!isNaN(c))
                result.push({ name: _zoneNames[i], celsius: c });
        }
        thermal = result;
    }

    function readStorage() {
        storage = ProcParse.uniqueStorage(_storageCandidates.map(function(s) {
            var info = reader.storageInfo(s.path);
            return { path: s.path, label: s.label, info: info.ok ? info : null };
        }));
    }

    function askMemoryManager() {
        if (!bus)
            return;
        bus.call("luna://com.webos.service.memorymanager/getMemoryStatus", "{}",
                 function(message) { sampler.memoryManager = ProcParse.memoryLevel(JSON.parse(message.payload)); },
                 function() { sampler.memoryManager = null; });
    }

    /*
     * batteryd's figures; if the bus will not give them (no batteryd, or
     * the call refused), the kernel's power_supply/battery instead.
     */
    function askBattery() {
        if (!bus) {
            batteryFromSysfs();
            return;
        }
        bus.call("luna://com.webos.service.battery/batteryStatusQuery", "{}",
                 function(message) {
                     var b = ProcParse.batteryFromStatus(JSON.parse(message.payload));
                     if (b)
                         sampler.battery = b;
                     else
                         sampler.batteryFromSysfs();
                 },
                 function() { sampler.batteryFromSysfs(); });
    }

    function batteryFromSysfs() {
        battery = ProcParse.batteryFromUevent(reader.readFile("/sys/class/power_supply/battery/uevent"));
    }

    // SAM tells about apps starting and closing as they do.
    function subscribeRunning() {
        if (!bus || _runningCall)
            return;
        _runningCall = bus.subscribe("luna://com.webos.service.applicationmanager/running",
                                     JSON.stringify({ "subscribe": true }),
                                     function(message) {
                                         var reply = JSON.parse(message.payload);
                                         if (reply.running)
                                             sampler.appsByPid = ProcParse.appsByPid(reply);
                                     },
                                     function(error) { console.warn("SAM running: " + error); })
                       || ({});
    }

    function unsubscribeRunning() {
        if (_runningCall && typeof _runningCall.cancel === "function")
            _runningCall.cancel();
        _runningCall = null;
    }

    // Closes an app through SAM, as the card view's close does.
    function closeApp(appId, instanceId, done) {
        var request = instanceId ? { "instanceId": instanceId } : { "id": appId };
        bus.call("luna://com.webos.service.applicationmanager/close", JSON.stringify(request),
                 function(message) {
                     var reply = JSON.parse(message.payload);
                     done(reply.returnValue !== false, reply.errorText || "");
                 },
                 function(error) { done(false, String(error)); });
    }
}
