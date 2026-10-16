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

/*
 * A stand-in for the plugin's ProcessModel, over the processes the
 * ProcReader stand-in serves (the window's "proc": the device and phase the
 * test chose). It works the figures out as the plugin does, more simply;
 * the plugin itself is tested against the same files in tests/unit.
 */
ListModel {
    id: model

    property string rootPath: ""
    property string searchText: ""
    property string sortKey: "cpu"
    property bool showKernelThreads: false
    property var apps: ({})
    property int ownPid: 0
    property int totalCount: 0
    property int pageSize: 4096
    // How many times refresh() ran.
    property int refreshes: 0

    property var _all: []
    // The rows as shown, for pidAt(): get() here is ProcessModel's, by pid.
    property var _rows: []
    property var _lastTicks: ({})
    property real _lastTotal: 0

    onSearchTextChanged: _update()
    onSortKeyChanged: _update()
    onShowKernelThreadsChanged: _update()
    onAppsChanged: { _name(); _update(); }
    onOwnPidChanged: _update()

    function _cmdline(pid) {
        return appWindow.proc.cmdlineOf(pid);
    }

    function refresh() {
        refreshes++;
        var proc = appWindow.proc;
        var cpuLine = proc.readFile("/proc/stat").split("\n")[0].trim().split(/\s+/);
        var total = 0;
        for (var c = 1; c <= 8 && c < cpuLine.length; c++)
            total += Number(cpuLine[c]);
        var elapsed = _lastTotal > 0 && total > _lastTotal ? total - _lastTotal : 0;
        var lines = proc.readProcessStats().split("\n");
        var list = [];
        var ticks = {};
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i];
            var open = l.indexOf("("), close = l.lastIndexOf(")");
            if (open < 1 || close < open)
                continue;
            var w = l.substring(close + 2).split(" ");
            var p = {
                pid: parseInt(l.substring(0, open), 10),
                comm: l.substring(open + 1, close),
                state: w[0],
                ppid: Number(w[1]),
                kernelThread: Math.floor(Number(w[6]) / 0x200000) % 2 === 1 || parseInt(l, 10) === 2,
                ticks: Number(w[11]) + Number(w[12]),
                threads: Number(w[17]),
                startTime: Number(w[19]),
                rss: Number(w[21]) * pageSize
            };
            var key = p.pid + ":" + p.startTime;
            p.cpu = _lastTicks[key] !== undefined && elapsed > 0 ? (p.ticks - _lastTicks[key]) * 100 / elapsed : -1;
            ticks[key] = p.ticks;
            p.cmdline = p.kernelThread ? "" : _cmdline(p.pid);
            list.push(p);
        }
        _lastTicks = ticks;
        _lastTotal = total;
        _all = list;
        totalCount = list.length;
        _name();
        _update();
    }

    function reset() {
        _lastTicks = {};
        _lastTotal = 0;
    }

    function _name() {
        for (var i = 0; i < _all.length; i++) {
            var p = _all[i];
            var app = apps[String(p.pid)];
            var m = /qml-runner\s+(?:.*\s)?--appid[ =](\S+)/.exec(p.cmdline);
            p.appId = app ? app.id : (m ? m[1] : "");
            p.instanceId = app ? (app.instanceId || "") : "";
            var base = p.cmdline.split(" ")[0];
            base = base.substring(base.lastIndexOf("/") + 1);
            p.name = p.appId !== "" ? p.appId : p.kernelThread ? "[" + p.comm + "]"
                   : base !== "" && base.lastIndexOf(p.comm, 0) === 0 ? base : p.comm;
        }
    }

    function _update() {
        var needle = searchText.trim().toLowerCase();
        var rows = _all.filter(function(p) {
            if (p.kernelThread && !showKernelThreads)
                return false;
            return needle === "" || String(p.pid) === needle || p.name.toLowerCase().indexOf(needle) >= 0
                    || p.cmdline.toLowerCase().indexOf(needle) >= 0 || p.appId.toLowerCase().indexOf(needle) >= 0;
        });
        rows.sort(function(a, b) {
            var d = 0;
            if (sortKey === "memory")
                d = b.rss - a.rss;
            else if (sortKey === "name")
                d = a.name.toLowerCase() < b.name.toLowerCase() ? -1 : a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0;
            else if (sortKey !== "pid")
                d = b.cpu - a.cpu;
            return d || a.pid - b.pid;
        });
        _rows = rows;
        clear();
        for (var i = 0; i < rows.length; i++) {
            var p = rows[i];
            append({
                pid: p.pid, name: p.name,
                detail: p.appId !== "" && p.appId !== p.name ? p.appId : (p.kernelThread ? "kernel" : p.cmdline),
                cpu: p.cpu, rss: p.rss, isApp: p.appId !== "", isSelf: p.pid === ownPid, kernelThread: p.kernelThread
            });
        }
    }

    function get(pid) {
        for (var i = 0; i < _all.length; i++) {
            var p = _all[i];
            if (p.pid === pid)
                return { pid: p.pid, name: p.name, comm: p.comm, cmdline: p.cmdline, appId: p.appId,
                         instanceId: p.instanceId, state: p.state, ppid: p.ppid, kernelThread: p.kernelThread,
                         cpu: p.cpu, rss: p.rss, threads: p.threads, startTime: p.startTime };
        }
        return {};
    }

    function pidAt(row) {
        return row >= 0 && row < _rows.length ? _rows[row].pid : -1;
    }
}
