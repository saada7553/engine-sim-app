#!/usr/bin/env bash
# Driven by an Xcode "Run Script" phase. Compiles the engine-sim C++ static
# libraries for whichever platform/configuration Xcode is currently building,
# into the matching out-of-tree CMake build folder. Idempotent — repeated
# Xcode builds just re-run incremental cmake builds.
#
# Inputs from the Xcode environment:
#   PLATFORM_NAME   one of: macosx | iphoneos | iphonesimulator
#   CONFIGURATION   one of: Debug  | Release
#   PROJECT_DIR     absolute path to the Xcode project root
#   ARCHS           space-separated list of archs Xcode is targeting

set -euo pipefail

ENGINE_SIM_DIR="${PROJECT_DIR}/physics-simulation/engine-sim"

case "${PLATFORM_NAME}" in
    macosx)
        case "${CONFIGURATION}" in
            Debug)   BUILD_SUBDIR="build-debug";        CMAKE_BUILD_TYPE="Debug"   ;;
            Release) BUILD_SUBDIR="build";              CMAKE_BUILD_TYPE="Release" ;;
            *)       echo "Unhandled CONFIGURATION='${CONFIGURATION}' for macOS" >&2; exit 1 ;;
        esac
        # Mirror Xcode's $ARCHS so the static archive contains the same slices
        # Xcode is producing for the app target (e.g. arm64+x86_64 universal).
        # Release with -march=native is gated off for non-host builds via the
        # CMakeLists; Debug doesn't use march at all.
        CMAKE_PLATFORM_ARGS=(
            "-DCMAKE_OSX_ARCHITECTURES=${ARCHS// /;}"
        )
        ;;
    iphoneos)
        case "${CONFIGURATION}" in
            Debug)   BUILD_SUBDIR="build-ios-debug";    CMAKE_BUILD_TYPE="Debug"   ;;
            Release) BUILD_SUBDIR="build-ios";          CMAKE_BUILD_TYPE="Release" ;;
            *)       echo "Unhandled CONFIGURATION='${CONFIGURATION}' for iOS" >&2; exit 1 ;;
        esac
        CMAKE_PLATFORM_ARGS=(
            "-DCMAKE_SYSTEM_NAME=iOS"
            "-DCMAKE_OSX_SYSROOT=iphoneos"
            "-DCMAKE_OSX_ARCHITECTURES=${ARCHS// /;}"
            "-DCMAKE_OSX_DEPLOYMENT_TARGET=${IPHONEOS_DEPLOYMENT_TARGET:-26.0}"
        )
        ;;
    iphonesimulator)
        case "${CONFIGURATION}" in
            Debug)   BUILD_SUBDIR="build-ios-sim-debug"; CMAKE_BUILD_TYPE="Debug"   ;;
            Release) BUILD_SUBDIR="build-ios-sim";       CMAKE_BUILD_TYPE="Release" ;;
            *)       echo "Unhandled CONFIGURATION='${CONFIGURATION}' for iOS sim" >&2; exit 1 ;;
        esac
        CMAKE_PLATFORM_ARGS=(
            "-DCMAKE_SYSTEM_NAME=iOS"
            "-DCMAKE_OSX_SYSROOT=iphonesimulator"
            "-DCMAKE_OSX_ARCHITECTURES=${ARCHS// /;}"
            "-DCMAKE_OSX_DEPLOYMENT_TARGET=${IPHONEOS_DEPLOYMENT_TARGET:-26.0}"
        )
        ;;
    *)
        echo "Unhandled PLATFORM_NAME='${PLATFORM_NAME}'" >&2
        exit 1
        ;;
esac

BUILD_DIR="${ENGINE_SIM_DIR}/${BUILD_SUBDIR}"
mkdir -p "${BUILD_DIR}"

# `cmake` may not be on the sanitized PATH Xcode gives the script — fall back
# to the standard Homebrew location on Apple Silicon machines.
CMAKE_BIN="$(command -v cmake || true)"
if [[ -z "${CMAKE_BIN}" ]]; then
    if [[ -x /opt/homebrew/bin/cmake ]]; then
        CMAKE_BIN="/opt/homebrew/bin/cmake"
    else
        echo "cmake not found on PATH and /opt/homebrew/bin/cmake is missing" >&2
        exit 1
    fi
fi

echo "[engine-sim] cmake configure -> ${BUILD_DIR} (${CONFIGURATION}, ${PLATFORM_NAME}, archs=${ARCHS})"
# `set -u` + bash 3.2 treats an empty array expansion as unbound, so guard it.
if [[ ${#CMAKE_PLATFORM_ARGS[@]} -gt 0 ]]; then
    "${CMAKE_BIN}" \
        -S "${ENGINE_SIM_DIR}" \
        -B "${BUILD_DIR}" \
        -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
        "${CMAKE_PLATFORM_ARGS[@]}"
else
    "${CMAKE_BIN}" \
        -S "${ENGINE_SIM_DIR}" \
        -B "${BUILD_DIR}" \
        -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}"
fi

CMAKE_BUILD_JOBS="${ENGINE_SIM_BUILD_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
echo "[engine-sim] cmake build -> ${BUILD_DIR} (-j ${CMAKE_BUILD_JOBS})"
"${CMAKE_BIN}" --build "${BUILD_DIR}" -j "${CMAKE_BUILD_JOBS}"
