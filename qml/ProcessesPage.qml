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
import QtQuick.Layouts
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1
import LuneOS.Forms 1.0

import SysMonitorApp 1.0

import "components"

/*
 * Every process, with its share of the CPU and its memory, sorted and
 * searchable. Apps show by their id (SAM's running apps, or the id a
 * qml-runner was started with). Tap one for its details, to close the app
 * or to end the process.
 *
 * The processes are only read while this page is shown: on each of the
 * sampler's readings, and once more a second after the page opens so the
 * CPU shares do not wait a whole interval.
 */
AppPage {
    id: page

    objectName: "processesPage"
    title: "Processes"
    explanation: processes.count + (processes.count === 1 ? " process" : " processes")
                 + " · tap one for details, to close or end it"

    readonly property var sampler: appWindow.sampler
    readonly property var prefs: appWindow.prefs
    readonly property bool wide: width >= Units.gu(60)
    property alias processes: processes
    property alias processDialog: processDialog

    ProcessModel {
        id: processes
        ownPid: appWindow.proc.ownPid
        searchText: searchField.text
        sortKey: page.prefs.sortKey
        showKernelThreads: page.prefs.showKernelThreads
        apps: page.sampler.appsByPid
    }

    Component.onCompleted: {
        processes.refresh();
        quickRefresh.start();
    }

    Connections {
        target: page.sampler
        function onUpdated() { processes.refresh(); }
        function onResumed() { processes.reset(); }
    }

    Timer {
        id: quickRefresh
        interval: 1000
        onTriggered: {
            if (page.sampler.running && page.sampler.interval > 1500)
                processes.refresh();
        }
    }

    function openDetails(pid) {
        var p = processes.get(pid);
        if (p.pid !== undefined)
            processDialog.show(p);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        GridLayout {
            Layout.fillWidth: true
            Layout.margins: Units.gu(1)
            columns: page.wide ? 2 : 1
            columnSpacing: Units.gu(1)
            rowSpacing: Units.gu(0.5)

            TextField {
                id: searchField
                objectName: "searchField"
                Layout.fillWidth: true
                placeholderText: "Search by name, command or number"
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            }

            RowLayout {
                Layout.fillWidth: !page.wide
                spacing: Units.gu(0.5)

                Repeater {
                    model: [{ key: "cpu", text: "CPU" }, { key: "memory", text: "Memory" },
                            { key: "name", text: "Name" }, { key: "pid", text: "PID" }]
                    delegate: Button {
                        required property var modelData
                        objectName: "sort-" + modelData.key
                        Layout.fillWidth: !page.wide
                        text: modelData.text
                        checkable: true
                        checked: page.prefs.sortKey === modelData.key
                        LuneOSButton.mainColor: checked ? LuneOSButton.affirmativeColor : LuneOSButton.secondaryColor
                        onClicked: {
                            page.prefs.sortKey = modelData.key;
                            list.positionViewAtBeginning();
                        }
                    }
                }
            }
        }

        ListView {
            id: list
            objectName: "processList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: processes
            reuseItems: true

            delegate: ProcessRow {
                onClicked: page.openDetails(pid)
            }

            ScrollIndicator.vertical: ScrollIndicator {}

            Label {
                anchors.centerIn: parent
                visible: processes.count === 0
                text: processes.totalCount === 0 ? "Reading the processes…" : "No process matches."
                color: Colors.secondaryText
            }
        }
    }

    ProcessDialog {
        id: processDialog
        ownPid: appWindow.proc.ownPid
        clockTicks: appWindow.proc.clockTicks
        uptime: page.sampler.uptime

        onCloseApp: function(p) {
            page.sampler.closeApp(p.appId, p.instanceId, function(ok, error) {
                appWindow.notice = ok ? "" : "Could not close " + p.appId + ": " + error;
                recheck.restart();
            });
        }
        onSignalProcess: function(p, sig) {
            var result = appWindow.proc.sendSignal(p.pid, p.startTime, sig);
            appWindow.notice = result.ok ? "" : "Could not end " + p.name + ": " + result.error;
            // Look again shortly: ending takes the process a moment.
            recheck.restart();
        }
    }

    Timer {
        id: recheck
        interval: 700
        onTriggered: processes.refresh()
    }
}
