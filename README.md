# ATAK-CIV 5.5.1 for 32-bit Android (`armeabi-v7a`)

A reproducible recipe that builds **ATAK-CIV 5.5.1 from source into a complete
`armeabi-v7a` APK**, for phones whose userspace is 32-bit and which therefore cannot run
the official arm64-only build.

It is a Docker image plus a handful of scripts, two small conan recipes, one patch and one
missing asset. It produces the APK; it does not contain one. **Please read
[Licensing](#licensing-why-no-apk-is-published-here) before asking for a binary.**

Verified on a **Cat S42** (`S42G`, MediaTek MT6761 / Helio A20, Android 12, `uname -m` =
`armv7l`, `ro.product.cpu.abilist64` empty). ATAK installs, launches, loads its plugins and
reaches the TAK Device Setup screen with the map engine reporting position, callsign,
elevation and heading.

---

## Status: what is tested and what is not

| | |
|---|---|
| Builds end to end from a clean tree | **yes**, reproduced twice (with and without LiDAR) |
| `aapt` reports `native-code: 'armeabi-v7a'` only | **yes** |
| `libtakengine.so` is ELF 32-bit ARM | **yes** |
| Installs, launches, survives first run | **yes**, on the S42 — default (LiDAR) variant |
| Plugins load; map engine reports position | **yes** |
| Sustained map use, GPS fix, TAK server connection | **not tested** |
| Any device other than the Cat S42 | **not tested** |
| `arm64-v8a` or `x86` | not attempted — the point here was v7a |

The engine was the real question: `libtakengine` is the one piece of ATAK that nobody
appears to have exercised on 32-bit in years. It compiled under `-Werror` with **no source
changes at all**. Everything that had to be worked around was build plumbing.

---

## The short version of what is wrong with the documented build

`BUILDING.md` in the ATAK repo is accurate about intent and wrong or silent about most of
the specifics. The findings below are the actual content of this repository; the scripts
are just those findings made executable.

### 1. The documented NDK cannot build the project

`BUILDING.md` pins **NDK r12b**. The `takthirdparty` makefiles reference the *unified
sysroot* layout (`toolchains/llvm/prebuilt/<host>/sysroot/...`), which **did not exist until
r19**. So the documented NDK cannot build the project's own third-party stack.

The other end is pinned too: `BUILDING.md` also pins **CMake 3.14.7**, whose built-in
Android support drives the *legacy* `platforms/android-NN` layout, which **r22 deleted**.

That leaves **r19–r21 as the only window** satisfying both. This recipe uses **r21e**, the
newest of them. The app module itself uses **r25b**, which its own gradle pins — so two
NDKs are required and the image installs both.

### 2. assimp's link failure is a lookup bug, not an architecture problem

Building assimp fails with:

```
/usr/bin/ld: unrecognised emulation mode: armelf_linux_eabi
```

which reads like a toolchain mismatch. It is not. CMake 3.14 implements
`-DCMAKE_SYSTEM_NAME=Android` by globbing
`<ndk>/{build/core/,}toolchains/*-[0-9].[0-9]/config.mk` to learn the gcc toolchain name.
r21e no longer ships those `config.mk` files, so the name resolves **empty**, clang is
handed `--gcc-toolchain=<ndk>/toolchains//prebuilt/linux-x86_64` — a path that does not
exist — and falls back to the **host** binutils. Compiling succeeded; only linking failed.

Fix: bypass CMake's built-in Android support for this one target and use the NDK's own
`android.toolchain.cmake`, which is version-matched to r21e. See `scripts/assimp-fix.sh`.

### 3. No single CMake builds ATAK

Three are needed, and this is not written down anywhere:

| Component | CMake |
|---|---|
| `takthirdparty`, assimp | 3.14.7 (as documented) |
| `takkernel/engine` | **3.21 or newer** — it fails the documented 3.14.7 outright |
| cesium-native | 3.27.9 |

`BUILDING.md` says "CMake 3.14.7 or later … other versions are not guaranteed", which
reads as *use 3.14.7*. Set `cmake.dir` in `local.properties` to the newer one for the app
build; the Android gradle plugin will otherwise pick the wrong one off `PATH`.

### 4. Three Maven artifacts are not in the repository and not mentioned

`:ATAK:app` resolves three artifacts in group `gov.tak.thirdparty` that upstream publishes
from private CI to `artifacts.tak.gov`, which redirects anonymous callers to an auth
portal:

- `takthirdparty:4.2.4` — buildable, from `takthirdparty/ci-support` (AAR)
- `apache-commons-lang-slim:1.0.0` — buildable, from `takengine/thirdparty/`
- `libLAS:1.8.2f` — see below

All three are published to `mavenLocal()` by the scripts here.

### 5. libLAS **is** buildable — its build system is inside the tarball

This one cost the most time and I got it wrong first. The ATAK repo has no libLAS build
script, so it looks like a hard stop. **The scripts are inside
`depends/libLAS-1.8.2-mod.tar.gz` itself** — each dependency tarball carries its own
`.gitlab-ci.yml` and `ci-support/` directory with the conan recipe and the AAR gradle
project. TAK's own CI has a `liblas_android_armeabi` job: they build it 32-bit routinely.

`scripts/las.sh` replays that job for LASzip and then libLAS, using the same CMake (3.24.3)
and NDK (r25b) their CI names. Note the `las` and `las_c` targets need **no external
Boost** — the resulting CMake cache has no Boost entry at all. Only the apps and tests do,
and those are not built.

### 6. A single-ABI build silently produces an AAR with no Java bindings

`artifactAssembly.gradle` takes `.so` files per ABI but takes `gdal.jar`, `jassimp.jar` and
`jcommoncommo.jar` **only** from `../android-arm64-v8a-release/java`. Build one ABI and
that path does not exist, so the AAR ships without Java bindings and the app fails later
with confusing `NoClassDefFoundError`s.

Workaround in `scripts/stage8b.sh`: create `android-arm64-v8a-release/` containing *only* a
`java` symlink to the v7a build's `java` directory — a `java/` with no `lib/` beside it, so
no arm64 `.so` can ever be picked up.

### 7. Gradle 8 refuses to assemble and publish in one invocation

Publishing the takthirdparty AAR fails validation: the publish task consumes
`createAndroidSourceSet`'s output without declaring the dependency. Run `assembleRelease`
and `publish…ToMavenLocal` as **two separate gradle invocations** and the check does not
fire. (`scripts/stage8b.sh` then `scripts/stage8c.sh`.)

### 8. Conan details that are not in the docs

- `BUILDING.md` publishes with `-s os.api_level=29`; the engine resolves at
  **`os.api_level=21`**. Use 21.
- Two packages have no public recipe at all and are stood in for here:
  - **`khronos/1.0`** — consumed only as `${khronos_INCLUDE_DIRS}` for `<GLES2/gl2.h>` and
    friends, which the NDK sysroot already provides. An **empty header-only package** is
    enough (`recipes/khronos/`).
  - **`draco/1.5.7`** — cesium-native's vcpkg tree has already built it. `recipes/draco/`
    re-homes that. Its **headers are required**: tinygltf includes
    `<draco/compression/decode.h>`, so `include/draco/` must keep its directory level.
- Run conan inside a **persistent** conan home. Exports into a `docker run --rm`
  container's `~/.conan` vanish with the container, and the next stage re-resolves from
  the network and fails.
- **After changing any conan package, delete `takkernel/engine/.cxx`.** The generated
  `Find<pkg>.cmake` files and include paths are cached there, and a rebuild silently reuses
  the stale ones. This presents as a missing `-I` for a package that is demonstrably
  correct.

### 9. Every APK built from the public source crashes at the end of first run

This one is not about 32-bit and will hit anyone who builds ATAK-CIV 5.5.1 from source on
any ABI.

```
java.lang.NullPointerException: inStream parameter is null
  at java.util.Properties.load(Properties.java:406)
  at com.atakmap.android.update.AppVersionUpgrade.onUpgrade(AppVersionUpgrade.java:189)
  at com.atakmap.app.ATAKActivity.postInitialization(ATAKActivity.java:566)
```

`AppVersionUpgrade.onUpgrade()` runs once, right after the first-run wizard, and opens
`assets/wms/cleanup.properties`. **There is no `assets/wms/` anywhere in the source tree.**
`FileSystemUtils.getInputStreamFromAsset()` swallows the `IOException` and returns `null`
rather than throwing, and the caller catches only `IOException` — so `Properties.load(null)`
throws an NPE that nothing catches, and ATAK dies. The tak.gov binaries must ship the
asset; the source drop does not.

The fix is the asset, not the code. That file maps a legacy WMS pointer filename to the
sha256 of the last copy ATAK shipped, so an untouched one can be deleted on upgrade. A
fresh install has nothing to clean, so an **empty table is the correct content** and
upstream behaviour is preserved exactly. Copy `assets/wms/cleanup.properties` from this
repo to `atak/ATAK/app/src/main/assets/wms/cleanup.properties`.

The other four callers of `getInputStreamFromAsset` point at `iconsets`, `dbs` and `menus`,
which are all present.

---

## Optional LiDAR (`patches/0001-optional-libLAS.patch`)

libLAS is the heaviest dependency in the chain and only serves LAS/LAZ point clouds. The
patch makes it a build-time switch rather than a requirement:

```sh
./gradlew -PndkAbiFilter=armeabi-v7a -PwithLas=false assembleCivDebug
```

It adds a `TAK_WITH_LAS` CMake option (**default ON**, so the unpatched behaviour is the
default), guards the LAS format and model sources and the JNI entry points behind it, and
drops the libLAS AAR dependency when the flag is off.

What it actually saves is **the build stage, not the download**. `liblas.so` and
`liblas_c.so` are 1.8 MB uncompressed, about 250 KB of APK — the engine is marginally
*larger* without LAS, so the net difference is small. The reason to use the switch is to
skip the LASzip/libLAS stage of the build entirely, which is the fiddliest part of the
chain.

Verified on the built artifacts: the `-PwithLas=false` APK contains no `liblas.so`, and
`readelf -d` on its `libtakengine.so` shows no `NEEDED` entry for `liblas.so` or
`liblas_c.so`, where the default build has both. **Only the default (LiDAR) variant has
been run on a phone**; the no-LAS variant is verified as built, not as running.

---

## Build order

Everything runs in one Docker image. Rootless Docker is fine (the image sets
`TAR_OPTIONS=--no-same-owner`, which protects against a `protobuf-3.21.0` extraction
failure under rootless).

```sh
# 0. a working directory, with the ATAK source beside the scripts
export ATAK_BUILD_ROOT=$HOME/atak-build
mkdir -p "$ATAK_BUILD_ROOT"/{out,conan-home,gradle-home,m2,las-build}
cd "$ATAK_BUILD_ROOT"
git clone https://github.com/TAK-Product-Center/atak-civ.git src
cp -r /path/to/this/repo/{scripts,recipes,patches,Dockerfile} .
mv scripts/*.sh .            # the scripts expect to sit at the root

# 1. the image (~20 min, mostly NDK and SDK downloads)
docker build -t atak-build:5.5.1 .

# 2. the missing asset, and optionally the LiDAR switch
mkdir -p src/atak/ATAK/app/src/main/assets/wms
cp /path/to/this/repo/assets/wms/cleanup.properties \
   src/atak/ATAK/app/src/main/assets/wms/
python3 patches/apply_las_switch.py src      # only if you want -PwithLas=false

# 3. the native third-party stack (the long one)
docker run --rm --cpus=3 -v "$ATAK_BUILD_ROOT/src":/src \
  -v "$ATAK_BUILD_ROOT/build.sh":/build.sh:ro atak-build:5.5.1 bash /build.sh
docker run --rm --cpus=3 -v "$ATAK_BUILD_ROOT/src":/src \
  -v "$ATAK_BUILD_ROOT/assimp-fix.sh":/f.sh:ro atak-build:5.5.1 bash /f.sh

# 4. LASzip + libLAS   (skip entirely if building -PwithLas=false)
./las-unpack.sh
docker run --rm --cpus=3 -v "$ATAK_BUILD_ROOT/src":/src \
  -v "$ATAK_BUILD_ROOT/las-build":/las -v "$ATAK_BUILD_ROOT/m2":/root/.m2 \
  -v "$ATAK_BUILD_ROOT/conan-home":/root/.conan \
  -v "$ATAK_BUILD_ROOT/las.sh":/las.sh:ro atak-build:5.5.1 bash /las.sh

# 5. cesium-native, then the conan packages, then the Maven artifacts
#    (cesium.sh, conan-prep.sh, stages678.sh, stage8b.sh, stage8c.sh - same
#     pattern, mounting conan-home / gradle-home / m2 so nothing is lost)

# 6. assemble
VARIANT=full ./run-final.sh      # or VARIANT=nolas
ls -l out/
```

`run-final.sh` shows the full mount set the final stage needs; the earlier stages use
subsets of it. Roughly **3.5 hours of compute on 4 cores** for a cold build of one ABI.

Each script announces its stage and prints `FAILED AT: <stage>` on the way out, so a
failure localises instead of being buried in a 7 MB gradle log.

### Installing the result

```sh
adb push atak-civ-5.5.1-armeabi-v7a-full.apk /data/local/tmp/atak.apk
adb shell pm install -r /data/local/tmp/atak.apk
```

Install from `/data/local/tmp`, **not** from `/sdcard`. On Android 12 the latter fails with
an SELinux denial — `system_server` cannot read `u:object_r:fuse:s0` — and the error
message tells you so.

---

## Licensing: why no APK is published here

**Do not redistribute the APK this recipe builds.** It bundles proprietary components that
are licensed for use inside ATAK and not for redistribution by third parties, among them
PAR Government PGSC video libraries (`lib*pgsc*.so`), MrSID (`libltidsdk.so`) and pdfium.
The *recipe* is shareable; the *binary* is not. Build your own.

The APK is signed with the ATAK repository's own public debug keystore
(`O=WinTec Arrowmaker`), so it cannot upgrade, or be upgraded by, a Play Store or tak.gov
install. Generate your own signing key for anything beyond testing — `BUILDING.md`
documents the `takDebugKey*` / `takReleaseKey*` properties.

ATAK-CIV is government-furnished software under its own licence; read `LICENSE.txt` in the
ATAK repository. This repository contains only build scripts, two conan recipes, one patch
and one asset file, and is not affiliated with, endorsed by, or supported by the TAK
Product Center or PAR Government.

---

## If it does not work on your phone

The one hardware requirement is an ABI the APK was built for. Check:

```sh
adb shell getprop ro.product.cpu.abilist
```

If `armeabi-v7a` is in that list, this APK is a candidate. If the device is arm64, you do
not need any of this — use the official build.

Device-specific GPU trouble is the most likely remaining failure, since the renderer is the
part most exposed to driver differences. The S42's PowerVR GE8300 worked without any
coaxing; nothing else has been tried.
