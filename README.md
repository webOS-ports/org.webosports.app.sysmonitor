System Monitor
==============

Summary
-------
CPU, memory, network, storage, battery and temperatures at a glance, and the processes, with a way to close an app or end a process.

Description
-----------
What the device is doing, and the processes behind it.

A QML app for LuneOS in the LuneOS style (LuneOS.Forms), with a small C++
plugin (`SysMonitorApp`) for what QML cannot do or cannot do cheaply.

Features
--------

- **Overview**, in two columns on a tablet and one on a phone:
  - **CPU:** the total load with a graph of the last readings, and each
    core's load and clock (a core that is switched off shows "off").
  - **Memory:** used of total (total less the kernel's MemAvailable), a
    graph, what is available, cache and buffers, swap, and memorymanager's
    level (Normal, Low, Critical).
  - **System:** uptime, the load average (1, 5, 15 minutes), tasks and how
    many are running.
  - **Network:** download and upload rates with a graph, and each interface
    that moved anything.
  - **Storage:** free and total of the system, the internal storage, /var
    when it is a file system of its own, and memory cards under /media.
  - **Battery:** charge, charging or not, current, voltage, temperature and
    health, from batteryd (or the kernel's power_supply when the bus does
    not answer).
  - **Temperatures:** every thermal zone that reads a temperature; zones
    without a sensor behind them are left out.
- **Processes** (the header's button, or the app menu): every process with
  its share of the whole device's CPU since the last reading and its
  memory (resident), sorted by CPU, memory, name or number, and searchable
  by name, command line, app id or number. Apps are shown by their id
  (SAM's running apps; a qml-runner also by the id it was started with).
  Kernel threads are hidden unless asked for in the preferences.
- **Tap a process** for its details (state, threads, parent, how long it
  has run, command line) and:
  - **Close app**, as its card would be closed (SAM's `close`);
  - **End process** (SIGTERM) or **Kill process** (SIGKILL).

  Each asks first. init (process 1), the kernel's threads and System
  Monitor itself cannot be ended; the dialog says why instead. The plugin
  checks this again, and that the process number still belongs to the
  process that was shown (by its start time), before it sends anything.
- **Back** (the back gesture, Escape) closes a question, then the dialog,
  then the page.
- **Preferences** (app menu): how often to read (every 1, 2, 5 or 10
  seconds; 2 to begin with), kernel threads in the list or not, and how long
  the last reading took.
- **Launch parameters:** `{"page": "processes"}` or `{"page":
  "preferences"}` opens that page.

Battery use
-----------
Nothing is read while System Monitor is in the background - minimised, or
behind another app or the lock screen - so it costs nothing there. The
processes are only read while their list is shown, and the overview's
figures are not worked out meanwhile.

Measured on the HP TouchPad (armv7, two cores, Linux 3.4, 326 processes)
with `tools/measure.sh`: the app's own CPU time over 60 seconds, reading
every 2 seconds. The screen was locked, so the readings were kept going with
`{"measure": true}` and nothing was drawn: this is the cost of reading and
working out the figures, not of drawing them.

| Page | App's CPU time |
|---|---|
| Overview | 0.6 % of one core (0.3 % of the device) |
| Processes | 3.9 % of one core (1.9 % of the device) |
| In the background | 0 (no CPU time at all in 60 seconds) |

The processes were first worked out in QML's JavaScript, which cost the
TouchPad 12 % of a core; reading and sorting them in C++ (`ProcessModel`),
telling the list only about the rows that changed, and not working out the
hidden overview brought that down to the figure above.

How it works
------------

| What | Where from |
|---|---|
| CPU load | `/proc/stat`, the difference between two readings |
| CPU clocks | `/sys/devices/system/cpu/cpuN/cpufreq/scaling_cur_freq` |
| Memory | `/proc/meminfo`; the level from `com.webos.service.memorymanager/getMemoryStatus` |
| Load, tasks, uptime | `/proc/loadavg`, `/proc/uptime` |
| Network | `/proc/net/dev`, the difference between two readings |
| Storage | `/proc/mounts`, and `statvfs()` in the plugin |
| Battery | `com.webos.service.battery/batteryStatusQuery`, or `/sys/class/power_supply/battery/uevent` |
| Temperatures | `/sys/class/thermal/thermal_zoneN/{type,temp}` |
| Processes | `/proc/<pid>/stat` and `cmdline`, in the plugin |
| Apps | `com.webos.service.applicationmanager/running` (subscribed) |
| Closing an app | `com.webos.service.applicationmanager/close` |
| Ending a process | `kill()` in the plugin, SIGTERM or SIGKILL only |

QML apps run as root, so every process's `/proc` entries can be read. The
plugin reads only under `/proc` and `/sys`.

- `qml/js/ProcParse.js`: the overview's parsing - what the files say, turned
  into figures, rates and shares. Plain JavaScript without QML, tested
  against files captured on the devices.
- `SysMonitorApp/procfs.*`: reading `/proc` and `/sys`, file system sizes,
  sending signals (with the checks above). `procreader.*` is it for QML.
- `SysMonitorApp/processmodel.*`: the processes' list model.
- `qml/Sampler.qml`: reads every interval while the card is in front, and
  keeps what it found for the pages.

Bus permissions (`requiredPermissions` in appinfo.json, and
`sysbus/*.perm.json` for the recipe): `application.launcher` (running apps,
close), `memorymanager.query` and `batteryd.management`.

Building
--------
CMake with Qt 6 (Core, Qml). The recipe builds and installs it; for
development, build the plugin with a LuneOS build's toolchain (the Camera
app's recipe sysroot has what it needs):

    tests/build-matrix.sh <build TMPDIR> <x86-64 sysroot> <Qt host dir> <out dir>

builds it six ways (see Tests), among them `<out dir>/arm-gcc` for armv7 and
`<out dir>/aarch64-gcc` for aarch64.

Installing on a device for development
--------------------------------------

    STRIP=<the target's strip> tools/install.sh <build dir> <adb serial>

packs the app with the plugin into an ipk and installs it through
`com.webos.appInstallService`, as Preware does. Then launch "System
Monitor" from the launcher.

Tests
-----

    tools/run-tests.sh [--all]

- **QML tests** (`tests/qml`, on the build host with luneos-components'
  desktop build): `tst_parse.qml` checks the parsing against `/proc` and
  `/sys` files captured on the TouchPad (armv7, Linux 3.4), the mindphone
  (armv7, 4.14) and the Q25 (aarch64, 5.10) (`tests/fixtures`), with
  figures worked out separately; `tst_ui.qml` runs the app with stand-ins
  for the plugin (over the same files) and the bus (with the replies those
  devices gave): the overview on each device, nothing read in the
  background, the processes read only while shown, sorting, search, apps by
  id, the details, ending and killing (and what may not be ended), closing
  an app, refusals shown, Escape, the preferences, launch parameters, and
  the layout at 480x800, 720x720, 1024x768 and 768x1024.
- **C++ unit tests** (`tests/unit`, gtest, through the x86-64 sysroot's
  loader): path confinement, reading files that report no size, the
  processes' stat lines (every line the three devices wrote), storage,
  signals (only SIGTERM and SIGKILL, never init, kernel threads, itself or
  a reused pid; a real child process ended), and the process model against
  the devices' processes - CPU shares, sorting, search, apps, rows updated
  in place (checked by Qt's QAbstractItemModelTester) and only the rows
  that changed announced.
- `--all` adds the **six builds** (GCC and Clang for armv7, aarch64 and
  x86-64, warnings as failures in the app's code), **static analysis**
  (`tests/static-analysis.sh`: gcc `-fanalyzer` at -O0 and -O2, the clang
  analyzer with the alpha checkers, clang-tidy, cppcheck, flawfinder,
  Coccinelle) and **ASan+UBSan** (GCC, Clang), **TSan** and **valgrind**
  (`tests/sanitizers.sh`).
- **On a device:** `tools/test-device.sh <adb serial>` runs
  `tests/device/tst_device.qml` with the device's qmltestrunner and the
  installed plugin, against the device's own `/proc` and `/sys`, and ends a
  `sleep 600` it starts for that (the only process it signals).
  `tools/measure.sh <adb serial> <overview|processes>` measures the app's
  own CPU use.

See `tests/README.md` for the details.

License
-------
Apache License 2.0, see LICENSE.
