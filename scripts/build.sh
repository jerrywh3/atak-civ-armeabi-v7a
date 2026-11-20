#!/bin/bash
# ATAK-CIV 5.5.1 -> armeabi-v7a, run INSIDE the atak-build container.
# Stages are announced so a failure is localised rather than buried.
set -u
cd /src || exit 90

stage() { echo; echo "=================== STAGE: $* ==================="; date '+%H:%M:%S'; }
die()   { echo "!!! FAILED AT: $*"; exit 1; }

stage "1/8 git-lfs: fetch the 152 pointer objects (depends/ tarballs live here)"
git lfs install --local || die "lfs install"
git lfs pull || die "lfs pull"
for f in depends/gdal-2.4.4-mod.tar.gz depends/assimp-4.0.1-mod.tar.gz; do
  sz=$(stat -c%s "$f")
  echo "  $f = $sz bytes"
  [ "$sz" -gt 100000 ] || die "lfs pull left $f as a pointer ($sz bytes)"
done

stage "2/8 STLSoft 1.9 (BUILDING.md requires it under takengine/thirdparty/stlsoft)"
if [ ! -d takengine/thirdparty/stlsoft ]; then
  git clone --depth 1 https://github.com/synesissoftware/STLSoft-1.9.git \
      takengine/thirdparty/stlsoft || die "stlsoft clone"
fi
ls takengine/thirdparty/stlsoft >/dev/null || die "stlsoft missing"

stage "3/8 unpack the modified GDAL 2.4.4 and ASSIMP 4.0.1 to the tree root"
for pkg in gdal-2.4.4-mod assimp-4.0.1-mod; do
  if [ ! -f "${pkg}.tar" ]; then
    cp "depends/${pkg}.tar.gz" . || die "copy ${pkg}"
    gzip -df "${pkg}.tar.gz"    || die "gunzip ${pkg}"
  fi
  tar xf "${pkg}.tar" || die "untar ${pkg}"
done
ls -d gdal assimp 2>/dev/null || echo "  (note: check what the tarballs unpacked to)"

stage "4/8 conan profile (BUILDING.md: compiler version 8 for package resolution)"
conan profile new default --detect --force || die "conan profile new"
conan profile update settings.compiler.version=8 default || die "conan profile update"
conan profile show default | head -12

stage "5/8 takthirdparty: build the native stack for armeabi-v7a ONLY"
# arm64/x86 are deliberately skipped - the target phone is 32-bit, and each
# extra architecture is another full GDAL/ASSIMP/spatialite compile.
cd takthirdparty || die "cd takthirdparty"
# NDK choice here is squeezed between two incompatible requirements:
#   * the takthirdparty makefiles reference the UNIFIED SYSROOT layout
#     (toolchains/llvm/prebuilt/<host>/sysroot/...), introduced in r19 - so
#     the documented r12b cannot build its own project;
#   * CMake 3.14 (also pinned by BUILDING.md) drives Android through the
#     LEGACY platforms/android-NN layout, deleted in r22 - so r25b fails
#     assimp's configure with "platforms/android-21 does not exist".
# r19..r21 is the only window satisfying both. r21e is the newest of those.
# The APP module (stage 8) still uses r25b, which its gradle pins.
export ANDROID_NDK=/opt/android-ndk-r21e
export ANDROID_NDK_HOME=/opt/android-ndk-r21e
make TARGET=android-armeabi-v7a GDAL_USE_KDU=no \
     build_spatialite build_gdal build_commoncommo build_assimp \
  || die "takthirdparty make (this is the stage most likely to rot)"
ls -d builds/android-armeabi-v7a-release || die "no v7a build output"

stage "6/8 publish the v7a artifacts to the local conan repo"
ln -sfn builds/android-armeabi-v7a-release android-armeabi-v7a-release
cd ci-support || die "cd ci-support"
conan export-pkg . -s arch=armv7 -s os=Android -s os.api_level=29 -f \
  || die "conan export-pkg armv7"
cd /src || exit 90

stage "7/8 tinygltf + tinygltfloader conan packages"
for pkg in tinygltf-2.4.1-mod tinygltfloader-0.9.5-mod; do
  if [ ! -f "${pkg}.tar" ]; then
    cp "depends/${pkg}.tar.gz" . 2>/dev/null && gzip -df "${pkg}.tar.gz"
  fi
  [ -f "${pkg}.tar" ] && tar xf "${pkg}.tar"
done
echo "  (tinygltf conan export handled by the gradle build where applicable)"

stage "8/8 assemble the APK, narrowed to armeabi-v7a"
cd atak || die "cd atak"
cat > local.properties <<EOF
sdk.dir=/opt/android-sdk
ndk.dir=/opt/android-sdk/ndk/25.1.8937393
cmake.dir=/opt/cmake
ndkAbiFilter=armeabi-v7a
EOF
echo "local.properties:"; sed 's/^/  /' local.properties
./gradlew --no-daemon -PndkAbiFilter=armeabi-v7a assembleCivDebug \
  || die "gradle assembleCivDebug"

stage "DONE - locating the APK"
find . -name '*.apk' -newermt '-6 hours' -exec ls -lh {} \;
echo "BUILD SCRIPT COMPLETED OK"
