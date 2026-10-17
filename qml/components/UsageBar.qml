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

import LunaNext.Common 0.1

/*
 * How full something is, as a bar: blue, amber from 75 %, red from 90 %.
 * With lowIsBad (a battery) the other way round: amber under 25 %, red
 * under 10 %. fraction outside 0..1 (not known) shows an empty bar.
 */
Rectangle {
    id: bar

    property real fraction: 0
    property bool lowIsBad: false
    readonly property real shown: fraction >= 0 && fraction <= 1 ? fraction : 0

    width: parent ? parent.width : Units.gu(20)
    height: Units.gu(1)
    radius: height / 2
    color: "#bdbdbd"

    Rectangle {
        objectName: "fill"
        width: Math.max(bar.shown > 0 ? bar.height : 0, bar.width * bar.shown)
        height: parent.height
        radius: parent.radius
        readonly property real badness: bar.lowIsBad ? 1 - bar.shown : bar.shown
        color: badness >= 0.9 ? "#be0003" : badness >= 0.75 ? "#d99a16" : "#2f7fc8"
    }
}
