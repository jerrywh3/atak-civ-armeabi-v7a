# Build environment for ATAK-CIV 5.5.1 targeting armeabi-v7a.
# Pins match BUILDING.md: NDK r12b for the third-party native stack,
# CMake 3.14.7 for libtakengine, Conan 1.x for package management.
# Debian bookworm is chosen deliberately: it still carries Python 3.11,
# which Conan 1.x needs (trixie's 3.13 breaks it), and unlike bullseye it
# is still served by the mirrors.
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk

RUN apt-get update && apt-get install -y --no-install-recommends \
      openjdk-17-jdk-headless \
      git git-lfs curl unzip zip ca-certificates \
      build-essential autoconf automake libtool pkg-config \
      ninja-build swig patch file \
      python3 python3-pip python3-setuptools python3-venv \
      ant \
    && rm -rf /var/lib/apt/lists/*

# Conan 1.x - BUILDING.md uses `conan profile update`, which is 1.x syntax.
# Installed into a venv because bookworm enforces PEP 668 on the system python.
RUN python3 -m venv /opt/conan-venv \
    && /opt/conan-venv/bin/pip install --no-cache-dir "conan==1.59.0"
ENV PATH="/opt/conan-venv/bin:${PATH}"

# CMake 3.14.7 exactly, as BUILDING.md requires for libtakengine.
RUN curl -fsSL -o /tmp/cmake.tar.gz \
      https://cmake.org/files/v3.14/cmake-3.14.7-Linux-x86_64.tar.gz \
    && mkdir -p /opt/cmake \
    && tar -xzf /tmp/cmake.tar.gz -C /opt/cmake --strip-components=1 \
    && rm /tmp/cmake.tar.gz
ENV PATH="/opt/cmake/bin:${PATH}"

# NDK r12b - the third-party stack is compiled with this per BUILDING.md.
RUN curl -fsSL -o /tmp/ndk12.zip \
      https://dl.google.com/android/repository/android-ndk-r12b-linux-x86_64.zip \
    && unzip -q /tmp/ndk12.zip -d /opt \
    && rm /tmp/ndk12.zip
ENV ANDROID_NDK_R12B=/opt/android-ndk-r12b

# Android SDK command-line tools, then platform/build-tools and NDK r25b
# (which the app module's gradle pins) via sdkmanager.
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools \
    && curl -fsSL -o /tmp/cmdline.zip \
       https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
    && unzip -q /tmp/cmdline.zip -d ${ANDROID_SDK_ROOT}/cmdline-tools \
    && mv ${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest \
    && rm /tmp/cmdline.zip
ENV PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}"

RUN yes | sdkmanager --licenses > /dev/null 2>&1 || true
RUN sdkmanager --install \
      "platform-tools" \
      "platforms;android-35" \
      "build-tools;35.0.0" \
      "ndk;25.1.8937393" \
      > /dev/null

ENV ANDROID_NDK_HOME=${ANDROID_SDK_ROOT}/ndk/25.1.8937393
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

WORKDIR /src
CMD ["/bin/bash"]

# Tools the takthirdparty makefiles invoke but BUILDING.md never mentions.
# Found by scanning takthirdparty/mk/*.mk: dos2unix (22 call sites),
# sqlite3 (16), plus a bare `python`. Appended as a separate layer so the
# NDK/SDK layers above stay cached.
RUN apt-get update && apt-get install -y --no-install-recommends \
      dos2unix sqlite3 libsqlite3-dev python-is-python3 perl \
      gperf bison flex texinfo rsync yasm nasm \
    && rm -rf /var/lib/apt/lists/*

# tclsh is required by SQLCipher's own configure to generate the amalgamation
# (tool/cktclsh.sh). It is not referenced by takthirdparty's makefiles, so a
# scan of those misses it. Neighbours added pre-emptively to cut iterations.
RUN apt-get update && apt-get install -y --no-install-recommends \
      tcl tcl-dev libtool-bin gettext help2man autoconf-archive \
    && rm -rf /var/lib/apt/lists/*

# Rootless Docker: the container's root maps to the host user, so tar cannot
# chown extracted files to the uids baked into the upstream tarballs and
# exits non-zero (protobuf-3.21.0 trips this). GNU tar honours TAR_OPTIONS.
ENV TAR_OPTIONS=--no-same-owner

# NDK r21e - the only window that satisfies BOTH constraints:
#   * takthirdparty makefiles need the UNIFIED SYSROOT layout -> r19 or later
#   * CMake 3.14 (pinned by BUILDING.md) drives Android via the LEGACY
#     platforms/android-NN layout, which NDK r22 deleted -> r21 or earlier
# r25b satisfies the first and fails the second (assimp's CMake configure).
RUN curl -fsSL -o /tmp/ndk21.zip \
      https://dl.google.com/android/repository/android-ndk-r21e-linux-x86_64.zip \
    && unzip -q /tmp/ndk21.zip -d /opt \
    && rm /tmp/ndk21.zip
ENV ANDROID_NDK_R21E=/opt/android-ndk-r21e
