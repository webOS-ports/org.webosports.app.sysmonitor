#!/bin/sh
# Builds the unit tests with ASan+UBSan (GCC and Clang) and TSan (GCC)
# against the x86-64 sysroot from tests/host-sysroot.sh, runs each through
# the sysroot's loader, and runs the plain build under valgrind memcheck.
#
#   tests/sanitizers.sh <x86-64 sysroot> <Qt host dir> <out dir>
#
# Fails if any run reports an error. TSan re-executes itself to turn off
# address randomisation, which loses the loader, so it runs under
# "setarch x86_64 -R".
set -u
cd "$(dirname "$0")/.."
X86=${1:?usage: tests/sanitizers.sh <x86-64 sysroot> <Qt host dir> <out dir>}
QTHOST=${2:?}
OUT=${3:?}
SRC=$(pwd)
mkdir -p "$OUT/tmp"
LOADER="$X86/usr/lib/ld-linux-x86-64.so.2 --library-path $X86/usr/lib"
fail=0

gcclib=$(dirname "$(find "$X86/usr/lib" -name crtbeginS.o | head -n 1)")
ver=$(basename "$gcclib")
CLANG_INC="-B$gcclib -isystem $X86/usr/include/c++/$ver -isystem $X86/usr/include/c++/$ver/x86_64-webos-linux"

build() {   # name cc cxx flags ldflags
    dir=$OUT/$1
    rm -rf "$dir"
    cmake -S "$SRC" -B "$dir" -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON \
        -DCMAKE_TOOLCHAIN_FILE="$SRC/tests/host-toolchain.cmake" -DTEST_SYSROOT="$X86" -DQT_HOST_PATH="$QTHOST/usr" \
        -DCMAKE_C_COMPILER="$2" -DCMAKE_CXX_COMPILER="$3" -DCMAKE_CXX_FLAGS="$4" \
        -DCMAKE_EXE_LINKER_FLAGS="$5" -DCMAKE_MODULE_LINKER_FLAGS="$5" > "$dir.cmake.log" 2>&1 \
        && ninja -C "$dir" tests/sysmonitor-tests > "$dir.log" 2>&1 || { echo "$1: build FAILED (see $dir.log)"; fail=1; return 1; }
}

run() {   # name command...
    name=$1; shift
    if TMPDIR=$OUT/tmp "$@" > "$OUT/$name.run.log" 2>&1 && ! grep -qE 'ERROR: (Address|Thread|Leak)Sanitizer|runtime error:|WARNING: ThreadSanitizer' "$OUT/$name.run.log"; then
        echo "$name: $(grep -E '^\[  PASSED  \]' "$OUT/$name.run.log")"
    else
        echo "$name: FAILED (see $OUT/$name.run.log)"; fail=1
    fi
}

SAN="-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=undefined"
if build asan-gcc gcc g++ "$SAN" "$SAN -static-libasan -static-libubsan"; then
    run asan-gcc env ASAN_OPTIONS=detect_leaks=1 $LOADER "$OUT/asan-gcc/tests/sysmonitor-tests"
fi
if build asan-clang clang clang++ "$CLANG_INC $SAN" "-L$gcclib $SAN"; then
    run asan-clang env ASAN_OPTIONS=detect_leaks=1 $LOADER "$OUT/asan-clang/tests/sysmonitor-tests"
fi
if build tsan-gcc gcc g++ "-fsanitize=thread" "-fsanitize=thread -static-libtsan"; then
    run tsan-gcc setarch x86_64 -R $LOADER "$OUT/tsan-gcc/tests/sysmonitor-tests"
fi
if build plain-gcc gcc g++ "-g -O1" ""; then
    run valgrind valgrind --error-exitcode=9 --leak-check=full --errors-for-leak-kinds=definite \
        $LOADER "$OUT/plain-gcc/tests/sysmonitor-tests"
fi
exit $fail
