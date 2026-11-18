#!/bin/bash
#
# =============================================================================
# Script Name:   build_pkg.sh
# Description:   Builds IconFinder (Release) and packages it as an installer
#                that installs IconFinder.app into /Applications.
#
# Usage:         ./scripts/build_pkg.sh
#
# Output:        dist/IconFinder.app
#                dist/IconFinder-<version>.pkg
#
# Author:        Russell Collis
# License:       MIT
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$REPO_DIR/dist"
# Persistent (gitignored) work dir so a slow notarization can be resumed
WORK_DIR="$REPO_DIR/build/pkg"
DERIVED_DIR="$WORK_DIR/DerivedData"
PKG_ID="com.russcollis.IconFinder.pkg"
APP_IDENTITY="Developer ID Application: Russell Collis (UM5LY5579J)"
INSTALLER_IDENTITY="Developer ID Installer: Russell Collis (UM5LY5579J)"
NOTARY_PROFILE="notary"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "🔨 Building IconFinder (Release)..."
xcodebuild \
    -project "$REPO_DIR/Icon Finder.xcodeproj" \
    -scheme "Icon Finder" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DIR" \
    clean build -quiet

APP="$DERIVED_DIR/Build/Products/Release/IconFinder.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")

echo "🔏 Signing app with Developer ID..."
codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "📦 Packaging IconFinder $VERSION..."
mkdir -p "$WORK_DIR/root" "$WORK_DIR/resources" "$DIST_DIR"
ditto "$APP" "$WORK_DIR/root/IconFinder.app"

# Component package: always install to /Applications, never relocate
pkgbuild --analyze --root "$WORK_DIR/root" "$WORK_DIR/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK_DIR/component.plist"
pkgbuild \
    --root "$WORK_DIR/root" \
    --component-plist "$WORK_DIR/component.plist" \
    --identifier "$PKG_ID" \
    --version "$VERSION" \
    --install-location /Applications \
    "$WORK_DIR/IconFinder-component.pkg"

# Product archive with title and MIT license screen
cp "$REPO_DIR/LICENSE" "$WORK_DIR/resources/LICENSE.txt"
cat > "$WORK_DIR/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>IconFinder</title>
    <license file="LICENSE.txt"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <volume-check><allowed-os-versions><os-version min="$MIN_OS"/></allowed-os-versions></volume-check>
    <choices-outline><line choice="default"/></choices-outline>
    <choice id="default" title="IconFinder">
        <pkg-ref id="$PKG_ID"/>
    </choice>
    <pkg-ref id="$PKG_ID" version="$VERSION" onConclusion="none">IconFinder-component.pkg</pkg-ref>
</installer-gui-script>
EOF

PKG_OUT="$DIST_DIR/IconFinder-$VERSION.pkg"
rm -rf "$PKG_OUT" "$DIST_DIR/IconFinder.app"
productbuild \
    --sign "$INSTALLER_IDENTITY" \
    --timestamp \
    --distribution "$WORK_DIR/distribution.xml" \
    --resources "$WORK_DIR/resources" \
    --package-path "$WORK_DIR" \
    "$PKG_OUT"

# Notarizing the pkg also notarizes the nested app, so both can be stapled
echo "📨 Notarizing package..."
xcrun notarytool submit "$PKG_OUT" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$PKG_OUT"
xcrun stapler staple "$APP"
ditto "$APP" "$DIST_DIR/IconFinder.app"
spctl -a -vvv -t install "$PKG_OUT"
spctl -a -vvv "$DIST_DIR/IconFinder.app"

echo "✅ Done:"
echo "   $DIST_DIR/IconFinder.app"
echo "   $PKG_OUT"
