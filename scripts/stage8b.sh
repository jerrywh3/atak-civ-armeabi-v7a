#!/bin/bash
# Stage 8b: publish the Maven artifacts the APK needs that CAN be built from
# this repo, then re-attempt the APK so the remaining gap is exact.
#
# BUILDING.md documents the conan side (export-pkg) but never mentions that
# :ATAK:app also resolves three MAVEN artifacts in group gov.tak.thirdparty.
# Upstream publishes those from private CI to artifacts.tak.gov, which
# redirects anonymous callers to an auth portal. Two of the three have build
# scripts in this repo; the third (libLAS) does not.
set -u
cd /src || exit 90
stage() { echo; echo "=================== STAGE: $* ==================="; date '+%H:%M:%S'; }

export ANDROID_NDK=/opt/android-ndk-r21e
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

stage "8b-1 point the AAR's JAR source at the v7a build"
# artifactAssembly.gradle takes the .so files per-ABI but takes gdal.jar /
# jassimp.jar / jcommoncommo.jar ONLY from ../android-arm64-v8a-release/java.
# Building a single ABI therefore yields an AAR with no Java bindings. Give it
# a java/ directory without a lib/ directory, so no arm64 .so is ever copied.
cd takthirdparty || exit 90
ln -sfn builds/android-armeabi-v7a-release android-armeabi-v7a-release
mkdir -p android-arm64-v8a-release
ln -sfn ../builds/android-armeabi-v7a-release/java android-arm64-v8a-release/java
ls -l android-arm64-v8a-release/java/ | head

stage "8b-2 build and publish gov.tak.thirdparty:takthirdparty:4.2.4 (AAR)"
cd ci-support || exit 90
./gradlew --no-daemon assembleRelease publishTtpRuntimeAndroidPublicationToMavenLocal
echo "  ci-support exit: $?"

stage "8b-3 publish gov.tak.thirdparty:apache-commons-lang-slim:1.0.0"
cd /src/takengine/thirdparty/apache-commons-lang-slim || exit 90
./gradlew --no-daemon publishApacheCommonsLangSlimPublicationToMavenLocal
echo "  commons-lang-slim exit: $?"

stage "8b-4 what is in the local maven repo now"
find /root/.m2/repository/gov -name "*.aar" -o -name "*.jar" -o -name "*.pom" 2>/dev/null | sed 's|/root/.m2/repository/||' | sort

stage "8b-5 re-attempt the APK"
cd /src/atak || exit 90
cat > local.properties <<EOF
sdk.dir=/opt/android-sdk
ndk.dir=/opt/android-sdk/ndk/25.1.8937393
cmake.dir=/opt/cmake
ndkAbiFilter=armeabi-v7a
EOF
./gradlew --no-daemon -PndkAbiFilter=armeabi-v7a assembleCivDebug
rc=$?
echo "=== gradle exit: $rc ==="
find . -name '*.apk' -newermt '-12 hours' -exec ls -lh {} \; 2>/dev/null
[ "$rc" = "0" ] && echo "BUILD SCRIPT COMPLETED OK" || echo "FAILED AT: gradle assembleCivDebug (stage 8b)"
exit $rc
