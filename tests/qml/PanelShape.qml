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
 * The panel's shape - its cutouts (the notch) and rounded corners, from the
 * profile's Settings.displayCutouts and displayCornerRadii - painted black
 * over a window, so a screenshot shows what the panel hides. Nothing on a
 * profile without either. Corner radii go top-left, top-right,
 * bottom-right, bottom-left.
 */
Canvas {
    id: shape

    readonly property var cutouts: Settings.displayCutouts || []
    readonly property var radii: Settings.displayCornerRadii || []
    readonly property bool shaped: cutouts.length > 0 || radii.length > 0
    property bool done: false

    anchors.fill: parent
    z: 1000000
    visible: shaped

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = "black";
        for (var i = 0; i < cutouts.length; i++)
            ctx.fillRect(cutouts[i].x, cutouts[i].y, cutouts[i].width, cutouts[i].height);
        var r = [0, 0, 0, 0];
        for (var j = 0; j < 4 && j < radii.length; j++)
            r[j] = radii[j];
        var w = width, h = height;
        // Each corner: the square it sits in, less the quarter circle.
        var corners = [[0, 0, r[0], r[0], r[0]], [w - r[1], 0, w - r[1], r[1], r[1]],
                       [w - r[2], h - r[2], w - r[2], h - r[2], r[2]], [0, h - r[3], r[3], h - r[3], r[3]]];
        for (var k = 0; k < 4; k++) {
            var c = corners[k];
            if (c[4] <= 0)
                continue;
            ctx.save();
            ctx.beginPath();
            ctx.rect(c[0], c[1], c[4], c[4]);
            ctx.clip();
            ctx.beginPath();
            ctx.rect(c[0], c[1], c[4], c[4]);
            ctx.moveTo(c[2] + c[4], c[3]);
            ctx.arc(c[2], c[3], c[4], 0, 2 * Math.PI, false);
            ctx.closePath();
            ctx.fillRule = Qt.OddEvenFill;
            ctx.fill();
            ctx.restore();
        }
    }
    onPainted: done = true
}
