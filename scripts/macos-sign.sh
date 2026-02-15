#!/usr/bin/env bash
#
# macos-sign.sh
#
# Deep-signs a LibreWolf.app bundle for distribution.
# Signs inner-to-outer: libraries, frameworks, helper apps, main bundle.
# Uses hardened runtime and secure timestamp (required for notarization).
#
# Usage: ./scripts/macos-sign.sh <path-to.app> <signing-identity> [entitlements.plist]
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
echo "==> Stripping extended attributes..."
xattr -cr "$APP_PATH"

# Step 1: Sign all Mach-O files that are NOT bundle executables.
# When codesign encounters a bundle's main executable, it tries to validate
# the entire bundle (including subcomponents not yet signed), so we must
# skip those and let them be signed as part of their bundle in later steps.
echo "==> Signing Mach-O binaries..."
sign_count=0
skip_count=0
find "$APP_PATH" -type f | while read -r f; do
    if ! file "$f" | grep -q "Mach-O"; then
        continue
    fi

    rel="${f#"$APP_PATH"/}"

    # Skip bundle executables — they'll be signed when their bundle is signed.
    # A bundle executable lives at <Name>.app/Contents/MacOS/<something>.
    # Signing it directly makes codesign validate the whole bundle prematurely.
    if [[ "$f" == *".app/Contents/MacOS/"* ]] && [[ "$rel" != *"/"*"/"*"/"*"/"* || "$f" == *".app/Contents/MacOS/"*".app/"* ]]; then
        # Check: is this file directly inside a .app/Contents/MacOS/ (not deeper)?
        # Get the path after the last .app/Contents/MacOS/
        after_macos="${f##*.app/Contents/MacOS/}"
        if [[ "$after_macos" != *"/"* ]]; then
            echo "  Skipping bundle executable: $rel (will sign with bundle)"
            skip_count=$((skip_count + 1))
            continue
        fi
    fi

    echo "  Signing: $rel"
    codesign "${CODESIGN_FLAGS[@]}" "$f"
    sign_count=$((sign_count + 1))
done
echo "  Signed $sign_count files, skipped $skip_count bundle executables"

# Step 2: Sign all frameworks
echo ""
echo "==> Signing frameworks..."
find "$APP_PATH" -name "*.framework" -type d | while read -r fw; do
    echo "  Signing: ${fw#"$APP_PATH"/}"
    codesign "${CODESIGN_FLAGS[@]}" "$fw"
done

# Step 3: Sign helper apps and XPC services (innermost first)
echo ""
echo "==> Signing helper apps and XPC services..."
# Sort by depth (deepest first) so nested bundles are signed before their parents
find "$APP_PATH" \( -name "*.app" -o -name "*.xpc" \) -type d -not -path "$APP_PATH" | \
    awk '{print gsub(/\//,"/"), $0}' | sort -rn | cut -d' ' -f2- | while read -r helper; do
    echo "  Signing: ${helper#"$APP_PATH"/}"
    codesign "${CODESIGN_FLAGS[@]}" "$helper"
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
