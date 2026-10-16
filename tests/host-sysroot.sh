#!/bin/sh
# Puts together a sysroot for building and running the unit tests on an
# x86-64 build host, from a LuneOS build's sysroot components: Qt, googletest
# and what they load. No recipe sysroot has all of these at once.
#
#   tests/host-sysroot.sh <TMPDIR of the build> <output dir> [arch]
#
# arch is the sysroots-components directory, corei7-64 by default; aarch64
# or cortexa8t2hf-neon-halium give the sysroots for the compile checks.
set -e
TMPDIR_BUILD=${1:?usage: host-sysroot.sh <build TMPDIR> <output dir> [arch]}
OUT=${2:?usage: host-sysroot.sh <build TMPDIR> <output dir> [arch]}
ARCH=${3:-corei7-64}
SC=$TMPDIR_BUILD/sysroots-components/$ARCH

for c in glibc gcc-runtime libgcc zlib zstd openssl libffi glib-2.0 icu pcre2 double-conversion \
         libb2 brotli dbus systemd libcap util-linux-libuuid libxcrypt \
         qtbase qtdeclarative qtmultimedia googletest pulseaudio libsndfile1 libtool \
         gstreamer1.0 gstreamer1.0-plugins-base orc libdrm libxkbcommon wayland \
         freetype libpng harfbuzz fontconfig expat graphite2 libglvnd mesa \
         linux-libc-headers libunwind libpthread-stubs \
         cairo elfutils flac libogg libpciaccess libpcre2 libvorbis libxml2 llvm mtdev \
         pmloglib qtquick3d qtsvg util-linux libpbnjson pixman qtquicktimeline qtshadertools \
         gmp uriparser yajl; do
    if [ -d "$SC/$c" ]; then
        cp -a "$SC/$c/." "$OUT/"
    fi
done
# The components drop their sysroot-providers stamps alongside; not needed.
rm -rf "$OUT/sysroot-providers"
echo "sysroot for $ARCH in $OUT"
