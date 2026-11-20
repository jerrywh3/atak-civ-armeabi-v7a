#!/bin/bash
# Stage 5b: assimp alone, with the NDK's OWN cmake toolchain file.
#
# WHY: takthirdparty asks for CMake's BUILT-IN Android support
# (-DCMAKE_SYSTEM_NAME=Android -DCMAKE_ANDROID_NDK=...). CMake 3.14 implements
# that by globbing <ndk>/{build/core/,}toolchains/*-[0-9].[0-9]/config.mk to
# learn the gcc toolchain name. NDK r21e no longer ships those config.mk files,
# so the name resolves EMPTY and clang is handed
#     --gcc-toolchain=<ndk>/toolchains//prebuilt/linux-x86_64
# a path that does not exist -> clang falls back to the HOST binutils ->
#     /usr/bin/ld: unrecognised emulation mode: armelf_linux_eabi
# Compiling worked; only linking failed, which is what made it look like an
# architecture problem rather than a lookup bug.
#
# FIX: bypass CMake's built-in Android support and use the NDK's own
# android.toolchain.cmake, which is version-matched to r21e and sets the
# compiler, linker, ar/ranlib/strip and sysroot explicitly. The pinned
# CMake 3.14.7 is kept everywhere.
set -u
cd /src/takthirdparty || exit 90

export ANDROID_NDK=/opt/android-ndk-r21e
export ANDROID_NDK_HOME=/opt/android-ndk-r21e

echo "=== assimp retry with NDK android.toolchain.cmake ==="; date '+%H:%M:%S'

make TARGET=android-armeabi-v7a GDAL_USE_KDU=no \
  assimp_CONFIG_EX="-DCMAKE_TOOLCHAIN_FILE=/opt/android-ndk-r21e/build/cmake/android.toolchain.cmake -DANDROID_ABI=armeabi-v7a -DANDROID_PLATFORM=android-21 -DANDROID_STL=c++_shared -DANDROID_ARM_NEON=ON" \
  build_assimp
rc=$?
echo "=== assimp make exit: $rc ==="
ls -l builds/android-armeabi-v7a-release/lib/libassimp.so \
      builds/android-armeabi-v7a-release/lib/libjassimp.so 2>&1
[ "$rc" = "0" ] && echo "ASSIMP OK" || echo "ASSIMP FAILED AT: make build_assimp"
exit $rc
