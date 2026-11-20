#!/usr/bin/env python3
"""Make libLAS (LiDAR .las/.laz point clouds) an optional part of the ATAK-CIV
build instead of a hard dependency.

    gradle:  -PwithLas=false     cmake:  -DTAK_WITH_LAS=OFF

Default stays ON, so an unmodified invocation behaves exactly as upstream.
Idempotent: safe to run twice. Originals are kept beside each file as *.orig.
"""
import pathlib, re, shutil, sys
root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/src")
MARK = "TAK_WITH_LAS"

def patch(rel, fn):
    p = root / rel
    s = p.read_text()
    if MARK in s or "withLas" in s:
        print("already patched:", rel); return
    shutil.copy2(p, str(p) + ".orig")
    n = fn(s)
    if n == s: sys.exit("NO CHANGE MADE (upstream moved?): " + rel)
    p.write_text(n); print("patched:", rel)

def must(s, old, new, count=1):
    if s.count(old) < count: sys.exit("anchor missing: " + old[:60])
    return s.replace(old, new)

# 1. top-level engine CMake: option, conditional conan requirement + find_package
def cml(s):
    s = must(s, 'option(BUILD_JNI "Build JNI into the library" ON)',
        'option(BUILD_JNI "Build JNI into the library" ON)\n'
        'option(TAK_WITH_LAS "Build LiDAR .las/.laz point cloud support (needs libLAS)" ON)\n'
        'if(TAK_WITH_LAS)\n    set(TAK_LAS_CONAN_REQ libLAS/1.8.2f)\n'
        '    add_compile_definitions(TAK_WITH_LAS=1)\nelse()\n    set(TAK_LAS_CONAN_REQ)\nendif()')
    s = must(s, "libLAS/1.8.2f\n", "${TAK_LAS_CONAN_REQ}\n", 2)
    s = must(s, "find_package (libLAS)", "if(TAK_WITH_LAS)\n    find_package (libLAS)\nendif()")
    return s
patch("takkernel/engine/CMakeLists.txt", cml)

# 2. source lists
def common(s):
    s = must(s, "set(takengine_COMMON_INCS",
        "if(TAK_WITH_LAS)\n"
        "    set(TAK_LAS_FORMAT_SRCS ${SRC_DIR}/formats/las/LAS.cpp)\n"
        "    set(TAK_LAS_MODEL_SRCS ${SRC_DIR}/model/LASSceneInfoSpi.cpp ${SRC_DIR}/model/LASSceneSpi.cpp)\n"
        "else()\n    set(TAK_LAS_FORMAT_SRCS)\n    set(TAK_LAS_MODEL_SRCS)\nendif()\n\n"
        "set(takengine_COMMON_INCS")
    s = must(s, "    ${SRC_DIR}/formats/las/LAS.cpp\n", "    ${TAK_LAS_FORMAT_SRCS}\n")
    s = must(s, "    ${SRC_DIR}/model/LASSceneInfoSpi.cpp\n    ${SRC_DIR}/model/LASSceneSpi.cpp\n",
                "    ${TAK_LAS_MODEL_SRCS}\n")
    return s
patch("takkernel/engine/src/main/cpp/cmake/CommonSources.cmake", common)

# 3. android link line
def android(s):
    s = must(s, "    las\n    las_c\n", "    ${TAK_LAS_LIBS}\n")
    return ("if(TAK_WITH_LAS)\n    set(TAK_LAS_LIBS las las_c)\nelse()\n    set(TAK_LAS_LIBS)\nendif()\n\n" + s)
patch("takkernel/engine/src/main/cpp/cmake/AndroidSources.cmake", android)

# 4. JNI registration: guard every statement that touches the LAS SPIs
def jni(s):
    # Sentinels, not literal #endif, when merging adjacent guards: the file
    # already has "#if C3DT_ENABLED ... #endif" blocks right beside these lines.
    out = []
    for line in s.split("\n"):
        hit = ("LASScene" in line or re.search(r"(->|::|^\s*)las(info|scene)spi\b", line)) \
              and "std::shared_ptr" not in line.split("=")[0]
        out += ["@@B", line, "@@E"] if hit else [line]
    return ("\n".join(out).replace("@@E\n@@B\n", "")
            .replace("@@B", "#ifdef TAK_WITH_LAS").replace("@@E", "#endif // TAK_WITH_LAS"))
patch("takkernel/engine/src/main/jni/jsceneinfofactory.cpp", jni)

# 5. gradle: pass the switch down, and only ask Maven for the AAR when it is on
G = "(project.findProperty('withLas') ?: 'true').toString() != 'false'"
def eng(s):
    s = must(s, '"-DCONAN_COMMAND=${conanPath}"',
        '"-DCONAN_COMMAND=${conanPath}", "-DTAK_WITH_LAS=${(' + G + ') ? \'ON\' : \'OFF\'}"')
    s = must(s, '        api("gov.tak.thirdparty:libLAS:${libLasVersion}@aar")',
        '        if (' + G + ') {\n            api("gov.tak.thirdparty:libLAS:${libLasVersion}@aar")\n        }')
    return s
patch("takkernel/engine/build.gradle", eng)
patch("takkernel/aarbundle/build.gradle", lambda s: must(s,
    '        api("gov.tak.thirdparty:libLAS:${libLasVersion}@aar")',
    '        if (' + G + ') {\n            api("gov.tak.thirdparty:libLAS:${libLasVersion}@aar")\n        }'))
