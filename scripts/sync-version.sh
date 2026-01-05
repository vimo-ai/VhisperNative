#!/bin/bash
# Sync version to Info.plist
VERSION=$1
PLIST_PATH="VhisperNative/Resources/Info.plist"

echo "Syncing version $VERSION to $PLIST_PATH"

# Update CFBundleShortVersionString (display version like 1.0.0)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST_PATH"

# Update CFBundleVersion (build number - use version without dots)
BUILD_NUMBER=$(echo "$VERSION" | tr -d '.')
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST_PATH"

echo "Version synced: $VERSION (build: $BUILD_NUMBER)"
