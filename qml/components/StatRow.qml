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

/*
 * A name on the left and its value on the right, smaller than the
 * settings apps' rows: the overview has many of them.
 */
Item {
    property alias label: nameLabel.text
    property alias value: valueLabel.text
    property alias valueColor: valueLabel.color

    width: parent ? parent.width : implicitWidth
    implicitWidth: nameLabel.implicitWidth + valueLabel.implicitWidth + Units.gu(1)
    height: Math.max(nameLabel.implicitHeight, valueLabel.implicitHeight) + Units.gu(0.5)

    Label {
        id: nameLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.6)
        elide: Text.ElideRight
        color: Colors.secondaryText
        font.pixelSize: FontUtils.sizeToPixels("medium")
    }
    Label {
        id: valueLabel
        anchors.left: nameLabel.right
        anchors.leftMargin: Units.gu(1)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
        color: Colors.text
        font.pixelSize: FontUtils.sizeToPixels("medium")
    }
}
