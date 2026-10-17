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
