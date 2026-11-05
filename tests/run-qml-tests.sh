#!/bin/sh
# Runs the QML tests on the build host: the parsing (tst_parse.qml) and the
# app's pages (tst_ui.qml) once, with luneos-components' desktop stand-ins
# and the app's own stand-ins for its plugin and the bus (qml/imports); then
# every screen (tst_screens.qml) once per device screen in PROFILES - by
# default the mindphone, the Q25, the TouchPad and the FuriPhone FLX1s
# (radon), each saved as build/test-output/ui/<profile>-<screen>.png.
#
#   tests/run-qml-tests.sh [path to luneos-components [qmltestrunner arguments]]
#   PROFILES=q25 tests/run-qml-tests.sh ...      one screen only
#   TESTS= tests/run-qml-tests.sh ...            only the screens
#
# luneos-components needs its desktop build (CONFIG+=desktop, see its
# README) for the style plugin. A later -import wins over an earlier one:
# the desktop stand-ins over the real modules, the app's over both.
#
# The stand-ins read their profile, and with it the window's size and the
# grid unit, once as they load, and qmltestrunner passes no --profile on:
# each profile runs against a copy of LunaNext.Common whose default profile
# is that screen, imported ahead of the stand-ins.
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
[ $# -gt 0 ] && shift
PROFILES=${PROFILES:-mindphone q25 tp radon}
TESTS=${TESTS-tst_parse.qml tst_ui.qml}
mkdir -p build/test-output/ui
CONF=$(mktemp -d "$(pwd)/build/qmltest.XXXXXX")
trap 'rm -rf "$CONF"' EXIT

# The preferences go to a throwaway directory, not the user's. The stand-ins
# read the fixtures with XMLHttpRequest, which needs file reading allowed.
run() {
    rm -rf "$CONF/config" "$CONF/cache"
    XDG_CONFIG_HOME=$CONF/config XDG_CACHE_HOME=$CONF/cache QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} \
    QML_XHR_ALLOW_FILE_READ=1 QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS \
        ${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner} \
        -import "$LC/modules" -import "$LC/test/imports" "$@"
}

status=0
for t in $TESTS; do
    echo "--- $t"
    run -import tests/qml/imports -input "tests/qml/$t" "$@" || status=1
done
for profile in $PROFILES; do
    common=$CONF/profile-$profile/LunaNext/Common
    mkdir -p "$common"
    cp "$LC"/test/imports/LunaNext/Common/* "$common/"
    sed -i "s/^var defaultProfile = .*/var defaultProfile = \"$profile\";/" "$common/SettingsStub.js"
    if ! grep -q "^var defaultProfile = \"$profile\";" "$common/SettingsStub.js"; then
        echo "could not select profile $profile in SettingsStub.js" >&2
        status=1
        continue
    fi
    echo "--- tst_screens.qml ($profile)"
    run -import "$CONF/profile-$profile" -import tests/qml/imports -input tests/qml/tst_screens.qml "$@" || status=1
done
exit $status
