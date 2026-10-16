System Monitor tests
====================

## Fixtures (`fixtures/<device>`)

Captured on 2026-10-16 from the HP TouchPad (armv7, Linux 3.4), the
mindphone (armv7, 4.14) and the Q25 (aarch64, 5.10):

- `stat1`, `stat2`; `netdev1`, `netdev2`: `/proc/stat` and `/proc/net/dev`
  two seconds apart.
- `snap-stat-a`, `snap-pids-a`, `snap-stat-b`, `snap-pids-b` (TouchPad and
  mindphone): `/proc/stat` and every `/proc/<pid>/stat`, then the same three
  seconds later.
- `pid-stats`: every `/proc/<pid>/stat`; `cmdlines`: each process's
  command line (pid, a tab, the arguments with spaces for NULs).
- `meminfo`, `loadavg`, `uptime`, `mounts`.
- `cpufreq`: per core `name online cur max min` (kHz) from cpufreq;
  `thermal`: per zone `name type temp`; `battery-uevent`.
- `sam-running.json`, `memstatus.json`, `battery.json`: what SAM's
  `running`, memorymanager's `getMemoryStatus` and batteryd's
  `batteryStatusQuery` answered.

The figures the tests expect were worked out from these files with a
separate script, not with the app's code.

## QML (`qml/`), on the build host

    tests/run-qml-tests.sh [path to luneos-components [qmltestrunner arguments]]

- `tst_parse.qml`: `qml/js/ProcParse.js` and `Format.js`.
- `tst_ui.qml`: `qml/main.qml` and its pages with luneos-components'
  desktop stand-ins and `qml/imports`: a ProcReader and a ProcessModel over
  the fixtures (the test picks the device and which reading), and a
  LunaService answering from the fixtures and recording every call.

luneos-components needs its desktop build (`CONFIG+=desktop`, see its
README) for the style plugin. The stand-ins read the fixtures with
XMLHttpRequest, so the script sets `QML_XHR_ALLOW_FILE_READ=1`.

## Unit tests (`unit/`), gtest

The plugin's C++: `ProcFs` (`procfs.h`), `ProcReader` and `ProcessModel`,
the last over a `/proc` laid out from the fixtures in a temporary
directory. There is no recipe sysroot with Qt and googletest together, so
`host-sysroot.sh` puts one together from a build's sysroot components and
`host-toolchain.cmake` builds against it with the host's compiler and the
build's native Qt tools (moc must match the target Qt):

    tests/host-sysroot.sh <build TMPDIR> <sysroot>
    cmake -S . -B build/tests -G Ninja -DBUILD_TESTING=ON \
        -DCMAKE_TOOLCHAIN_FILE=tests/host-toolchain.cmake \
        -DTEST_SYSROOT=<sysroot> -DQT_HOST_PATH=<qtbase-native etc.>/usr
    ninja -C build/tests
    <sysroot>/usr/lib/ld-linux-x86-64.so.2 --library-path <sysroot>/usr/lib \
        build/tests/tests/sysmonitor-tests

`tools/run-tests.sh` does this with `APP_SYSROOT` and `QT_HOST` set. One
test ends a child process of its own (fork, then SIGTERM); no other process
is signalled.

## Sanitizers and valgrind

    tests/sanitizers.sh <sysroot> <Qt host dir> <out dir>

ASan+UBSan with GCC (`-static-libasan -static-libubsan`) and Clang, TSan
with GCC (under `setarch x86_64 -R`: TSan re-executes itself, which would
lose the sysroot's loader), and valgrind memcheck on a plain build.

## Static analysis

    APP_SYSROOT=<sysroot> tests/static-analysis.sh

gcc `-fanalyzer` at -O0 and -O2, the clang analyzer with the alpha
checkers, clang-tidy, cppcheck (exhaustive, inconclusive), flawfinder and
Coccinelle with `cocci/`. sparse parses C only. The lines flawfinder flags
that are not faults say why and carry `Flawfinder: ignore`; any other hit
fails the run.

## Six builds

    tests/build-matrix.sh <build TMPDIR> <x86-64 sysroot> <Qt host dir> <out dir>

GCC and Clang for armv7, aarch64 and x86-64, with `-Wall -Wextra
-Wpedantic -Wshadow -Wold-style-cast` and more; fails on any warning in the
app's code. armv7 and aarch64 build against the Camera app's recipe
sysroots with that recipe's GCC; Clang is the build host's.

## On a device

    tools/install.sh <build dir> <adb serial>
    tools/test-device.sh <adb serial> [directory on the device]
    tools/measure.sh <adb serial> <overview|processes> [seconds] [interval]

`test-device.sh` runs `device/tst_device.qml` with the device's
qmltestrunner (offscreen) and the installed plugin against the device's own
`/proc` and `/sys`: the overview's files parsed, CPU over a second, thermal
zones and clocks, storage, reading confined to `/proc` and `/sys`, the
process model, refusals (init, kthreadd, itself, a wrong start time) and
ending a `sleep 600` that the same shell started for it.

`measure.sh` starts the app with `{"measure": true}` (readings go on with
the screen locked or another app in front) and counts its CPU time.
