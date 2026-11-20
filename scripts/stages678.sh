#!/bin/bash
# Stages 6-8: publish the v7a native artifacts to conan, then assemble the APK.
set -u
cd /src || exit 90
stage() { echo; echo "=================== STAGE: $* ==================="; date '+%H:%M:%S'; }
die()   { echo "!!! FAILED AT: $*"; exit 1; }

export ANDROID_NDK=/opt/android-ndk-r21e
export ANDROID_NDK_HOME=/opt/android-ndk-r21e

stage "6/8 publish the v7a artifacts to the local conan repo"
cd takthirdparty || die "cd takthirdparty"
ln -sfn builds/android-armeabi-v7a-release android-armeabi-v7a-release
cd ci-support || die "cd ci-support"
conan export-pkg . -s arch=armv7 -s os=Android -s os.api_level=29 -f \
  || die "conan export-pkg armv7"
cd /src || exit 90

stage "7/8 tinygltf + tinygltfloader conan packages"
# BUILDING.md puts these under takengine/thirdparty and exports each as a
# conan package; libtakengine's conanfile resolves them by name.
for pkg in tinygltf-2.4.1-mod tinygltfloader-0.9.5-mod; do
  if [ ! -f "takengine/thirdparty/${pkg}.tar" ]; then
    cp "depends/${pkg}.tar.gz" takengine/thirdparty/ || die "copy ${pkg}"
    ( cd takengine/thirdparty && gzip -df "${pkg}.tar.gz" ) || die "gunzip ${pkg}"
  fi
  ( cd takengine/thirdparty && tar xf "${pkg}.tar" ) || die "untar ${pkg}"
done
for d in tinygltf tinygltfloader; do
  ( cd "takengine/thirdparty/$d" && conan export-pkg . -f ) || die "conan export-pkg $d"
done

stage "8/8 assemble the APK, narrowed to armeabi-v7a"
cd atak || die "cd atak"
# The app module's own gradle pins NDK r25b; only takthirdparty needed r21e.
# Debug signing falls back to the repo's bundled android_keystore, so no key
# of our own is needed for assembleCivDebug.
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
find . -name '*.apk' -newermt '-12 hours' -exec ls -lh {} \;
echo "BUILD SCRIPT COMPLETED OK"
