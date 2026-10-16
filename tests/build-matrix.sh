#!/bin/sh
# Builds the plugin (and on x86-64 the unit tests) six ways - GCC and Clang
# for armv7, aarch64 and x86-64 - with extra warnings, and fails on any
# warning in the app's own code.
#
#   tests/build-matrix.sh <build TMPDIR> <x86-64 sysroot> <Qt host dir> <out dir>
#
# armv7 and aarch64 build against the Camera app's recipe sysroots (they
# hold Qt Multimedia) with that recipe's GCC; Clang is the build host's,
# pointed at the same sysroots. The x86-64 sysroot comes from
# tests/host-sysroot.sh, the Qt host dir is qtbase-native etc.
set -e
cd "$(dirname "$0")/.."
TMPD=${1:?usage: build-matrix.sh <build TMPDIR> <x86-64 sysroot> <Qt host dir> <out dir>}
X86=${2:?}
QTHOST=${3:?}
OUT=${4:?}
SRC=$(pwd)
WARN="-Wall -Wextra -Wpedantic -Wshadow -Wnon-virtual-dtor -Wold-style-cast -Wcast-align -Wformat=2"
mkdir -p "$OUT"
FAILED=$OUT/failed
rm -f "$FAILED"

camera_dir() {
    ls -d "$TMPD"/work/"$1"/org.webosports.app.camera/*/ | head -n 1
}

build() {   # name toolchain-args...
    name=$1; shift
    dir=$OUT/$name
    rm -rf "$dir"
    if ! cmake -S "$SRC" -B "$dir" -G Ninja -DCMAKE_BUILD_TYPE=Release "$@" > "$dir.cmake.log" 2>&1; then
        echo "$name: configure FAILED (see $dir.cmake.log)"; touch "$FAILED"; return
    fi
    if ! ninja -C "$dir" > "$dir.log" 2>&1; then
        echo "$name: build FAILED (see $dir.log)"; touch "$FAILED"; return
    fi
    # Warnings from the app's own files; Qt's headers are reported apart.
    own=$(grep -E "warning:" "$dir.log" | grep -E "$SRC/(SysMonitorApp|tests)/" | sort -u | wc -l)
    other=$(grep -E "warning:" "$dir.log" | grep -v -E "$SRC/(SysMonitorApp|tests)/" | sort -u | wc -l)
    echo "$name: built, $own warnings in our code, $other elsewhere"
    [ "$own" -eq 0 ] || touch "$FAILED"
}

# Clang has no idea of Yocto's layout: the GCC runtime (crtbeginS.o,
# libgcc) is in usr/lib/<triple>/<version>, libstdc++'s headers in
# usr/include/c++/<version>.
clang_flags() {   # sysroot triple
    gcclib=$(dirname "$(find "$1/usr/lib" -name crtbeginS.o | head -n 1)")
    ver=$(basename "$gcclib")
    echo "-B$gcclib -isystem $1/usr/include/c++/$ver -isystem $1/usr/include/c++/$ver/$2"
}

clang_ldflags() {   # sysroot [linker]
    gcclib=$(dirname "$(find "$1/usr/lib" -name crtbeginS.o | head -n 1)")
    echo "-L$gcclib${2:+ --ld-path=$2}"
}

for arch in arm aarch64; do
  (
    if [ $arch = arm ]; then
        D=$(camera_dir cortexa8t2hf-neon-halium-webos-linux-gnueabi); triple=arm-webos-linux-gnueabi
        cpu="-mthumb -mfpu=neon -mfloat-abi=hard -mcpu=cortex-a8"
    else
        D=$(camera_dir aarch64-webos-linux); triple=aarch64-webos-linux; cpu=""
    fi
    NATIVE=$D/recipe-sysroot-native/usr
    PATH=$NATIVE/bin/$triple:$NATIVE/bin:$PATH
    export PATH
    build "$arch-gcc" -DCMAKE_TOOLCHAIN_FILE="$D/toolchain.cmake" \
        -DQT_HOST_PATH="$NATIVE" -DQT_HOST_PATH_CMAKE_DIR="$NATIVE/lib/cmake" \
        -DCMAKE_CXX_FLAGS_RELEASE="-O2 $WARN"
    flags=$(clang_flags "$D/recipe-sysroot" "$triple")
    ld=$(clang_ldflags "$D/recipe-sysroot" "$NATIVE/bin/$triple/$triple-ld")
    build "$arch-clang" -DCMAKE_TOOLCHAIN_FILE="$SRC/tests/host-toolchain.cmake" \
        -DTEST_SYSROOT="$D/recipe-sysroot" -DTEST_TARGET="$triple" \
        -DQT_HOST_PATH="$NATIVE" -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_CXX_FLAGS="$cpu $flags $WARN" -DCMAKE_C_FLAGS="$cpu $flags" \
        -DCMAKE_SHARED_LINKER_FLAGS="$ld" -DCMAKE_MODULE_LINKER_FLAGS="$ld" -DCMAKE_EXE_LINKER_FLAGS="$ld"
  )
done

for cc in gcc clang; do
    cxx=$([ $cc = gcc ] && echo g++ || echo clang++)
    extra=""
    ld=""
    if [ $cc = clang ]; then extra=$(clang_flags "$X86" x86_64-webos-linux); ld=$(clang_ldflags "$X86"); fi
    build "x86_64-$cc" -DBUILD_TESTING=ON -DCMAKE_TOOLCHAIN_FILE="$SRC/tests/host-toolchain.cmake" \
        -DTEST_SYSROOT="$X86" -DQT_HOST_PATH="$QTHOST/usr" \
        -DCMAKE_C_COMPILER=$cc -DCMAKE_CXX_COMPILER=$cxx -DCMAKE_CXX_FLAGS="$extra $WARN" -DCMAKE_C_FLAGS="$extra" \
        -DCMAKE_SHARED_LINKER_FLAGS="$ld" -DCMAKE_MODULE_LINKER_FLAGS="$ld" -DCMAKE_EXE_LINKER_FLAGS="$ld"
done

[ ! -e "$FAILED" ]
