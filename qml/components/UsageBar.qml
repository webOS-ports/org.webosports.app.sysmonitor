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
