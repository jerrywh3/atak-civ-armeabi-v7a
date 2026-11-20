#!/bin/bash
# Conan packages for the engine, into a PERSISTENT conan home (the earlier
# exports went into a --rm container's ~/.conan and were lost with it).
# Settings mirror exactly what takkernel/engine/CMakeLists.txt asks conan for.
set -u
S="-s os=Android -s os.api_level=21 -s arch=armv7 -s compiler=gcc -s compiler.version=8 -s compiler.libcxx=libstdc++ -s build_type=Release"
conan profile new default --detect --force >/dev/null 2>&1
conan profile update settings.compiler.version=8 default
( cd /recipes/khronos && conan export-pkg . -f ) || { echo "PREP FAILED AT: khronos"; exit 1; }
( cd /src/takthirdparty/ci-support && conan export-pkg . $S -f ) || { echo "PREP FAILED AT: ttp-dist"; exit 1; }
for d in tinygltf tinygltfloader; do
  ( cd /src/takengine/thirdparty/$d && conan export-pkg . -f ) || { echo "PREP FAILED AT: $d"; exit 1; }
done
conan search 2>&1 | tail -8
echo "PREP OK"
