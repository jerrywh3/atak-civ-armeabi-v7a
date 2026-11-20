#!/bin/bash
# Stage 8c: publish the takthirdparty AAR in a SEPARATE gradle invocation.
# Gradle 8 refuses a graph where publish consumes createAndroidSourceSet's
# output without declaring the dependency. Splitting assemble and publish into
# two invocations keeps both tasks out of one graph, so the check does not fire.
set -u
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
cd /src/takthirdparty/ci-support || exit 90
echo "=== AAR present? ==="; ls -l build/outputs/aar/
echo "=== publish only ==="
./gradlew --no-daemon publishTtpRuntimeAndroidPublicationToMavenLocal
echo "  publish exit: $?"
echo "=== .m2 contents ==="
find /root/.m2/repository/gov -type f | sed 's|/root/.m2/repository/||' | sort

echo; echo "=== re-attempt the APK ==="; date '+%H:%M:%S'
cd /src/atak || exit 90
./gradlew --no-daemon -PndkAbiFilter=armeabi-v7a assembleCivDebug
rc=$?
echo "=== gradle exit: $rc ==="
find . -name '*.apk' -newermt '-12 hours' -exec ls -lh {} \; 2>/dev/null
[ "$rc" = "0" ] && echo "BUILD SCRIPT COMPLETED OK" || echo "FAILED AT: gradle assembleCivDebug (stage 8c)"
exit $rc
