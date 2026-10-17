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
import LuneOS.Forms 1.0

import "../js/Format.js" as Format

/*
 * One process in the list: its name (the app's id for an app) and what
 * it runs underneath; its CPU share and memory on the right.
 */
ItemDelegate {
    id: row

    // ProcessModel's roles.
    required property int pid
    required property string name
    required property string detail
    required property real cpu
    required property real rss
    required property bool isApp
    required property bool isSelf
    required property bool kernelThread

    readonly property string cpuText: Format.percent(cpu)
    readonly property string memoryText: kernelThread ? "" : Format.bytes(rss)

    width: ListView.view ? ListView.view.width : implicitWidth
    height: Units.gu(6.5)
    padding: 0

    contentItem: Item {
        Column {
            anchors.left: parent.left
            anchors.leftMargin: Units.gu(1)
            anchors.right: numbers.left
            anchors.rightMargin: Units.gu(1)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Units.gu(0.25)

            Label {
                width: parent.width
                text: row.name + (row.isSelf ? " (this app)" : "")
                elide: Text.ElideRight
                font.bold: row.isApp
                color: Colors.text
                font.pixelSize: FontUtils.sizeToPixels("medium")
            }
            Label {
                width: parent.width
                text: row.pid + (row.detail !== "" ? "  ·  " + row.detail : "")
                elide: Text.ElideRight
                color: Colors.secondaryText
                font.pixelSize: FontUtils.sizeToPixels("small")
            }
        }
        Row {
            id: numbers
            anchors.right: parent.right
            anchors.rightMargin: Units.gu(1)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Units.gu(1)

            Label {
                objectName: "cpuText"
                width: Units.gu(7)
                horizontalAlignment: Text.AlignRight
                text: row.cpuText
                color: Colors.text
                font.pixelSize: FontUtils.sizeToPixels("medium")
            }
            Label {
                objectName: "memoryText"
                width: Units.gu(9)
                horizontalAlignment: Text.AlignRight
                text: row.memoryText
                color: Colors.text
                font.pixelSize: FontUtils.sizeToPixels("medium")
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Colors.ruleDark
    }
}
