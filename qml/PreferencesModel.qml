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

import QtCore

/*
 * The app's preferences, kept between runs.
 */
Settings {
    // Not a QSettings organisation/application pair: the QML runner is
    // shared by every QML app, so the file is named explicitly.
    location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)
              + "/org.webosports.app.sysmonitor/preferences.ini"
    category: "monitor"

    // Seconds between readings.
    property int interval: 2
    property bool showKernelThreads: false
    // How the processes are sorted: "cpu", "memory", "name" or "pid".
    property string sortKey: "cpu"
}
