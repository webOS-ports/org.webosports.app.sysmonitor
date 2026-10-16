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
import QtQuick.Controls
import QtTest

import LunaNext.Common 0.1

/*
 * The app itself - qml/main.qml with its pages - on the build host, with
 * luneos-components' desktop stand-ins for the window, and tests/qml/imports
 * for the app's plugin (ProcReader over the devices' captured files) and
 * the bus (SAM, memorymanager and batteryd as the devices answered).
 * Run by tests/run-qml-tests.sh.
 */
TestCase {
    id: test
    name: "SysMonitorUi"
    when: windowShown

    property var app: null

    function createApp(device, width, height) {
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        // In the background to begin with, so each test decides when the
        // readings start and what they read.
        app = component.createObject(null, { appActive: false });
        verify(app !== null, "main.qml did not load");
        if (width) {
            app.width = width;
            app.height = height;
        }
        // The preferences outlive an app: back to how they start.
        app.prefs.showKernelThreads = false;
        app.prefs.sortKey = "cpu";
        app.prefs.interval = 2;
        app.proc.device = device || "touchpad";
        app.proc.phase = "a";
        app.sampler.bus.loadDevice(device || "touchpad");
        waitForRendering(app.contentItem);
        return app;
    }

    // Two readings, three seconds apart on the device: rates and shares.
    function startReading() {
        app.appActive = true;
        app.proc.phase = "b";
        app.sampler.poll();
    }

    function cleanup() {
        if (app) {
            app.destroy();
            app = null;
        }
    }

    function page() {
        return app.pageStack.currentItem;
    }

    function findChild(item, objectName) {
        if (!item)
            return null;
        if (item.objectName === objectName)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findChild(kids[i], objectName);
            if (found)
                return found;
        }
        if (item.contentItem && item.contentItem !== item)
            return findChild(item.contentItem, objectName);
        return null;
    }

    function textOf(objectName) {
        var item = findChild(page(), objectName);
        verify(item, "no " + objectName);
        return item.value !== undefined ? item.value : item.text;
    }

    function openProcesses() {
        app.openProcesses();
        tryCompare(app.pageStack, "busy", false);
        compare(page().objectName, "processesPage");
        return page();
    }

    function processList() {
        return findChild(page(), "processList");
    }

    function processes() {
        return page().processes;
    }

    function rowNames() {
        var m = processes();
        var names = [];
        for (var i = 0; i < m.count; i++)
            names.push(m.get(m.pidAt(i)).name);
        return names;
    }

    function row(i) {
        return processes().get(processes().pidAt(i));
    }

    function dialog() {
        return page().processDialog;
    }

    // A button of the dialog, once the dialog has laid itself out.
    function dialogButton(objectName) {
        var b = findChild(dialog().contentItem, objectName);
        verify(b && b.visible, objectName + " not shown");
        waitForPolish(dialog().contentItem);
        return b;
    }

    function test_overview_touchpad() {
        createApp("touchpad");
        startReading();
        compare(page().objectName, "overviewPage");
        compare(textOf("cpuTotal"), "3.3%");
        compare(findChild(page(), "coreGrid").children.length - 1, 2);
        compare(textOf("memoryUsed"), "427 MB of 824 MB");
        compare(textOf("memoryLevel"), "Normal");
        compare(textOf("uptime"), "5 h 43 min");
        compare(textOf("loadAverage"), "0.44  0.53  0.53");
        // /var is the same file system as / on the TouchPad: shown once.
        compare(app.sampler.storage.map(function(s) { return s.path; }), ["/", "/media/internal"]);
        compare(textOf("batteryLevel"), "100%");
        // batteryd's figures, the kernel's word for the state.
        compare(textOf("batteryStatus"), "Full");
        verify(findChild(page(), "batteryPanel").visible);
        // Its only thermal zone reads nothing: no temperatures panel.
        verify(!findChild(page(), "thermalPanel").visible);
        compare(app.sampler.cpuHistory.length, 1);
        // A small graph per core, with that core's readings.
        compare(app.sampler.coreHistories.length, 2);
        var graph = findChild(findChild(page(), "coreGrid").children[0], "coreGraph");
        verify(graph && graph.height > 0);
        compare(graph.series[0].values, app.sampler.coreHistories[0]);
    }

    function test_overview_mindphone() {
        createApp("mindphone");
        startReading();
        compare(textOf("cpuTotal"), "2.0%");
        compare(app.sampler.cpuCores.length, 4);
        compare(app.sampler.cpuFrequencies, [1274, 1274, 1274, 1274]);
        verify(findChild(page(), "thermalPanel").visible);
        // The zones without a sensor (-127000) are left out.
        verify(app.sampler.thermal.length > 0 && app.sampler.thermal.length < 28, app.sampler.thermal.length);
        verify(app.sampler.thermal.every(function(t) { return t.celsius > 0 && t.celsius < 100; }));
        compare(app.sampler.network.interfaces.map(function(i) { return i.name; }), ["wlan0"]);
    }

    // A core whose load is not known yet is not "off": only one with no
    // figures at all is.
    function test_core_off_only_without_figures() {
        createApp("touchpad");
        app.appActive = true;
        var core = findChild(page(), "coreGrid").children[0];
        verify(String(findChild(core, "coreValue").value).indexOf("off") < 0, findChild(core, "coreValue").value);
        app.proc.overrides["/sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq"] = "";
        app.proc.overrides["/proc/stat"] = "cpu  1 0 1 10 0 0 0 0 0 0\ncpu0 1 0 1 10 0 0 0 0\n";
        app.sampler.poll();
        app.proc.overrides["/proc/stat"] = "cpu  2 0 2 20 0 0 0 0 0 0\ncpu0 2 0 2 20 0 0 0 0\n";
        app.sampler.poll();
        compare(app.sampler.cpuCores[1], -1);
        tryVerify(function() {
            var c1 = findChild(page(), "coreGrid").children[1];
            return c1 && findChild(c1, "coreValue") && findChild(c1, "coreValue").value === "off";
        });
    }

    function test_overview_q25_eight_cores() {
        createApp("q25", 720, 720);
        startReading();
        compare(app.sampler.cpuCores.length, 8);
        compare(findChild(page(), "coreGrid").children.length - 1, 8);
        compare(app.sampler.cpuFrequencies[6], 725);
    }

    function test_nothing_read_in_the_background() {
        createApp("touchpad");
        compare(app.proc.fileReads, 0);
        compare(app.sampler.bus.calls.length, 0);
        app.prefs.interval = 1;
        app.appActive = true;
        verify(app.proc.fileReads > 0);
        compare(app.sampler.bus.liveSubscriptions("luna://com.webos.service.applicationmanager/running"), 1);
        tryVerify(function() { return app.sampler.readings >= 2; }, 3000);
        app.appActive = false;
        var reads = app.proc.fileReads;
        var calls = app.sampler.bus.calls.length;
        wait(2500);
        compare(app.proc.fileReads, reads);
        compare(app.sampler.bus.calls.length, calls);
        compare(app.sampler.bus.liveSubscriptions("luna://com.webos.service.applicationmanager/running"), 0);
        // In front again: read at once, and the rates start afresh.
        app.appActive = true;
        verify(app.proc.fileReads > reads);
        compare(app.sampler.cpuTotal, -1);
    }

    function test_processes_only_read_on_their_page() {
        createApp("touchpad");
        startReading();
        compare(app.proc.processReads, 0);
        openProcesses();
        verify(app.proc.processReads > 0);
        verify(processList().count > 0);
        // Each reading refreshes them, and reads nothing for the overview
        // underneath but the uptime (the dialog's "Running for").
        var reads = app.proc.processReads;
        var meminfo = app.proc.readsOf("/proc/meminfo");
        var uptime = app.proc.readsOf("/proc/uptime");
        app.sampler.poll();
        compare(app.proc.processReads, reads + 1);
        compare(app.proc.readsOf("/proc/meminfo"), meminfo);
        compare(app.proc.readsOf("/proc/uptime"), uptime + 1);
        keyClick(Qt.Key_Escape);
        tryCompare(app.pageStack, "busy", false);
        compare(page().objectName, "overviewPage");
        reads = app.proc.processReads;
        app.sampler.poll();
        wait(1200);
        compare(app.proc.processReads, reads);
        // The overview is read again, its rates starting afresh.
        verify(app.proc.readsOf("/proc/meminfo") > meminfo);
        compare(app.sampler.cpuTotal, -1);
    }

    function test_process_list() {
        createApp("touchpad");
        startReading();
        openProcesses();
        // A reading on each side of the three seconds, now that the
        // processes are read too.
        app.proc.phase = "a";
        app.sampler.poll();
        app.proc.phase = "b";
        app.sampler.poll();
        // No kernel threads by default: 325 processes, of which 173 are.
        var shown = processList().count;
        verify(shown > 100 && shown < 200, shown);
        verify(rowNames().indexOf("[kthreadd]") < 0);
        // Busiest first: dbus-daemon took 4 of 604 ticks.
        compare(row(0).pid, 756);
        tryVerify(function() { var r = processList().itemAtIndex(0); return r && r.pid === 756; });
        compare(processList().itemAtIndex(0).cpuText, "0.7%");
        // Apps go by their id: the phone (qml-runner) and a web app's renderer.
        verify(rowNames().indexOf("org.webosports.app.phone") >= 0);
        verify(rowNames().indexOf("com.palm.app.email") >= 0);
        app.prefs.showKernelThreads = true;
        verify(rowNames().indexOf("[kthreadd]") >= 0);
        compare(processList().count, 325);
    }

    function test_sort_and_search() {
        createApp("touchpad");
        startReading();
        openProcesses();
        mouseClick(findChild(page(), "sort-memory"));
        compare(app.prefs.sortKey, "memory");
        compare(row(0).pid, 2540);
        compare(row(0).name, "surface-manager");
        processList().positionViewAtBeginning();
        tryVerify(function() { return processList().itemAtIndex(0) && processList().itemAtIndex(0).pid === 2540; });
        compare(processList().itemAtIndex(0).memoryText, "98.6 MB");
        mouseClick(findChild(page(), "sort-pid"));
        compare(row(0).pid, 1);
        mouseClick(findChild(page(), "sort-name"));
        var names = rowNames();
        verify(names[0].toLowerCase() <= names[1].toLowerCase());
        var search = findChild(page(), "searchField");
        search.text = "dbus";
        verify(processList().count >= 1);
        verify(rowNames().every(function(n) { return n.indexOf("dbus") >= 0; }), rowNames().join());
        search.text = "no such process anywhere";
        compare(processList().count, 0);
        search.text = "";
        mouseClick(findChild(page(), "sort-cpu"));
    }

    function test_details_and_end_a_process() {
        createApp("touchpad");
        startReading();
        openProcesses();
        page().openDetails(756);
        tryCompare(dialog(), "opened", true);
        compare(dialog().title, "dbus-daemon");
        verify(findChild(dialog().contentItem, "endButton").visible);
        verify(!findChild(dialog().contentItem, "closeAppButton").visible);
        mouseClick(dialogButton("endButton"));
        compare(dialog().confirming, "term");
        // Cancel asks nothing of the process.
        mouseClick(dialogButton("cancelButton"));
        compare(dialog().confirming, "");
        compare(app.proc.signalsSent.length, 0);
        mouseClick(dialogButton("endButton"));
        mouseClick(dialogButton("confirmButton"));
        tryCompare(dialog(), "visible", false);
        compare(app.proc.signalsSent.length, 1);
        compare(app.proc.signalsSent[0].pid, 756);
        compare(app.proc.signalsSent[0].sig, 15);
        // With the start time it had, so a reused pid is not hit.
        var p = processes().get(756);
        compare(app.proc.signalsSent[0].startTime, p.startTime);
        compare(app.notice, "");
    }

    function test_kill_and_refused() {
        createApp("touchpad");
        startReading();
        openProcesses();
        app.proc.signalReply = { ok: false, error: "Operation not permitted" };
        page().openDetails(756);
        tryCompare(dialog(), "opened", true);
        mouseClick(dialogButton("killButton"));
        mouseClick(dialogButton("confirmButton"));
        compare(app.proc.signalsSent[0].sig, 9);
        verify(app.notice.indexOf("Operation not permitted") >= 0, app.notice);
        verify(findChild(app.contentItem, "statusNotice").visible);
    }

    function test_init_kernel_threads_and_itself_are_not_offered() {
        createApp("touchpad");
        startReading();
        openProcesses();
        app.prefs.showKernelThreads = true;
        var refused = [1, 2, 3];
        // The app itself: the stand-in's own pid is made one of the device's.
        app.proc.ownPid = 756;
        refused.push(756);
        for (var i = 0; i < refused.length; i++) {
            page().openDetails(refused[i]);
            tryCompare(dialog(), "opened", true);
            verify(findChild(dialog().contentItem, "refusal").visible, "pid " + refused[i]);
            verify(!findChild(dialog().contentItem, "endButton").visible, "pid " + refused[i]);
            verify(!findChild(dialog().contentItem, "killButton").visible, "pid " + refused[i]);
            dialog().close();
            tryCompare(dialog(), "visible", false);
        }
        compare(app.proc.signalsSent.length, 0);
    }

    function test_close_an_app() {
        createApp("touchpad");
        startReading();
        openProcesses();
        page().openDetails(3335);
        tryCompare(dialog(), "opened", true);
        compare(dialog().process.appId, "org.webosports.app.phone");
        mouseClick(dialogButton("closeAppButton"));
        mouseClick(dialogButton("confirmButton"));
        var calls = app.sampler.bus.callsTo("luna://com.webos.service.applicationmanager/close");
        compare(calls.length, 1);
        verify(calls[0].args.instanceId.length > 0);
        compare(app.proc.signalsSent.length, 0);
    }

    function test_close_refused_says_so() {
        createApp("touchpad");
        app.sampler.bus.replies["luna://com.webos.service.applicationmanager/close"] = { error: "Denied method call" };
        startReading();
        openProcesses();
        page().openDetails(3335);
        tryCompare(dialog(), "opened", true);
        mouseClick(dialogButton("closeAppButton"));
        mouseClick(dialogButton("confirmButton"));
        verify(app.notice.indexOf("Denied") >= 0, app.notice);
    }

    function test_escape_closes_the_dialog_not_the_page() {
        createApp("touchpad");
        startReading();
        openProcesses();
        page().openDetails(756);
        tryCompare(dialog(), "opened", true);
        keyClick(Qt.Key_Escape);
        tryCompare(dialog(), "visible", false);
        compare(page().objectName, "processesPage");
        // The next Escape is the back gesture: back to the overview.
        keyClick(Qt.Key_Escape);
        tryCompare(app.pageStack, "busy", false);
        compare(page().objectName, "overviewPage");
        // And on the first page it does nothing.
        keyClick(Qt.Key_Escape);
        compare(page().objectName, "overviewPage");
    }

    function test_new_app_follows_sam() {
        createApp("touchpad");
        startReading();
        openProcesses();
        verify(rowNames().indexOf("org.example.later") < 0);
        var running = JSON.parse(JSON.stringify(app.sampler.bus.replies["luna://com.webos.service.applicationmanager/running"]));
        running.running.push({ id: "org.example.later", processid: "756", webprocessid: "", instanceId: "x1", appType: "native_qml" });
        app.sampler.bus.push("luna://com.webos.service.applicationmanager/running", running);
        app.sampler.poll();
        verify(rowNames().indexOf("org.example.later") >= 0);
    }

    function test_battery_from_the_kernel_when_batteryd_refuses() {
        createApp("mindphone");
        app.sampler.bus.replies["luna://com.webos.service.battery/batteryStatusQuery"] = { error: "Denied method call" };
        app.sampler.bus.replies["luna://com.webos.service.memorymanager/getMemoryStatus"] = { error: "Denied method call" };
        startReading();
        // The power_supply uevent: charging, 26.4 °C.
        compare(app.sampler.battery.status, "Charging");
        compare(app.sampler.battery.temperature_C, 26.4);
        compare(textOf("memoryLevel"), "–");
    }

    function test_preferences() {
        createApp("touchpad");
        startReading();
        app.openPreferences();
        tryCompare(app.pageStack, "busy", false);
        compare(page().objectName, "preferencesPage");
        verify(textOf("readingCost").indexOf("ms") > 0);
        var selector = findChild(page(), "intervalSelector");
        selector.chosen(5);
        compare(app.sampler.interval, 5000);
        selector.chosen(1);
        compare(app.sampler.interval, 1000);
        keyClick(Qt.Key_Escape);
        tryCompare(app.pageStack, "busy", false);
        compare(page().objectName, "overviewPage");
    }

    function test_launch_params_open_pages() {
        createApp("touchpad");
        app.launchParams = JSON.stringify({ page: "processes" });
        tryCompare(app.pageStack, "busy", false);
        compare(page().objectName, "processesPage");
    }

    // {"measure": true} keeps reading in the background, for tools/measure.sh.
    function test_measure_launch_parameter() {
        createApp("touchpad");
        verify(!app.sampler.running);
        app.launchParams = JSON.stringify({ measure: true });
        verify(app.sampler.running);
        verify(app.proc.fileReads > 0);
        app.launchParams = JSON.stringify({ measure: false });
        verify(!app.sampler.running);
    }

    function test_layout_data() {
        return [
            { tag: "phone 480x800", w: 480, h: 800, columns: 1 },
            { tag: "Q25 720x720", w: 720, h: 720, columns: 1 },
            { tag: "tablet 1024x768", w: 1024, h: 768, columns: 2 },
            { tag: "tablet portrait 768x1024", w: 768, h: 1024, columns: 1 }
        ];
    }

    function test_layout(data) {
        createApp("q25", data.w, data.h);
        startReading();
        compare(page().wide, data.columns === 2);
        var panels = ["cpuPanel", "memoryPanel", "systemPanel", "networkPanel", "storagePanel"];
        for (var i = 0; i < panels.length; i++) {
            var p = findChild(page(), panels[i]);
            var pos = p.mapToItem(null, 0, 0);
            verify(pos.x >= 0 && pos.x + p.width <= app.width + 0.5, panels[i] + " off the side");
            verify(p.width > Units.gu(25), panels[i] + " too narrow: " + p.width);
        }
        var cpu = findChild(page(), "cpuPanel");
        var net = findChild(page(), "networkPanel");
        if (data.columns === 2)
            verify(net.mapToItem(null, 0, 0).x > cpu.mapToItem(null, 0, 0).x + cpu.width - 1, "network not beside CPU");
        else
            verify(net.mapToItem(null, 0, 0).y > cpu.mapToItem(null, 0, 0).y + cpu.height - 1, "network not under CPU");

        openProcesses();
        var sorts = ["sort-cpu", "sort-memory", "sort-name", "sort-pid"];
        for (var j = 0; j < sorts.length; j++) {
            var b = findChild(page(), sorts[j]);
            var bp = b.mapToItem(null, 0, 0);
            verify(bp.x >= 0 && bp.x + b.width <= app.width + 0.5, sorts[j] + " off the side");
        }
        var l = processList();
        verify(l.height > Units.gu(20), "no room for the list: " + l.height);
        var row = l.itemAtIndex(0);
        verify(row && row.width <= l.width + 0.5, "row wider than the list");
        page().openDetails(processes().pidAt(0));
        tryCompare(dialog(), "opened", true);
        var d = dialog();
        var dp = d.contentItem.mapToItem(null, 0, 0);
        verify(dp.x >= 0 && dp.x + d.contentItem.width <= app.width + 0.5, "dialog off the side");
        verify(d.y >= 0 && d.y + d.height <= app.height + 0.5, "dialog taller than the window: " + d.height);
    }
}
