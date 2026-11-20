#!/bin/bash
# Assemble the APK in the build container. VARIANT=full|nolas
set -u
V=${VARIANT:-full}
B=${ATAK_BUILD_ROOT:-$HOME/atak-build}
OUT=$B/final-$V.log
: > "$OUT"
docker run --rm --cpus=3 -e VARIANT="$V" \
  -v $B/src:/src \
  -v $B/recipes:/recipes \
  -v $B/out:/out \
  -v $B/las-build:/las \
  -v $B/conan-home:/root/.conan \
  -v $B/gradle-home:/root/.gradle \
  -v $B/m2:/root/.m2 \
  -v $B/final.sh:/final.sh:ro \
  atak-build:5.5.1 bash /final.sh >> "$OUT" 2>&1
echo "FINAL EXIT: $?" >> "$OUT"
