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

import "components"
import "js/Format.js" as Format

/*
 * Everything at a glance: CPU, memory, the system's load and uptime on the
 * left (or first, on a phone); network, storage, battery and temperatures
 * on the right (or after).
 */
AppPage {
    id: page

    objectName: "overviewPage"
    title: "System Monitor"

    readonly property var sampler: appWindow.sampler
    // Two columns where there is room for them: a tablet, landscape.
    readonly property bool wide: width >= Units.gu(80)

    headerAction: Component {
        Button {
            objectName: "processesButton"
            text: "Processes"
            onClicked: appWindow.openProcesses()
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: grid.implicitHeight + Units.gu(2)
        clip: true

        GridLayout {
            id: grid

            x: Units.gu(1)
            y: Units.gu(1)
            width: flick.width - Units.gu(2)
            columns: page.wide ? 2 : 1
            columnSpacing: Units.gu(1)
            rowSpacing: Units.gu(1)

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: Units.gu(1)

                Panel {
                    id: cpuPanel
                    objectName: "cpuPanel"
                    Layout.fillWidth: true
                    title: "CPU"

                    Item {
                        width: parent.width
                        height: cpuBig.implicitHeight
                        Label {
                            id: cpuBig
                            objectName: "cpuTotal"
                            text: Format.percent(page.sampler.cpuTotal)
                            font.pixelSize: FontUtils.sizeToPixels("x-large")
                            font.bold: true
                        }
                        Label {
                            anchors.right: parent.right
                            anchors.baseline: cpuBig.baseline
                            text: page.sampler.cpuCores.length + (page.sampler.cpuCores.length === 1 ? " core" : " cores")
                            color: Colors.secondaryText
                        }
                    }
                    HistoryGraph {
                        objectName: "cpuGraph"
                        capacity: page.sampler.historyLength
                        series: [{ values: page.sampler.cpuHistory, color: "#2f7fc8" }]
                    }
                    Grid {
                        id: coreGrid
                        objectName: "coreGrid"
                        width: parent.width
                        columns: width >= Units.gu(60) ? 4 : 2
                        columnSpacing: Units.gu(1)
                        rowSpacing: Units.gu(0.5)

                        Repeater {
                            model: page.sampler.cpuCores.length
                            delegate: Column {
                                required property int index
                                readonly property real load: page.sampler.cpuCores[index]
                                readonly property real mhz: page.sampler.cpuFrequencies[index] || 0
                                width: (coreGrid.width - coreGrid.columnSpacing * (coreGrid.columns - 1)) / coreGrid.columns
                                spacing: Units.gu(0.25)
                                StatRow {
                                    label: "Core " + index
                                    value: (load >= 0 ? Format.percent(load) : "off")
                                           + (mhz > 0 ? " · " + Format.frequency(mhz) : "")
                                }
                                UsageBar {
                                    height: Units.gu(0.6)
                                    fraction: load >= 0 ? load / 100 : 0
                                }
                            }
                        }
                    }
                }

                Panel {
                    objectName: "memoryPanel"
                    Layout.fillWidth: true
                    title: "Memory"

                    StatRow {
                        objectName: "memoryUsed"
                        label: "Used"
                        value: page.sampler.memory ? Format.bytes(page.sampler.memory.used) + " of " + Format.bytes(page.sampler.memory.total) : "–"
                    }
                    UsageBar {
                        objectName: "memoryBar"
                        fraction: page.sampler.memory && page.sampler.memory.total > 0
                                  ? page.sampler.memory.used / page.sampler.memory.total : 0
                    }
                    HistoryGraph {
                        capacity: page.sampler.historyLength
                        implicitHeight: Units.gu(5)
                        series: [{ values: page.sampler.memoryHistory, color: "#7a3fb0" }]
                    }
                    StatRow {
                        label: "Available"
                        value: page.sampler.memory ? Format.bytes(page.sampler.memory.available) : "–"
                    }
                    StatRow {
                        label: "Cache and buffers"
                        value: page.sampler.memory ? Format.bytes(page.sampler.memory.cached + page.sampler.memory.buffers) : "–"
                    }
                    StatRow {
                        objectName: "swapRow"
                        visible: !!page.sampler.memory && page.sampler.memory.swapTotal > 0
                        label: "Swap"
                        value: page.sampler.memory ? Format.bytes(page.sampler.memory.swapUsed) + " of " + Format.bytes(page.sampler.memory.swapTotal) : ""
                    }
                    UsageBar {
                        visible: !!page.sampler.memory && page.sampler.memory.swapTotal > 0
                        fraction: page.sampler.memory && page.sampler.memory.swapTotal > 0
                                  ? page.sampler.memory.swapUsed / page.sampler.memory.swapTotal : 0
                    }
                    StatRow {
                        objectName: "memoryLevel"
                        label: "Memory manager"
                        value: page.sampler.memoryManager ? Format.memoryLevel(page.sampler.memoryManager.level) : "–"
                        valueColor: page.sampler.memoryManager && page.sampler.memoryManager.level !== "normal"
                                    ? Colors.error : Colors.text
                    }
                }

                Panel {
                    objectName: "systemPanel"
                    Layout.fillWidth: true
                    title: "System"

                    StatRow {
                        objectName: "uptime"
                        label: "Up for"
                        value: Format.duration(page.sampler.uptime)
                    }
                    StatRow {
                        objectName: "loadAverage"
                        label: "Load (1, 5, 15 min)"
                        value: page.sampler.load ? Format.load(page.sampler.load.one) + "  " + Format.load(page.sampler.load.five)
                                                   + "  " + Format.load(page.sampler.load.fifteen) : "–"
                    }
                    StatRow {
                        label: "Tasks (running)"
                        value: page.sampler.load ? page.sampler.load.tasks + " (" + page.sampler.load.running + ")" : "–"
                    }
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: Units.gu(1)

                Panel {
                    objectName: "networkPanel"
                    Layout.fillWidth: true
                    title: "Network"

                    StatRow {
                        objectName: "networkRates"
                        label: "Down / up"
                        value: Format.rate(page.sampler.network.rx) + "  /  " + Format.rate(page.sampler.network.tx)
                    }
                    HistoryGraph {
                        capacity: page.sampler.historyLength
                        maximum: 0
                        series: [{ values: page.sampler.rxHistory, color: "#2a9d3c" },
                                 { values: page.sampler.txHistory, color: "#d4731b" }]
                    }
                    Repeater {
                        model: page.sampler.network.interfaces
                        delegate: StatRow {
                            required property var modelData
                            label: modelData.name
                            value: "↓ " + Format.rate(modelData.rx) + "  ↑ " + Format.rate(modelData.tx)
                        }
                    }
                }

                Panel {
                    objectName: "storagePanel"
                    Layout.fillWidth: true
                    title: "Storage"

                    Repeater {
                        model: page.sampler.storage
                        delegate: Column {
                            required property var modelData
                            width: parent ? parent.width : 0
                            spacing: Units.gu(0.25)
                            StatRow {
                                label: modelData.label
                                value: Format.bytes(modelData.info.available) + " free of " + Format.bytes(modelData.info.total)
                            }
                            UsageBar {
                                fraction: modelData.info.total > 0 ? 1 - modelData.info.available / modelData.info.total : 0
                            }
                        }
                    }
                }

                Panel {
                    objectName: "batteryPanel"
                    Layout.fillWidth: true
                    title: "Battery"
                    visible: !!page.sampler.battery

                    StatRow {
                        objectName: "batteryLevel"
                        label: page.sampler.battery && page.sampler.battery.charging ? "Charging" : "Charge"
                        value: page.sampler.battery ? Math.round(page.sampler.battery.percent) + "%" : "–"
                    }
                    UsageBar {
                        objectName: "batteryBar"
                        lowIsBad: true
                        fraction: page.sampler.battery ? page.sampler.battery.percent / 100 : 0
                    }
                    StatRow {
                        visible: !!page.sampler.battery && page.sampler.battery.current_mA !== -1
                        label: "Current"
                        value: page.sampler.battery ? page.sampler.battery.current_mA + " mA" : ""
                    }
                    StatRow {
                        visible: !!page.sampler.battery && page.sampler.battery.voltage_mV > 0
                        label: "Voltage"
                        value: page.sampler.battery ? (page.sampler.battery.voltage_mV / 1000).toFixed(2) + " V" : ""
                    }
                    StatRow {
                        visible: !!page.sampler.battery && page.sampler.battery.temperature_C > -40
                        label: "Temperature"
                        value: page.sampler.battery ? Format.temperature(page.sampler.battery.temperature_C) : ""
                    }
                    StatRow {
                        visible: !!page.sampler.battery && page.sampler.battery.health !== ""
                        label: "Health"
                        value: page.sampler.battery ? page.sampler.battery.health : ""
                    }
                }

                Panel {
                    objectName: "thermalPanel"
                    Layout.fillWidth: true
                    title: "Temperatures"
                    visible: page.sampler.thermal.length > 0

                    Grid {
                        id: thermalGrid
                        width: parent.width
                        columns: width >= Units.gu(50) ? 2 : 1
                        columnSpacing: Units.gu(2)
                        Repeater {
                            model: page.sampler.thermal
                            delegate: StatRow {
                                required property var modelData
                                width: (thermalGrid.width - thermalGrid.columnSpacing * (thermalGrid.columns - 1)) / thermalGrid.columns
                                label: modelData.name
                                value: Format.temperature(modelData.celsius)
                                valueColor: modelData.celsius >= 70 ? Colors.error : Colors.text
                            }
                        }
                    }
                }
            }
        }
    }
}
