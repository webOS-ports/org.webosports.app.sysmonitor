#!/bin/bash
# Measures what System Monitor itself costs on a device: starts it with
# {"measure": true} (readings go on even with the screen locked or another
# app in front) on the overview or the processes, lets it settle, and
# counts the CPU time its process used over a while against the time all
# cores had. Prints the app's own log of how long its readings took.
# Closes the app at the end.
#
#   tools/measure.sh <adb serial> <overview|processes> [seconds] [interval]
#
# interval is the preference in seconds (1, 2, 5 or 10), set before the
# start and put back after. With the card in the background nothing is
# drawn, so this is the cost of reading and working out the figures, not
# of drawing them; with the app in front both count.
set -e
SERIAL=${1:?usage: tools/measure.sh <adb serial> <overview|processes> [seconds] [interval]}
PAGE=${2:?}
SECS=${3:-60}
INTERVAL=${4:-}
ID=org.webosports.app.sysmonitor
PREFS=/home/root/.config/$ID/preferences.ini
ADB="adb -s $SERIAL"

close() {
    $ADB shell "luna-send -n 1 -w 3000 luna://com.webos.service.applicationmanager/closeByAppId '{\"id\":\"$ID\"}' >/dev/null 2>&1" || true
}
close
sleep 2
if [ -n "$INTERVAL" ]; then
    $ADB shell "cp $PREFS /tmp/sm-prefs.saved 2>/dev/null || rm -f /tmp/sm-prefs.saved; mkdir -p \$(dirname $PREFS); \
        if [ -f $PREFS ] && grep -q '^interval=' $PREFS; then sed -i 's/^interval=.*/interval=$INTERVAL/' $PREFS; \
        else printf '[monitor]\ninterval=$INTERVAL\n' >> $PREFS; fi"
fi
$ADB shell "luna-send -n 1 -w 8000 luna://com.webos.service.applicationmanager/launch '{\"id\":\"$ID\",\"params\":{\"measure\":true,\"page\":\"$PAGE\"}}' > /tmp/sm-l.out 2>&1"
sleep 12
PID=$($ADB shell "for p in \$(pidof qml-runner); do grep -q $ID /proc/\$p/cmdline 2>/dev/null && echo \$p; done" | tr -d '\r' | head -n 1)
[ -n "$PID" ] || { echo "the app is not running"; exit 1; }
HZ=$($ADB shell "getconf CLK_TCK 2>/dev/null || echo 100" | tr -d '\r')
echo "== $SERIAL $PAGE: pid $PID, $SECS s, CLK_TCK $HZ, $($ADB shell 'grep -c ^processor /proc/cpuinfo' | tr -d '\r') cores"
$ADB shell "a=\$(cat /proc/$PID/stat); s1=\$(head -n 1 /proc/stat); sleep $SECS; b=\$(cat /proc/$PID/stat); s2=\$(head -n 1 /proc/stat); \
    echo \"\$a\"; echo \"\$s1\"; echo \"\$b\"; echo \"\$s2\"" | tr -d '\r' | python3 -I -c '
import sys
l = sys.stdin.read().split("\n")
def ticks(x):
    w = x[x.rindex(")") + 2:].split()
    return int(w[11]) + int(w[12]), int(w[21])
def total(x):
    return sum(int(v) for v in x.split()[1:9])
a, _ = ticks(l[0])
b, rss = ticks(l[2])
dt = total(l[3]) - total(l[1])
secs = float(sys.argv[1]); hz = float(sys.argv[2])
print("app: %d ticks in %.0f s = %.2f%% of one core, %.2f%% of the device; resident %d KiB (4 KiB pages)"
      % (b - a, secs, (b - a) * 100.0 / (hz * secs), (b - a) * 100.0 / dt if dt else -1, rss * 4))
' "$SECS" "$HZ"
$ADB shell "journalctl -b --no-pager --since '-$((SECS + 15))s' 2>/dev/null | grep 'qml-runner\[$PID\]' | grep -E 'reading [0-9]+ took' | sed 's/.*System Monitor: //'"
$ADB shell "luna-send -n 1 -w 8000 luna://com.webos.service.applicationmanager/launch '{\"id\":\"$ID\",\"params\":{\"measure\":false}}' > /tmp/sm-l.out 2>&1"
close
if [ -n "$INTERVAL" ]; then
    $ADB shell "if [ -f /tmp/sm-prefs.saved ]; then cp /tmp/sm-prefs.saved $PREFS; else rm -f $PREFS; fi"
fi
