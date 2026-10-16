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

/*
 * How often to look, and whether to list the kernel's own threads. The
 * cost of a reading is shown, so the price of a short interval is known.
 */
AppPage {
    id: page

    objectName: "preferencesPage"
    title: "Preferences"

    readonly property var prefs: appWindow.prefs
    readonly property var sampler: appWindow.sampler

    Flickable {
        anchors.fill: parent
        contentHeight: content.implicitHeight + Units.gu(2)
        clip: true

        ColumnLayout {
            id: content

            x: Units.gu(1)
            y: Units.gu(1)
            width: parent.width - Units.gu(2)
            spacing: Units.gu(1)

            FormGroup {
                Layout.fillWidth: true
                title: "Updates"

                LabelAndSelector {
                    objectName: "intervalSelector"
                    label: "Update every"
                    model: ["second", "2 seconds", "5 seconds", "10 seconds"]
                    values: [1, 2, 5, 10]
                    value: page.prefs.interval
                    onChosen: (v) => page.prefs.interval = v
                }
                LabelAndValue {
                    objectName: "readingCost"
                    label: "Last reading took"
                    value: page.sampler.readings > 0 ? page.sampler.lastReadingMs + " ms" : "–"
                }
            }

            ExplanationText {
                Layout.fillWidth: true
                text: "Nothing is read while System Monitor is in the background, so it uses no battery there. The processes are only read while their list is shown."
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Processes"

                LabelAndSwitch {
                    objectName: "kernelSwitch"
                    label: "Show kernel threads"
                    checked: page.prefs.showKernelThreads
                    onToggled: page.prefs.showKernelThreads = checked
                }
            }
        }
    }
}
