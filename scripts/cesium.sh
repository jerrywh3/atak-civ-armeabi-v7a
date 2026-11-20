#!/bin/bash
# cesium-native 0.40.1 for armeabi-v7a, via the repo's own build-android.sh.
# The repo ships only the wrapper; the CesiumGS source must be cloned beside it.
set -u
cd /src/cesium-native || exit 90
if [ ! -d cesium-native/.git ]; then
  git clone --depth 1 --branch v0.40.1 --recurse-submodules --shallow-submodules \
    https://github.com/CesiumGS/cesium-native.git || { echo "CESIUM FAILED AT: clone"; exit 1; }
fi
# cesium-native needs a far newer CMake than the 3.14.7 the rest of ATAK pins.
if [ ! -x /las/cmake-venv/bin/cmake ]; then
  python3 -m venv /las/cmake-venv && /las/cmake-venv/bin/pip install -q "cmake==3.27.9" ninja \
    || { echo "CESIUM FAILED AT: cmake venv"; exit 1; }
fi
export PATH=/las/cmake-venv/bin:$PATH
export ANDROID_NDK_HOME=/opt/android-sdk/ndk/25.1.8937393
export ANDROID_NDK_ROOT=$ANDROID_NDK_HOME
export ANDROID_ABI=armeabi-v7a
export WARNINGS_AS_ERRORS=OFF
export VCPKG_FORCE_SYSTEM_BINARIES=0
# The wrapper's toolchain hardcodes arm64-v8a; take the ABI from the environment
# instead. (Defensive - not proven to be what breaks a v7a build.)
sed -i 's|SET(CMAKE_ANDROID_ARCH_ABI arm64-v8a)|SET(CMAKE_ANDROID_ARCH_ABI "$ENV{ANDROID_ABI}")|' cmake/toolchains/android.cmake
cmake --version | head -1; date '+%H:%M:%S'
bash build-android.sh
rc=$?
date '+%H:%M:%S'
ls build/android-armeabi-v7a/lib/*.a 2>/dev/null | wc -l
[ "$rc" = 0 ] && echo "CESIUM OK" || echo "CESIUM FAILED AT: build-android.sh (rc $rc)"
