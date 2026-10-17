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
 * The last readings as lines, newest on the right: each series is
 * { values: [numbers], color }. maximum 0 scales to the largest value seen
 * (network rates); otherwise values are taken as a share of maximum
 * (percentages, maximum 100).
 *
 * Drawn on a Canvas only when the values change and the graph is on screen.
 */
Canvas {
    id: graph

    property var series: []
    property real maximum: 100
    property int capacity: 60
    // The largest value on the graph, when it scales itself.
    readonly property real scaleTop: {
        if (maximum > 0)
            return maximum;
        var m = 0;
        for (var i = 0; i < series.length; i++) {
            var v = series[i].values || [];
            for (var j = 0; j < v.length; j++)
                m = Math.max(m, v[j]);
        }
        return m > 0 ? m : 1;
    }

    implicitHeight: Units.gu(8)
    width: parent ? parent.width : Units.gu(20)
    height: implicitHeight
    renderTarget: Canvas.Image
    renderStrategy: Canvas.Immediate

    onSeriesChanged: if (visible) requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = "#f4f4f4";
        ctx.fillRect(0, 0, width, height);
        ctx.strokeStyle = "#d6d6d6";
        ctx.lineWidth = 1;
        ctx.beginPath();
        for (var g = 1; g < 4; g++) {
            var gy = Math.round(height * g / 4) + 0.5;
            ctx.moveTo(0, gy);
            ctx.lineTo(width, gy);
        }
        ctx.stroke();

        var step = width / Math.max(1, capacity - 1);
        for (var s = 0; s < series.length; s++) {
            var values = series[s].values || [];
            if (values.length < 2)
                continue;
            var x0 = width - (values.length - 1) * step;
            ctx.beginPath();
            for (var i = 0; i < values.length; i++) {
                var x = x0 + i * step;
                var y = height - Math.min(1, Math.max(0, values[i] / scaleTop)) * (height - 2) - 1;
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.strokeStyle = series[s].color;
            ctx.lineWidth = Math.max(1.5, Units.gu(0.25));
            ctx.stroke();
            if (s === 0) {
                ctx.lineTo(width, height);
                ctx.lineTo(x0, height);
                ctx.closePath();
                ctx.globalAlpha = 0.2;
                ctx.fillStyle = series[s].color;
                ctx.fill();
                ctx.globalAlpha = 1;
            }
        }
    }
}
