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
