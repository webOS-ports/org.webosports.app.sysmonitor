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
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1
import LuneOS.Service 1.0
import LuneOS.System 1.0
import LuneOS.Forms 1.0

import SysMonitorApp 1.0

/*
 * System Monitor: what the CPU, memory, network, storage, battery and
 * temperatures are doing, and the processes behind it, with a way to close
 * an app or end a process.
 *
 * The window holds the sampler, which reads the system while the card is
 * in front and not at all while it is in the background, and the pages
 * bind to what it found.
 */
AppWindow {
    id: appWindow

    title: "System Monitor"
    icon: Qt.resolvedUrl("../icon.png")
    initialPage: Qt.resolvedUrl("OverviewPage.qml")

    property alias prefs: preferences
    property alias sampler: sampler
    property alias proc: proc

    // In front: the card is shown and has focus. A card that is minimised or
    // behind another app is not, and is then not worth reading for.
    property bool appActive: Qt.application.state === Qt.ApplicationActive

    // {"measure": true} keeps the readings going in the background too, and
    // logs what each costs: for measuring the app on a device whose screen
    // is locked or in use. Not for everyday use: it costs battery.
    property bool measuring: false

    // Says what went wrong, under the header, until dismissed.
    property string notice: ""

    PreferencesModel {
        id: preferences
    }

    ProcReader {
        id: proc
    }

    LunaService {
        id: service
        name: "org.webosports.app.sysmonitor"
    }

    Sampler {
        id: sampler
        reader: proc
        bus: service
        interval: Math.max(1, preferences.interval) * 1000
        running: appWindow.appActive || appWindow.measuring
        light: !!appWindow.pageStack.currentItem && appWindow.pageStack.currentItem.objectName === "processesPage"
        onUpdated: {
            if (appWindow.measuring && readings % 30 === 0)
                console.info("System Monitor: reading " + readings + " took " + lastReadingMs + " ms");
        }
    }

    onAppActiveChanged: console.info("System Monitor: " + (appActive ? "in front, reading" : "in the background, not reading"))

    function openProcesses() {
        if (!(pageStack.currentItem && pageStack.currentItem.objectName === "processesPage")) {
            pageStack.pop(null);
            pageStack.push(Qt.resolvedUrl("ProcessesPage.qml"));
        }
    }

    function openPreferences() {
        if (!(pageStack.currentItem && pageStack.currentItem.objectName === "preferencesPage"))
            pageStack.push(Qt.resolvedUrl("PreferencesPage.qml"));
    }

    /* The status bar's app menu relaunches the app with "palm-command":
     * "open-app-menu"; LaunchParams turns that into appMenuRequested.
     * {"page": "processes"} or {"page": "preferences"} opens that page;
     * {"measure": true or false}: see measuring. */
    LaunchParams {
        window: appWindow
        onAppMenuRequested: appMenu.popup(0, 0)
        onLaunched: function(params) {
            if (params.measure !== undefined)
                appWindow.measuring = params.measure === true;
            if (params.page === "processes")
                appWindow.openProcesses();
            else if (params.page === "preferences")
                appWindow.openPreferences();
        }
    }

    property alias appMenu: appMenu

    Menu {
        id: appMenu
        // The app menu drops from the top of the window, as in every app.
        parent: appWindow.contentItem
        LuneOSMenu.appMenuStyle: true

        MenuItem {
            text: "Processes"
            onTriggered: appWindow.openProcesses()
        }
        MenuItem {
            text: "Preferences"
            onTriggered: appWindow.openPreferences()
        }
    }

    // Under the header: trouble, until dismissed.
    Item {
        width: appWindow.width
        height: statusNotice.visible ? statusNotice.height + Units.gu(2) : 0

        StatusNotice {
            id: statusNotice
            objectName: "statusNotice"

            x: Units.gu(1)
            y: Units.gu(1)
            width: parent.width - Units.gu(2)
            visible: text !== ""
            text: appWindow.notice
            onDismissed: appWindow.notice = ""
        }
    }
}
