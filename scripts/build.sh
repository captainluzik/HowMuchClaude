#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="HowMuchClaude"
BUILD_DIR="${PROJECT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
TARGET="arm64-apple-macosx14.0"
SDK="$(xcrun --show-sdk-path)"

SWIFT_FILES=(
    Sources/App/*.swift
    Sources/Data/*.swift
    Sources/Data/Models/*.swift
    Sources/MenuBar/*.swift
    Sources/Overlay/*.swift
    Sources/Settings/*.swift
    Sources/Stats/*.swift
    Sources/Stats/Models/*.swift
)

echo "==> Cleaning build directory..."
rm -rf "${BUILD_DIR}"

echo "==> Compiling ${APP_NAME}..."
mkdir -p "${MACOS}"
cd "${PROJECT_DIR}"
swiftc \
    -o "${MACOS}/${APP_NAME}" \
    -target "${TARGET}" \
    -sdk "${SDK}" \
    -framework AppKit \
    -framework SwiftUI \
    -O \
    "${SWIFT_FILES[@]}"

echo "==> Creating .app bundle..."
cp "${PROJECT_DIR}/Resources/Info.plist" "${CONTENTS}/Info.plist"

mkdir -p "${RESOURCES}"

ICONSET_DIR=$(mktemp -d)
ICONSET="${ICONSET_DIR}/AppIcon.iconset"
mkdir -p "${ICONSET}"

ICON_SRC="${PROJECT_DIR}/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -f "${ICON_SRC}/16.png" ]; then
    cp "${ICON_SRC}/16.png"   "${ICONSET}/icon_16x16.png"
    cp "${ICON_SRC}/32.png"   "${ICONSET}/icon_16x16@2x.png"
    cp "${ICON_SRC}/32.png"   "${ICONSET}/icon_32x32.png"
    cp "${ICON_SRC}/64.png"   "${ICONSET}/icon_32x32@2x.png"
    cp "${ICON_SRC}/128.png"  "${ICONSET}/icon_128x128.png"
    cp "${ICON_SRC}/256.png"  "${ICONSET}/icon_128x128@2x.png"
    cp "${ICON_SRC}/256.png"  "${ICONSET}/icon_256x256.png"
    cp "${ICON_SRC}/512.png"  "${ICONSET}/icon_256x256@2x.png"
    cp "${ICON_SRC}/512.png"  "${ICONSET}/icon_512x512.png"
    cp "${ICON_SRC}/1024.png" "${ICONSET}/icon_512x512@2x.png"

    iconutil -c icns "${ICONSET}" -o "${RESOURCES}/AppIcon.icns"
    echo "==> App icon created"
else
    echo "==> Warning: icon PNGs not found, skipping icon"
fi
rm -rf "${ICONSET_DIR}"

echo "==> Build complete: ${APP_BUNDLE}"
echo ""
echo "    To install:  cp -r ${APP_BUNDLE} /Applications/"
echo "    To run:      open /Applications/${APP_NAME}.app"
