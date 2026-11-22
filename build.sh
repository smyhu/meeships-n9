#!/bin/sh
# Cross-build the MeeShips launcher for Nokia N9 (Harmattan PR1.3, ARMv7 hard-float).
# NEVER add -fno-rtti: MInputContext dynamic_casts QML items and crashes.
# TC = unpacked n9-toolchain (hdr/, qtdev/, rt/, ld-arm); see tools/README-toolchain.md.
set -e
TC=${TC:-/tmp/claude-0/x/tc}
D=$(cd "$(dirname "$0")" && pwd)
VER=${VER:-0.1.5}
OUT=${OUT:-$D/build}
mkdir -p $OUT
H=$TC/hdr/usr/arm-linux-gnueabihf
Q=$TC/qtdev/usr/include/qt4
L=$TC/rt/usr/lib
SDKL=$TC/qtdev/usr/lib
for h in helper gamenet; do
  QEMU_LD_PREFIX=$TC/rt qemu-arm-static -E LD_LIBRARY_PATH=/usr/lib:/lib $TC/rt/host-moc -I$Q -I$Q/QtMobility $D/src/$h.h -o $OUT/moc_$h.cpp
done
T="--target=arm-linux-gnueabihf -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb"
CF="$T -O2 -fno-pic -nostdinc -isystem $(clang -print-resource-dir)/include -isystem $H/include/c++/13 -isystem $H/include/c++/13/arm-linux-gnueabihf -isystem $H/include -U_FORTIFY_SOURCE -D_FILE_OFFSET_BITS=32"
DEFS="-DQT_NO_DEBUG -DQT_SHARED -DAPP_VERSION=\"$VER\" -DAPP_NAME=\"meeships-n9\" -DAPP_TITLE=\"MeeShips\""
OBJS=""
for f in $D/src/*.cpp $OUT/moc_*.cpp; do
  o=$OUT/$(basename $f .cpp).o
  clang++ $CF -std=gnu++98 -fno-exceptions -fno-threadsafe-statics $DEFS -Wno-deprecated-declarations \
    -I $Q -I $Q/QtCore -I $Q/QtGui -I $Q/QtNetwork -I $Q/QtSql -I $Q/QtDeclarative -I $Q/QtMobility -I $Q/QtLocation -I $Q/QtSystemInfo -I $D/src -c $f -o $o
  OBJS="$OBJS $o"
done
G=$TC/hdr/usr/lib/gcc-cross/arm-linux-gnueabihf/13
clang++ $T --ld-path=$TC/ld-arm -no-pie -nostdlib -Wl,--allow-shlib-undefined -Wl,--as-needed -Wl,--hash-style=both -Wl,-z,norelro -Wl,-dynamic-linker,/lib/ld-linux.so.3 \
  $SDKL/crt1.o $SDKL/crti.o $G/crtbegin.o $OBJS \
  $L/libQtSystemInfo.so.1 $L/libQtDeclarative.so.4 $L/libQtNetwork.so.4 $L/libQtGui.so.4 $L/libQtCore.so.4 \
  $L/libstdc++.so.6 $TC/rt/lib/libc.so.6 $TC/rt/lib/libm.so.6 $SDKL/libc_nonshared.a $TC/rt/lib/libgcc_s.so.1 \
  $G/crtend.o $SDKL/crtn.o -o $OUT/meeships-n9
llvm-strip $OUT/meeships-n9
file $OUT/meeships-n9
