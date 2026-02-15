#!/usr/bin/env bash
#
# macos-sign.sh
#
# Deep-signs a LibreWolf.app bundle for distribution.
# Signs inner-to-outer (frameworks/dylibs first, main binary last)
# with hardened runtime and secure timestamp (required for notarization).
#
# Usage: ./scripts/macos-sign.sh <path-to.app> <signing-identity> <entitlements.plist>
#
# Example:
#   ./scripts/macos-sign.sh LibreWolf.app "Developer ID Application: ..." assets/entitlements.plist
#

set -euo pipefail

APP_PATH="$1"
IDENTITY="$2"
ENTITLEMENTS="${3:-}"

if [[ -z "$APP_PATH" || -z "$IDENTITY" ]]; then
    echo "Usage: $0 <path-to.app> <signing-identity> [entitlements.plist]"
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: $APP_PATH does not exist or is not a directory."
    exit 1
fi

CODESIGN_FLAGS=(
    --force
    --options runtime
    --timestamp
    --sign "$IDENTITY"
)

if [[ -n "$ENTITLEMENTS" ]]; then
    CODESIGN_FLAGS+=(--entitlements "$ENTITLEMENTS")
    echo "Using entitlements: $ENTITLEMENTS"
fi

echo "Signing $APP_PATH with identity: $IDENTITY"
echo ""

# Step 0: Strip extended attributes (resource forks, Finder info, etc.)
# These cause "resource fork, Finder information, or similar detritus not allowed" errors
echo "==> Stripping extended attributes..."
xattr -cr "$APP_PATH"

# Step 1: Sign all dylibs and .so files (innermost first)
echo "==> Signing shared libraries..."
find "$APP_PATH" \( -name "*.dylib" -o -name "*.so" \) -type f | while read -r lib; do
    echo "  Signing: ${lib#"$APP_PATH"/}"
    codesign "${CODESIGN_FLAGS[@]}" "$lib"
done

# Step 2: Sign all frameworks
echo ""
echo "==> Signing frameworks..."
find "$APP_PATH" -name "*.framework" -type d | while read -r fw; do
    echo "  Signing: ${fw#"$APP_PATH"/}"
    codesign "${CODESIGN_FLAGS[@]}" "$fw"
done

# Step 3: Sign helper apps and XPC services
echo ""
echo "==> Signing helper apps and XPC services..."
find "$APP_PATH" \( -name "*.app" -o -name "*.xpc" \) -type d -not -path "$APP_PATH" | while read -r helper; do
    echo "  Signing: ${helper#"$APP_PATH"/}"
    codesign --deep "${CODESIGN_FLAGS[@]}" "$helper"
done

# Step 4: Sign the main app bundle
echo ""
echo "==> Signing main app bundle..."
codesign "${CODESIGN_FLAGS[@]}" "$APP_PATH"

# Step 5: Verify
echo ""
echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo ""
echo "Signing complete and verified."
