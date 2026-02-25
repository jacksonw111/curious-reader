#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CuriousReader"
EXECUTABLE_NAME="CuriousReaderApp"
BUNDLE_ID="com.curious-reader.app"
VERSION="${APP_VERSION:-0.1.0}"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"
INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"
ICON_SOURCE="${ROOT_DIR}/logo/macos/AppIcon.icns"
ICON_FILE_NAME="AppIcon.icns"

cd "${ROOT_DIR}"

swift build -c release --product "${EXECUTABLE_NAME}"

BUILD_EXECUTABLE_PATH="${ROOT_DIR}/.build/release/${EXECUTABLE_NAME}"
if [[ ! -x "${BUILD_EXECUTABLE_PATH}" ]]; then
  BUILD_EXECUTABLE_PATH="$(find "${ROOT_DIR}/.build" -type f -path "*/release/${EXECUTABLE_NAME}" | head -n 1)"
fi
if [[ -z "${BUILD_EXECUTABLE_PATH}" || ! -x "${BUILD_EXECUTABLE_PATH}" ]]; then
  echo "Error: built executable not found for ${EXECUTABLE_NAME}" >&2
  exit 1
fi

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BUILD_EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cat > "${INFO_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>${ICON_FILE_NAME}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

printf "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

if [[ -f "${ICON_SOURCE}" ]]; then
  cp "${ICON_SOURCE}" "${RESOURCES_DIR}/${ICON_FILE_NAME}"
else
  echo "Warning: icon file not found at ${ICON_SOURCE}" >&2
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null
fi

echo "App bundle created: ${APP_BUNDLE}"
