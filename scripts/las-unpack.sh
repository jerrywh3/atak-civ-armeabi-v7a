#!/bin/bash
# Unpack the LASzip and libLAS sources that las.sh builds. Run on the HOST,
# before the las.sh container. Both tarballs are in the ATAK repo's depends/
# directory and both extract a single top-level directory.
#
# Each tarball carries its own .gitlab-ci.yml and ci-support/ - TAK's build
# scripts, conan recipe and AAR gradle project are inside the tarball, not in
# the ATAK repo. That is easy to miss and is why libLAS looks unbuildable.
set -eu
B=${ATAK_BUILD_ROOT:-$HOME/atak-build}
mkdir -p "$B/las-build"
cd "$B/las-build"
tar xzf "$B/src/depends/LASzip-3.4.3-mod.tar.gz"
tar xzf "$B/src/depends/libLAS-1.8.2-mod.tar.gz"
ls -d LASzip libLAS
