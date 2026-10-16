#!/bin/sh
# Runs the QML tests on the build host: the parsing (tst_parse.qml) and the
# app's pages (tst_ui.qml) with luneos-components' desktop stand-ins and the
# app's own stand-ins for its plugin and the bus (qml/imports).
#
#   tests/run-qml-tests.sh [path to luneos-components [qmltestrunner arguments]]
#
# luneos-components needs its desktop build (CONFIG+=desktop, see its
# README) for the style plugin. A later -import wins over an earlier one:
# the desktop stand-ins over the real modules, the app's over both.
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
[ $# -gt 0 ] && shift
mkdir -p build
CONF=$(mktemp -d "$(pwd)/build/qmltest.XXXXXX")
trap 'rm -rf "$CONF"' EXIT
# The preferences go to a throwaway directory, not the user's. The stand-ins
# read the fixtures with XMLHttpRequest, which needs file reading allowed.
XDG_CONFIG_HOME=$CONF XDG_CACHE_HOME=$CONF/cache QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} \
QML_XHR_ALLOW_FILE_READ=1 QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS \
    ${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner} \
    -import "$LC/modules" -import "$LC/test/imports" -import tests/qml/imports \
    -input tests/qml "$@"
