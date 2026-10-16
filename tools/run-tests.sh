#!/bin/sh
# Runs the app's tests on the build host.
#
#   tools/run-tests.sh [--all]
#
# Always: the QML tests (tests/run-qml-tests.sh) - the parsing against the
# devices' captured files, and the app's pages with stand-ins for the plugin
# and the bus.
#
# With APP_SYSROOT (an x86-64 sysroot from tests/host-sysroot.sh) and
# QT_HOST (a LuneOS build's qtbase-native etc.): the C++ unit tests, built
# and run through the sysroot's loader.
#
# --all, with BUILD_TMPDIR (a LuneOS build's TMPDIR) as well: the six
# builds (tests/build-matrix.sh), static analysis (tests/static-analysis.sh)
# and the sanitizers and valgrind (tests/sanitizers.sh).
#
# Environment: LUNEOS_COMPONENTS (default ../luneos-components, with its
# desktop build), OUT (default build/test-output).
set -e
cd "$(dirname "$0")/.."
LC=${LUNEOS_COMPONENTS:-../luneos-components}
OUT=${OUT:-build/test-output}
mkdir -p "$OUT"
failed=""

echo "== QML tests"
if tests/run-qml-tests.sh "$LC" > "$OUT/qml.log" 2>&1; then
    grep '^Totals' "$OUT/qml.log"
else
    grep -E '^(FAIL|Totals)' "$OUT/qml.log"; failed="$failed qml"
fi

if [ -n "$APP_SYSROOT" ] && [ -n "$QT_HOST" ]; then
    echo "== C++ unit tests"
    B=$OUT/unit
    if cmake -S . -B "$B" -G Ninja -DBUILD_TESTING=ON -DCMAKE_TOOLCHAIN_FILE=tests/host-toolchain.cmake \
            -DTEST_SYSROOT="$APP_SYSROOT" -DQT_HOST_PATH="$QT_HOST/usr" > "$OUT/unit.cmake.log" 2>&1 \
            && ninja -C "$B" > "$OUT/unit.build.log" 2>&1; then
        mkdir -p "$OUT/tmp"
        if TMPDIR=$(pwd)/$OUT/tmp "$APP_SYSROOT/usr/lib/ld-linux-x86-64.so.2" --library-path "$APP_SYSROOT/usr/lib" \
                "$B/tests/sysmonitor-tests" > "$OUT/unit.log" 2>&1; then
            grep -E '^\[  PASSED  \]' "$OUT/unit.log"
        else
            grep -E 'FAILED' "$OUT/unit.log"; failed="$failed unit"
        fi
    else
        echo "build failed (see $OUT/unit.build.log)"; failed="$failed unit"
    fi
else
    echo "== C++ unit tests: skipped (set APP_SYSROOT and QT_HOST)"
fi

if [ "$1" = "--all" ]; then
    : "${BUILD_TMPDIR:?--all needs BUILD_TMPDIR}" "${APP_SYSROOT:?}" "${QT_HOST:?}"
    echo "== six builds"
    tests/build-matrix.sh "$BUILD_TMPDIR" "$APP_SYSROOT" "$QT_HOST" "$(pwd)/$OUT/matrix" || failed="$failed matrix"
    echo "== static analysis"
    APP_SYSROOT=$APP_SYSROOT tests/static-analysis.sh || failed="$failed static"
    echo "== sanitizers and valgrind"
    tests/sanitizers.sh "$APP_SYSROOT" "$QT_HOST" "$(pwd)/$OUT/sanitizers" || failed="$failed sanitizers"
fi

if [ -n "$failed" ]; then
    echo "FAILED:$failed"
    exit 1
fi
echo "PASS"
