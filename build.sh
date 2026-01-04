#!/bin/bash

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="VhisperNative"
APP_NAME="Vhisper"
SCHEME="VhisperNative"
CONFIGURATION="Release"
BUILD_DIR="${PROJECT_DIR}/build"
APPLICATIONS_DIR="/Applications"

echo "==> Building ${APP_NAME}..."

cd "${PROJECT_DIR}"

# Clean previous build
rm -rf "${BUILD_DIR}"

# Build the app
xcodebuild \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${BUILD_DIR}" \
    build

# Find the built app
APP_PATH=$(find "${BUILD_DIR}" -name "${APP_NAME}.app" -type d | head -1)

if [ -z "${APP_PATH}" ]; then
    echo "Error: ${APP_NAME}.app not found in build output"
    exit 1
fi

echo "==> Built: ${APP_PATH}"

# Remove old app if exists
if [ -d "${APPLICATIONS_DIR}/${APP_NAME}.app" ]; then
    echo "==> Removing old ${APP_NAME}.app from ${APPLICATIONS_DIR}..."
    rm -rf "${APPLICATIONS_DIR}/${APP_NAME}.app"
fi

# Copy to Applications
echo "==> Copying to ${APPLICATIONS_DIR}..."
cp -R "${APP_PATH}" "${APPLICATIONS_DIR}/"

echo "==> Done! ${APP_NAME}.app installed to ${APPLICATIONS_DIR}"
