#!/bin/bash
# Final stage: conan-package cesium-native + draco, then assemble the APK.
# VARIANT=nolas  -> -PwithLas=false (the optional-libLAS patch)
# VARIANT=full   -> upstream behaviour, libLAS linked
set -u
die() { echo "FINAL FAILED AT: $*"; exit 1; }
VARIANT=${VARIANT:-nolas}
S="-s os=Android -s os.api_level=21 -s arch=armv7 -s compiler=gcc -s compiler.version=8 -s compiler.libcxx=libstdc++ -s build_type=Release"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

if ! conan search cesium-native 2>/dev/null | grep -q 0.40.1; then
  ( cd /src/cesium-native && CESIUM_NATIVE_REF=0.40.1 conan export-pkg . $S -f ) || die "cesium conan export-pkg"
fi
if ! conan search draco 2>/dev/null | grep -q 1.5.7; then
  export DRACO_PREFIX=$(ls -d /src/cesium-native/build/android-armeabi-v7a/ezvcpkg/*/installed/arm-neon-android | head -1)
  echo "DRACO_PREFIX=$DRACO_PREFIX"
  ( cd /recipes/draco && conan export-pkg . $S -f ) || die "draco conan export-pkg"
fi
conan search | tail -9

cd /src/atak || die "cd atak"
cat > local.properties <<EOF
sdk.dir=/opt/android-sdk
ndk.dir=/opt/android-sdk/ndk/25.1.8937393
cmake.dir=/las/cmake324
ndkAbiFilter=armeabi-v7a
EOF
FLAG=""; [ "$VARIANT" = nolas ] && FLAG="-PwithLas=false"
echo "=== gradle assembleCivDebug ($VARIANT) ==="; date '+%H:%M:%S'
./gradlew --no-daemon -PndkAbiFilter=armeabi-v7a $FLAG assembleCivDebug || die "gradle assembleCivDebug ($VARIANT)"
date '+%H:%M:%S'
mkdir -p /out
APK=$(find . -name '*.apk' -newermt '-3 hours' | head -1)
[ -n "$APK" ] || die "no apk produced"
cp "$APK" /out/atak-civ-5.5.1-armeabi-v7a-$VARIANT.apk && ls -l /out/
echo "FINAL OK ($VARIANT)"
