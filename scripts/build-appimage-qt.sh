#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 shadPS4 Emulator Project
# SPDX-License-Identifier: GPL-2.0-or-later
#
# One-shot Qt AppImage build for atomic/immutable hosts (Bazzite, Kinoite, ...).
#
# It runs the whole build inside a throwaway Ubuntu 24.04 distrobox that mirrors
# the CI environment, then drops Shadps4-qt.AppImage in the repo root. That
# AppImage runs on the host directly.
#
# Usage:
#   scripts/build-appimage-qt.sh            # create box (if needed), build, package
#   scripts/build-appimage-qt.sh --clean    # also delete the box afterwards
#   scripts/build-appimage-qt.sh --inside   # (internal) run the build; already in box

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOX="shadps4-build"
# 25.04 ships Qt 6.8 (LTS) with glibc 2.41. CI's 24.04 has Qt 6.4.2, whose xcb/
# wayland QPA crashes in QXcbConnection::initializeScreens on current Fedora/KDE
# hosts (Bazzite). 2.41 is still older than Bazzite's 2.43, so the AppImage
# stays portable.
IMAGE="docker.io/library/ubuntu:25.04"
JOBS="$(nproc)"

cd "$REPO_ROOT"

if [[ "${1:-}" != "--inside" ]]; then
    # ----------------------------- host side -----------------------------
    echo ">> Fetching submodules (shallow)..."
    git submodule update --init --recursive --depth 1 \
        externals/{zlib-ng,sdl3,fmt,vulkan-headers,vma,glslang,robin-map,xbyak,magic_enum,toml11,zydis,sirit,xxhash,tracy,ext-boost,date,ffmpeg-core,half,dear_imgui,pugixml,discord-rpc,LibAtrac9,libpng,ext-libusb,epoll-shim,hwinfo,ext-wepoll}

    if ! distrobox list --no-color 2>/dev/null | grep -q "\b${BOX}\b"; then
        echo ">> Creating distrobox '${BOX}' (${IMAGE})..."
        distrobox create --name "$BOX" --image "$IMAGE" --yes
    fi

    echo ">> Building inside '${BOX}'..."
    distrobox enter --name "$BOX" -- bash "$REPO_ROOT/scripts/build-appimage-qt.sh" --inside

    if [[ "${1:-}" == "--clean" ]]; then
        echo ">> Removing distrobox '${BOX}'..."
        distrobox rm --force "$BOX"
    fi

    echo ">> Done: $REPO_ROOT/Shadps4-qt.AppImage"
    exit 0
fi

# --------------------------- container side ---------------------------
export DEBIAN_FRONTEND=noninteractive
export APPIMAGE_EXTRACT_AND_RUN=1          # no FUSE inside the container
export GITHUB_WORKSPACE="$REPO_ROOT"       # consumed by .github/linux-appimage-qt.sh

echo ">> Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    build-essential gcc-14 g++-14 cmake ninja-build mold wget file ca-certificates git \
    qt6-base-dev qt6-tools-dev qt6-tools-dev-tools qt6-multimedia-dev qt6-wayland libssl-dev \
    libx11-dev libxext-dev libxcursor-dev libxi-dev libxrandr-dev libxinerama-dev libxfixes-dev \
    libwayland-dev libdecor-0-dev \
    libxkbcommon-dev libglfw3-dev libgl-dev libegl-dev libgles-dev \
    libasound2-dev libpulse-dev libopenal-dev libudev-dev libfuse2

echo ">> Configuring..."
cmake --fresh -S "$REPO_ROOT" -B "$REPO_ROOT/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=gcc-14 -DCMAKE_CXX_COMPILER=g++-14 \
    -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=mold" \
    -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=mold" \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE=ON \
    -DENABLE_QT_GUI=ON -DENABLE_UPDATER=ON

echo ">> Compiling (-j${JOBS})..."
cmake --build "$REPO_ROOT/build" --config Release --parallel "$JOBS"

echo ">> Packaging AppImage..."
cd "$REPO_ROOT"
# .github/linux-appimage-qt.sh has no `set -e` and does not clean up after itself;
# wipe stale state so a re-run after a failed attempt starts fresh.
rm -rf AppDir linuxdeploy-x86_64.AppImage linuxdeploy-plugin-qt-x86_64.AppImage \
    linuxdeploy-plugin-checkrt-x86_64.sh Shadps4-qt.AppImage
./.github/linux-appimage-qt.sh

ls -lh "$REPO_ROOT/Shadps4-qt.AppImage"
