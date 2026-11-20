#!/bin/bash
# The "correct thing": replay TAK's own CI (the .gitlab-ci.yml inside each
# depends/ tarball, jobs laszip_android_armeabi + liblas_android_armeabi) to
# produce conan LASzip/3.4.3c, conan libLAS/1.8.2f and the libLAS AAR for
# armeabi-v7a. Same CMake version (3.24.3) and NDK (r25b) their CI names.
set -u
die() { echo "LAS FAILED AT: $*"; exit 1; }
[ -x /las/cmake324/bin/cmake ] || { python3 -m venv /las/cmake324 && /las/cmake324/bin/pip install -q "cmake==3.24.3"; } || die "cmake venv"
export PATH=/las/cmake324/bin:$PATH
export ANDROID_NDK_HOME=/opt/android-sdk/ndk/25.1.8937393 ANDROID_NDK=/opt/android-sdk/ndk/25.1.8937393
export ANDROID_NDK_ROOT=$ANDROID_NDK
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ABI=armeabi-v7a
CS="-s arch=armv7 -s os=Android -s os.api_level=21 -s compiler.version=8"
COMMON="-DCMAKE_SYSTEM_NAME=Android -DCMAKE_SYSTEM_VERSION=21 -DCMAKE_ANDROID_ARCH_ABI=$ABI -DCMAKE_BUILD_TYPE=Release -DCMAKE_ANDROID_NDK=$ANDROID_NDK -DCMAKE_ANDROID_STL_TYPE=c++_static"
cmake --version | head -1

echo "=== LASzip ==="; date '+%H:%M:%S'
cd /las/LASzip || die "cd LASzip"
rm -rf build-android-$ABI && mkdir build-android-$ABI && cd build-android-$ABI
cmake .. -G "Unix Makefiles" $COMMON -DCMAKE_CXX_FLAGS="-fPIC -fexceptions -frtti -std=c++11" -DLASZIP_BUILD_STATIC=ON || die "laszip configure"
cmake --build . -- -j2 || die "laszip build"
cp -r ../include . && cp ../src/*.hpp ./include/laszip
cd ../ci-support && conan export-pkg . $CS -f || die "laszip conan export-pkg"

echo "=== libLAS ==="; date '+%H:%M:%S'
cd /las/libLAS || die "cd libLAS"
rm -rf build-android-$ABI && mkdir build-android-$ABI && cd build-android-$ABI
cmake .. -G "Unix Makefiles" $COMMON -DANDROID_NDK=$ANDROID_NDK -DCMAKE_CXX_FLAGS="-fPIC -fexceptions -frtti -std=c++11" || die "liblas configure"
cmake --build . --target las las_c -- -j2 || die "liblas build"
cp -r ../include .
find . -name "liblas*.so" -exec file {} \;
cd ../ci-support && conan export-pkg . $CS -f || die "liblas conan export-pkg"

echo "=== libLAS AAR ==="; date '+%H:%M:%S'
./gradlew --no-daemon assemble || die "liblas aar assemble"
ls -l build/outputs/aar/
./gradlew --no-daemon tasks --all 2>/dev/null | grep -i "ToMavenLocal" 
echo "LAS BUILD OK"
