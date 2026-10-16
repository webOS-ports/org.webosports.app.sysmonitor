#!/bin/bash
# Runs tests/device/tst_device.qml on a device with its qmltestrunner and the
# installed app's plugin: the plugin and the parsing against the device's
# real /proc and /sys, and ending a process - a "sleep 600" started here for
# it, the only process it signals.
#
#   tools/test-device.sh <adb serial> [directory on the device]
#
# The directory (/tmp/sm-devtest by default) is made for the run and removed
# after it; give another when the device's /tmp is full.
# Install the app first (tools/install.sh). Nothing is shown on the screen
# (offscreen), and the app itself is not started.
set -e
cd "$(dirname "$0")/.."
SERIAL=${1:?usage: tools/test-device.sh <adb serial>}
ADB="adb -s $SERIAL"
APP=/media/cryptofs/apps/usr/palm/applications/org.webosports.app.sysmonitor
D=${2:-/tmp/sm-devtest}

[ "$($ADB shell "test -f $APP/SysMonitorApp/qmldir && echo yes" | tr -d "\r")" = yes ] || { echo "the app is not installed"; exit 1; }
$ADB shell "rm -rf $D; mkdir -p $D"
$ADB push tests/device/tst_device.qml $D/ >/dev/null
echo "== $SERIAL: $($ADB shell uname -m | tr -d '\r')"
set +e
# The sleep is started by the same shell as the tests (a background job of
# an adb shell that has ended does not live on), and ended by it at the end
# if the tests have not.
$ADB shell "sleep 600 > /dev/null 2>&1 < /dev/null & S=\$!; echo \$S > $D/sleep.pid; echo \"dummy sleep is pid \$S\" > $D/out.txt; \
    cd $D && QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 LC_ALL=C.UTF-8 qmltestrunner -import $APP -input $D/tst_device.qml >> $D/out.txt 2>&1; \
    echo exit \$? >> $D/out.txt; kill \$S 2>/dev/null; wait \$S 2>/dev/null"
$ADB shell "cat $D/out.txt" | tr -d '\r' | grep -vE '^PASS|^QDEBUG|Config:|^\*\*\*'
result=$($ADB shell "grep -c '^FAIL' $D/out.txt" | tr -d '\r')
$ADB shell "rm -rf $D"
[ "$result" = 0 ]
