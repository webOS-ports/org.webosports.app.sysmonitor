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
 * A stand-in for LuneOS.Service's LunaService that answers the calls the
 * app makes from replies captured on the devices (tests/fixtures/<device>:
 * SAM's running apps, memorymanager, batteryd), and records every call.
 *
 * replies maps a luna:// URI to the reply object, to a function of the
 * request giving one, or to { error: "text" } for a refused call (as the
 * bus refuses a method the app has no permission for). A URI with no reply
 * is refused as unknown.
 */
QtObject {
    id: bus

    property string name
    property string device: "touchpad"
    property var replies: ({})
    // [{ uri, args }] for every call and subscribe.
    property var calls: []
    // Live subscriptions: [{ uri, callback, cancelled }].
    property var subscriptions: []

    function fixture(file) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("../../../../fixtures/" + device + "/" + file), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }

    function loadDevice(name) {
        device = name;
        var r = {};
        r["luna://com.webos.service.applicationmanager/running"] = fixture("sam-running.json");
        r["luna://com.webos.service.memorymanager/getMemoryStatus"] = fixture("memstatus.json");
        r["luna://com.webos.service.battery/batteryStatusQuery"] = fixture("battery.json");
        r["luna://com.webos.service.applicationmanager/close"] = function(args) {
            return { returnValue: true, appId: args.id || "", instanceId: args.instanceId || "" };
        };
        replies = r;
    }

    Component.onCompleted: loadDevice(device)

    function callsTo(uri) {
        return calls.filter(function(c) { return c.uri === uri; });
    }

    function _answer(uri, jsonArgs, onReply, onError) {
        var args = JSON.parse(jsonArgs);
        var list = calls.slice();
        list.push({ uri: uri, args: args });
        calls = list;
        var r = replies[uri];
        if (r === undefined) {
            if (onError)
                onError("Unknown method \"" + uri + "\"");
            return;
        }
        if (typeof r === "function")
            r = r(args);
        if (r && r.error !== undefined) {
            if (onError)
                onError(r.error);
            return;
        }
        if (onReply)
            onReply({ payload: JSON.stringify(r) });
    }

    function call(uri, jsonArgs, onReply, onError) {
        _answer(uri, jsonArgs, onReply, onError);
        return { cancel: function() {} };
    }

    function subscribe(uri, jsonArgs, onReply, onError) {
        var sub = { uri: uri, callback: onReply, cancelled: false };
        var list = subscriptions.slice();
        list.push(sub);
        subscriptions = list;
        _answer(uri, jsonArgs, onReply, onError);
        return { cancel: function() { sub.cancelled = true; } };
    }

    // A later reply on every live subscription to uri.
    function push(uri, reply) {
        for (var i = 0; i < subscriptions.length; i++) {
            var s = subscriptions[i];
            if (s.uri === uri && !s.cancelled && s.callback)
                s.callback({ payload: JSON.stringify(reply) });
        }
    }

    function liveSubscriptions(uri) {
        return subscriptions.filter(function(s) { return s.uri === uri && !s.cancelled; }).length;
    }
}
