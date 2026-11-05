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
import QtQuick.Controls
import QtTest

import LunaNext.Common 0.1

/*
 * Every screen of the app on one device's screen per run - the window is
 * the profile's display, with its grid unit (see tests/run-qml-tests.sh,
 * which runs this once per profile in PROFILES). Each screen is checked for
 * what breaks a layout - shown, not empty, inside the window, nothing wider
 * than the window - and saved as build/test-output/ui/<profile>-<screen>.png,
 * with the panel's notch and rounded corners painted over it (PanelShape).
 */
TestCase {
    id: test
    name: "SysMonitorScreens"
    when: windowShown

    readonly property string shotDir: decodeURIComponent(Qt.resolvedUrl("../../build/test-output/ui").toString()
                                                         .replace(/^file:\/\//, ""))
    readonly property string profile: Settings.profileName
    // The captured files of the device closest to the profile: the panels
    // then hold as many cores, zones and file systems as that device has.
    readonly property string device: ({ tp: "touchpad", q25: "q25" })[profile] || "mindphone"
    property var app: null

    Component {
        id: panelShape
        PanelShape {}
    }

    function init_data() {
        return [{ tag: profile + " " + Settings.displayWidth + "x" + Settings.displayHeight }];
    }

    function startApp() {
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        app = component.createObject(null, { appActive: false });
        verify(app !== null, "main.qml did not load");
        compare(app.width, Settings.displayWidth);
        compare(app.height, Settings.displayHeight);
        app.prefs.showKernelThreads = false;
        app.prefs.sortKey = "cpu";
        app.prefs.interval = 2;
        // No readings of its own: one between the test's two would find
        // nothing changed and blank the rates out ("–"), and on a slow
        // host even ten seconds go by.
        app.sampler.interval = 3600 * 1000;
        app.proc.device = device;
        app.proc.phase = "a";
        app.sampler.bus.loadDevice(device);
        waitForRendering(app.contentItem);
        // Two readings, three seconds apart on the device.
        app.appActive = true;
        app.proc.phase = "b";
        app.sampler.poll();
        return app;
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

    function flickableIn(item) {
        if (!item)
            return null;
        if (item.contentHeight !== undefined && item.contentY !== undefined && item.flick !== undefined)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = flickableIn(kids[i]);
            if (found)
                return found;
        }
        return null;
    }

    // Shown, not empty and inside the window, left to right; top to bottom
    // too unless it may be scrolled to.
    function onScreen(item, label, scrolls) {
        verify(item, "no " + label);
        verify(item.visible, label + " hidden");
        verify(item.width > 0 && item.height > 0, label + " has no size: " + item.width + "x" + item.height);
        var p = item.mapToItem(null, 0, 0);
        verify(p.x >= -0.5 && p.x + item.width <= app.width + 0.5,
               label + " off the side: x " + p.x + ", width " + item.width + " of " + app.width);
        if (!scrolls)
            verify(p.y >= -0.5 && p.y + item.height <= app.height + 0.5,
                   label + " runs off the bottom: y " + p.y + ", height " + item.height + " of " + app.height);
    }

    // A page that scrolls only up and down.
    function noSideways(flick, label) {
        verify(flick, "no Flickable in " + label);
        var r = flick.contentItem.childrenRect;
        verify(flick.contentWidth <= flick.width + 0.5 && r.x >= -0.5 && r.x + r.width <= flick.width + 0.5,
               label + " wider than the window: " + flick.contentWidth + ", " + r.x + "+" + r.width + " of " + flick.width);
    }

    function shot(name) {
        wait(300);
        waitForRendering(app.contentItem);
        var shape = panelShape.createObject(app.contentItem);
        if (shape.shaped) {
            shape.requestPaint();
            tryVerify(function() { return shape.done; }, 3000, "panel shape painted");
            waitForRendering(app.contentItem);
        }
        var done = false;
        verify(app.contentItem.grabToImage(function(result) {
            result.saveToFile(shotDir + "/" + profile + "-" + name + ".png");
            done = true;
        }), "grab " + name);
        tryVerify(function() { return done; }, 5000, "saved " + name);
        shape.destroy();
    }

    function openProcesses() {
        mouseClick(findChild(app.contentItem, "processesButton"));
        tryCompare(app.pageStack, "busy", false);
        compare(page().objectName, "processesPage");
        // The page reads them once more a second after it opens; past that,
        // a reading on each side of the three seconds, now that the
        // processes are read too (a later one would find nothing changed).
        wait(1200);
        app.proc.phase = "a";
        app.sampler.poll();
        app.proc.phase = "b";
        app.sampler.poll();
        var l = findChild(page(), "processList");
        tryVerify(function() {
            var r = l.itemAtIndex(0);
            var first = page().processes.get(page().processes.pidAt(0));
            return l.count > 0 && r && r.pid === first.pid && r.cpu === first.cpu;
        }, 3000, "the list shows the busiest first");
    }

    // The details of the busiest process that may be ended (on the Q25
    // the busiest may not: it is a kernel thread or the app itself).
    function openDetails() {
        openProcesses();
        var m = page().processes;
        var d = page().processDialog;
        for (var i = 0; i < m.count; i++) {
            page().openDetails(m.pidAt(i));
            if (d.refusal === "")
                break;
        }
        compare(d.refusal, "");
        tryCompare(d, "opened", true);
        return d;
    }

    // Every button the dialog shows, whole and in the window. The details
    // are taller than the Q25's 720 pixels at its grid unit: the last
    // buttons run off the bottom of the screen.
    // Marked as expected there, so the day they fit this says so.
    function buttonsFit(d, label, tooTallOnQ25) {
        var names = ["closeAppButton", "endButton", "killButton", "confirmButton", "cancelButton"];
        var off = [];
        for (var i = 0; i < names.length; i++) {
            var b = findChild(d.contentItem, names[i]);
            if (!b || !b.visible)
                continue;
            verify(b.width > 0 && b.height > 0, label + ": " + names[i] + " has no size");
            var p = b.mapToItem(null, 0, 0);
            if (p.x < -0.5 || p.y < -0.5 || p.x + b.width > app.width + 0.5 || p.y + b.height > app.height + 0.5)
                off.push(names[i] + " at " + Math.round(p.x) + "," + Math.round(p.y) + " " + b.width + "x" + b.height);
        }
        if (tooTallOnQ25 && profile === "q25")
            expectFailContinue("", "the details are taller than the Q25's screen");
        verify(off.length === 0, label + ": off the window: " + off.join("; "));
    }

    function dialogFits(d, label) {
        var p = d.contentItem.mapToItem(null, 0, 0);
        verify(p.x >= -0.5 && p.x + d.contentItem.width <= app.width + 0.5, label + " off the side");
        var top = d.parent.mapToItem(null, d.x, d.y);
        verify(top.y >= -0.5 && top.y + d.height <= app.height + 0.5,
               label + " taller than the window: y " + top.y + ", height " + d.height);
    }

    function test_overview() {
        startApp();
        compare(page().objectName, "overviewPage");
        var flick = flickableIn(page());
        noSideways(flick, "the overview");
        // Two columns only where there is room for them.
        compare(page().wide, page().width >= Units.gu(80));
        var panels = ["cpuPanel", "memoryPanel", "systemPanel", "networkPanel", "storagePanel"];
        for (var i = 0; i < panels.length; i++) {
            var p = findChild(page(), panels[i]);
            onScreen(p, panels[i], true);
            verify(p.width > Units.gu(25), panels[i] + " too narrow: " + p.width);
        }
        var cpu = findChild(page(), "cpuPanel");
        var net = findChild(page(), "networkPanel");
        if (page().wide)
            verify(net.mapToItem(null, 0, 0).x > cpu.mapToItem(null, 0, 0).x + cpu.width - 1, "network not beside CPU");
        else
            verify(net.mapToItem(flick.contentItem, 0, 0).y > cpu.mapToItem(flick.contentItem, 0, 0).y + cpu.height - 1,
                   "network not under CPU");
        onScreen(findChild(app.contentItem, "processesButton"), "the Processes button");
        verify(findChild(page(), "cpuGraph").height > 0, "no CPU graph");
        verify(findChild(page(), "cpuTotal").text.indexOf("%") > 0, "no CPU share: " + findChild(page(), "cpuTotal").text);
        shot("overview");

        // The bottom of it: storage, battery, temperatures.
        flick.contentY = Math.max(0, flick.contentHeight - flick.height);
        waitForRendering(app.contentItem);
        shot("overview-end");
    }

    function test_app_menu() {
        startApp();
        app.appMenu.popup(0, 0);
        tryCompare(app.appMenu, "opened", true);
        var p = app.appMenu.contentItem.mapToItem(null, 0, 0);
        verify(p.x >= -0.5 && p.x + app.appMenu.width <= app.width + 0.5, "app menu off the side");
        verify(app.appMenu.height > 0 && app.appMenu.height <= app.height, "app menu " + app.appMenu.height);
        shot("app-menu");
        app.appMenu.close();
    }

    function test_processes() {
        startApp();
        openProcesses();
        onScreen(findChild(page(), "searchField"), "the search field");
        var sorts = ["sort-cpu", "sort-memory", "sort-name", "sort-pid"];
        for (var j = 0; j < sorts.length; j++)
            onScreen(findChild(page(), sorts[j]), sorts[j]);
        var l = findChild(page(), "processList");
        onScreen(l, "the list");
        verify(l.height > Units.gu(20), "no room for the list: " + l.height);
        verify(l.contentWidth <= l.width + 0.5, "list wider than the window");
        var row = l.itemAtIndex(0);
        verify(row && row.width > 0 && row.width <= l.width + 0.5, "first row " + (row ? row.width : "missing"));
        verify(row.cpuText.indexOf("%") > 0, "no CPU share: " + row.cpuText);
        shot("processes");

        findChild(page(), "searchField").text = "no such process anywhere";
        tryCompare(l, "count", 0);
        shot("processes-none-found");
    }

    function test_details() {
        startApp();
        var d = openDetails();
        dialogFits(d, "the details");
        shot("details");
        buttonsFit(d, "the details", true);

        mouseClick(findChild(d.contentItem, "endButton"));
        compare(d.confirming, "term");
        waitForPolish(d.contentItem);
        dialogFits(d, "the confirmation");
        shot("details-confirm-end");
        buttonsFit(d, "the confirmation");
    }

    function test_details_of_an_app() {
        startApp();
        openProcesses();
        var pid = -1;
        var m = page().processes;
        for (var i = 0; i < m.count && pid < 0; i++)
            if (m.get(m.pidAt(i)).appId)
                pid = m.pidAt(i);
        verify(pid > 0, "no app among the processes");
        page().openDetails(pid);
        var d = page().processDialog;
        tryCompare(d, "opened", true);
        verify(findChild(d.contentItem, "closeAppButton").visible);
        dialogFits(d, "an app's details");
        shot("details-app");
        buttonsFit(d, "an app's details", true);
    }

    function test_refused() {
        startApp();
        app.proc.signalReply = { ok: false, error: "Operation not permitted" };
        var d = openDetails();
        mouseClick(findChild(d.contentItem, "killButton"));
        waitForPolish(d.contentItem);
        var confirm = findChild(d.contentItem, "confirmButton");
        onScreen(confirm, "Kill (confirm)");
        mouseClick(confirm);
        tryCompare(d, "visible", false);
        verify(app.notice.indexOf("Operation not permitted") >= 0, app.notice);
        onScreen(findChild(app.contentItem, "statusNotice"), "the notice");
        shot("notice");
    }

    function test_preferences() {
        startApp();
        app.openPreferences();
        tryCompare(app.pageStack, "busy", false);
        compare(page().objectName, "preferencesPage");
        noSideways(flickableIn(page()), "the preferences");
        onScreen(findChild(page(), "intervalSelector"), "the interval");
        onScreen(findChild(page(), "kernelSwitch"), "the kernel threads switch", true);
        shot("preferences");
    }
}
