#!/bin/bash

# Script to build KeySwitch and create a DMG installer with custom background and icon layout
# Usage: ./build_and_package.sh

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_NAME="KeySwitch"
SCHEME="KeySwitch"
CONFIGURATION="Release"
BUILD_DIR="build"
DMG_NAME="${PROJECT_NAME}.dmg"
APP_NAME="${PROJECT_NAME}.app"
DMG_TEMP="dmg_temp"
DMG_RW="dmg_rw.dmg"
VOLUME_NAME="${PROJECT_NAME}"
BACKGROUND_IMG="packaging/dmg_background.png"

echo "🔨 Building ${PROJECT_NAME} in ${CONFIGURATION} configuration..."

# Clean previous build
echo "🧹 Cleaning previous build..."
rm -rf "${BUILD_DIR}"
rm -f "${DMG_NAME}"
rm -f "${DMG_RW}"

# Build the project
echo "📦 Building project..."
xcodebuild \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${BUILD_DIR}" \
    clean build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

# Find the built app
APP_PATH=$(find "${BUILD_DIR}" -name "${APP_NAME}" -type d 2>/dev/null | head -n 1)
if [ -z "$APP_PATH" ]; then
    ALT_PATH="${BUILD_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}"
    if [ -d "$ALT_PATH" ]; then
        APP_PATH="$ALT_PATH"
    fi
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: Could not find built app"
    exit 1
fi

echo "✅ Found app at: ${APP_PATH}"

# ----- DMG layout -----
rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"

echo "📋 Copying app to DMG directory..."
cp -R "${APP_PATH}" "${DMG_TEMP}/"

echo "🔗 Creating Applications symlink..."
ln -s /Applications "${DMG_TEMP}/Applications"

# Add background image for DMG window (hidden folder)
if [ -f "${BACKGROUND_IMG}" ]; then
    echo "🖼 Adding DMG background..."
    mkdir -p "${DMG_TEMP}/.background"
    cp "${BACKGROUND_IMG}" "${DMG_TEMP}/.background/dmg_background.png"
fi

# Create read-write DMG (large enough for app + padding)
DMG_SIZE=150
echo "💿 Creating temporary DMG (${DMG_SIZE}MB)..."
hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${DMG_TEMP}" \
    -ov -format UDRW -size "${DMG_SIZE}m" "${DMG_RW}"

rm -rf "${DMG_TEMP}"

# Mount and apply layout
echo "📐 Applying window layout and background..."
MOUNT_POINT="/Volumes/${VOLUME_NAME}"
hdiutil attach "${DMG_RW}" -noverify -mountpoint "${MOUNT_POINT}" 2>/dev/null || true

# Wait for volume to be ready
for i in {1..10}; do
    [ -d "${MOUNT_POINT}" ] && break
    sleep 1
done

if [ ! -d "${MOUNT_POINT}" ]; then
    echo "⚠️ Could not mount DMG for layout; creating simple DMG without custom background."
    rm -f "${DMG_RW}"
    mkdir -p "${DMG_TEMP}"
    cp -R "${APP_PATH}" "${DMG_TEMP}/"
    ln -s /Applications "${DMG_TEMP}/Applications"
    hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${DMG_TEMP}" \
        -ov -format UDZO -imagekey zlib-level=9 "${DMG_NAME}"
    rm -rf "${DMG_TEMP}"
else
    # AppleScript: set icon view, background, icon positions
    if [ -f "${MOUNT_POINT}/.background/dmg_background.png" ]; then
        BG_POSIX="${MOUNT_POINT}/.background/dmg_background.png"
        osascript <<EOF
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {120, 100, 780, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:dmg_background.png"
        set position of item "${APP_NAME}" of container window to {140, 200}
        set position of item "Applications" of container window to {420, 200}
        close
    end tell
end tell
EOF
    fi

    hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || hdiutil detach "${MOUNT_POINT}" -force -quiet 2>/dev/null || true

    echo "💿 Compressing final DMG..."
    hdiutil convert "${DMG_RW}" -format UDZO -imagekey zlib-level=9 -o "${DMG_NAME}"
    rm -f "${DMG_RW}"
fi

echo "✅ DMG created successfully: ${DMG_NAME}"
echo "📦 File size: $(du -h "${DMG_NAME}" | cut -f1)"
echo ""
echo "🎉 Done! You can now distribute ${DMG_NAME} to testers."
echo ""
echo "📝 Instructions for testers:"
echo "   1. Double-click ${DMG_NAME} to mount it"
echo "   2. Drag ${APP_NAME} to Applications folder"
echo "   3. Open Applications and launch ${APP_NAME}"
echo "   4. Grant Accessibility permissions when prompted"
echo "   5. The app will appear in the menu bar"
