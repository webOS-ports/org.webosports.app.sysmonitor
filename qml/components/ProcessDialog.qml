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
import QtQuick.Layouts
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1
import LuneOS.Forms 1.0

import "../js/Format.js" as Format
import "../js/ProcParse.js" as ProcParse

/*
 * A process's details, and what can be done to it: close the app (as the
 * card view would), end the process (SIGTERM) or kill it (SIGKILL). Each
 * asks first. init, the kernel's threads and the app itself cannot be
 * ended; the dialog says why instead of offering it.
 *
 * The process is held as it was when the dialog opened; the plugin checks
 * that the pid still belongs to it (its start time) before it signals.
 */
Dialog {
    id: dialog

    objectName: "processDialog"

    // A row of Sampler.processes, copied.
    property var process: null
    property int ownPid: 0
    property real uptime: -1
    property int clockTicks: 100
    // "" for the details; "close", "term" or "kill" while asking.
    property string confirming: ""

    // Asked to act: the page does it.
    signal closeApp(var process)
    signal signalProcess(var process, int sig)

    readonly property string refusal: ProcParse.signalRefusal(process, ownPid)

    modal: true
    focus: true
    // Escape (the back gesture) is handled below, on its release: closing
    // on the press would hand the release to the page stack, which would
    // then go back a page as well.
    closePolicy: Popup.CloseOnPressOutside
    title: process ? process.name : ""
    width: Math.min(Units.gu(48), parent ? parent.width - Units.gu(4) : Units.gu(48))

    function show(p) {
        process = p;
        confirming = "";
        open();
    }

    onClosed: confirming = ""

    contentItem: ColumnLayout {
        spacing: Units.gu(0.5)
        focus: true

        // Back: from the question to the details, from the details away.
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape)
                event.accepted = true;
        }
        Keys.onReleased: function(event) {
            if (event.key !== Qt.Key_Escape)
                return;
            event.accepted = true;
            if (dialog.confirming !== "")
                dialog.confirming = "";
            else
                dialog.close();
        }

        // The details.
        ColumnLayout {
            visible: dialog.confirming === ""
            Layout.fillWidth: true
            spacing: Units.gu(0.25)

            StatRow {
                Layout.fillWidth: true
                label: "Process"
                value: dialog.process ? String(dialog.process.pid) : ""
            }
            StatRow {
                Layout.fillWidth: true
                visible: !!dialog.process && dialog.process.appId !== ""
                label: "App"
                value: dialog.process ? dialog.process.appId : ""
            }
            StatRow {
                Layout.fillWidth: true
                label: "State"
                value: dialog.process ? Format.processState(dialog.process.state) : ""
            }
            StatRow {
                Layout.fillWidth: true
                label: "CPU"
                value: dialog.process ? Format.percent(dialog.process.cpu) : ""
            }
            StatRow {
                Layout.fillWidth: true
                label: "Memory"
                value: dialog.process ? Format.bytes(dialog.process.rss) : ""
            }
            StatRow {
                Layout.fillWidth: true
                label: "Threads"
                value: dialog.process ? String(dialog.process.threads) : ""
            }
            StatRow {
                Layout.fillWidth: true
                label: "Parent"
                value: dialog.process ? String(dialog.process.ppid) : ""
            }
            StatRow {
                Layout.fillWidth: true
                visible: dialog.uptime >= 0
                label: "Running for"
                value: dialog.process ? Format.duration(dialog.uptime - dialog.process.startTime / dialog.clockTicks) : ""
            }
            Label {
                objectName: "cmdline"
                Layout.fillWidth: true
                visible: !!dialog.process && dialog.process.cmdline !== ""
                text: dialog.process ? dialog.process.cmdline : ""
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 4
                elide: Text.ElideRight
                color: Colors.secondaryText
                font.pixelSize: FontUtils.sizeToPixels("small")
            }
            Label {
                objectName: "refusal"
                Layout.fillWidth: true
                visible: dialog.refusal !== ""
                text: dialog.refusal
                wrapMode: Text.WordWrap
                color: Colors.secondaryText
                font.italic: true
            }
        }

        // Asking.
        Label {
            objectName: "question"
            visible: dialog.confirming !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Colors.text
            text: {
                if (!dialog.process)
                    return "";
                var who = "“" + dialog.process.name + "” (process " + dialog.process.pid + ")";
                if (dialog.confirming === "close")
                    return "Close " + who + "? It closes as its card would.";
                if (dialog.confirming === "term")
                    return "End " + who + "? It is asked to stop; what it has not saved is lost.";
                if (dialog.confirming === "kill")
                    return "Kill " + who + "? It is stopped at once, without saving anything.";
                return "";
            }
        }

        // The actions, one under the other: they fit a phone's width that way.
        Button {
            objectName: "closeAppButton"
            Layout.fillWidth: true
            visible: dialog.confirming === "" && !!dialog.process && dialog.process.appId !== "" && dialog.refusal === ""
            text: "Close app"
            onClicked: dialog.confirming = "close"
        }
        Button {
            objectName: "endButton"
            Layout.fillWidth: true
            visible: dialog.confirming === "" && dialog.refusal === ""
            text: "End process"
            onClicked: dialog.confirming = "term"
        }
        Button {
            objectName: "killButton"
            Layout.fillWidth: true
            visible: dialog.confirming === "" && dialog.refusal === ""
            text: "Kill process"
            LuneOSButton.mainColor: LuneOSButton.negativeColor
            onClicked: dialog.confirming = "kill"
        }
        Button {
            objectName: "confirmButton"
            Layout.fillWidth: true
            visible: dialog.confirming !== ""
            text: dialog.confirming === "close" ? "Close" : dialog.confirming === "term" ? "End" : "Kill"
            LuneOSButton.mainColor: LuneOSButton.negativeColor
            onClicked: {
                var p = dialog.process;
                var what = dialog.confirming;
                dialog.close();
                if (what === "close")
                    dialog.closeApp(p);
                else
                    dialog.signalProcess(p, what === "kill" ? 9 : 15);
            }
        }
        Button {
            objectName: "cancelButton"
            Layout.fillWidth: true
            text: dialog.confirming !== "" ? "Cancel" : "Done"
            onClicked: {
                if (dialog.confirming !== "")
                    dialog.confirming = "";
                else
                    dialog.close();
            }
        }
    }
}
