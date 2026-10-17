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

import QtCore
import LuneOS.Components 1.0

/*
 * The app's preferences, kept between runs.
 */
Settings {
    // In the app's own file, as every QML app has (LuneOS.Components' AppFiles).
    location: AppFiles.preferencesFile("org.webosports.app.sysmonitor")
    category: "monitor"

    // Seconds between readings.
    property int interval: 2
    property bool showKernelThreads: false
    // How the processes are sorted: "cpu", "memory", "name" or "pid".
    property string sortKey: "cpu"
}
