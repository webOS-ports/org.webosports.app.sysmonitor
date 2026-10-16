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

.pragma library

/*
 * Numbers as the app shows them. Sizes are binary (1 KB = 1024 bytes), as
 * the kernel counts them.
 */

function bytes(n) {
    if (!(n >= 0))
        return "–";
    var units = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    while (n >= 1024 && i < units.length - 1) {
        n /= 1024;
        i++;
    }
    return (i === 0 || n >= 100 ? Math.round(n) : n.toFixed(1)) + " " + units[i];
}

function rate(bytesPerSecond) {
    return bytes(bytesPerSecond) + "/s";
}

// A share, "–" when not known (-1).
function percent(p) {
    if (!(p >= 0))
        return "–";
    return (p < 10 ? p.toFixed(1) : Math.round(p)) + "%";
}

// "3 d 4 h", "4 h 12 min", "12 min", "45 s"
function duration(seconds) {
    if (!(seconds >= 0))
        return "–";
    var s = Math.floor(seconds);
    var d = Math.floor(s / 86400);
    var h = Math.floor((s % 86400) / 3600);
    var m = Math.floor((s % 3600) / 60);
    if (d > 0)
        return d + " d " + h + " h";
    if (h > 0)
        return h + " h " + m + " min";
    if (m > 0)
        return m + " min";
    return s + " s";
}

// MHz in, "1.73 GHz" or "384 MHz" out.
function frequency(mhz) {
    if (!(mhz > 0))
        return "off";
    return mhz >= 1000 ? (mhz / 1000).toFixed(2) + " GHz" : Math.round(mhz) + " MHz";
}

function temperature(c) {
    return isNaN(c) ? "–" : c.toFixed(1) + " °C";
}

function load(v) {
    return v >= 0 ? v.toFixed(2) : "–";
}

// What the kernel's one-letter process states mean.
function processState(s) {
    var names = {
        "R": "Running", "S": "Sleeping", "D": "Waiting for I/O", "Z": "Zombie",
        "T": "Stopped", "t": "Stopped (traced)", "X": "Dead", "I": "Idle", "P": "Parked",
        "W": "Paging", "K": "Wakekill"
    };
    return names[s] || s;
}

// memorymanager's levels, as words.
function memoryLevel(level) {
    var l = String(level || "").toLowerCase();
    if (l === "normal")
        return "Normal";
    if (l === "low")
        return "Low";
    if (l === "critical")
        return "Critical";
    return level ? String(level) : "–";
}
