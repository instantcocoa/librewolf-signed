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

# Build a list of bundle executable paths to skip in step 1.
# When codesign is given a bundle's CFBundleExecutable, it validates the
# entire bundle (including subcomponents not yet signed), causing failures.
# These executables get signed when their parent bundle is signed in later steps.
echo "==> Identifying bundle executables to defer..."
SKIP_PATHS=()
while IFS= read -r -d '' plist; do
    bundle_dir="$(dirname "$(dirname "$plist")")"
    exe_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null || true)
    if [[ -n "$exe_name" ]]; then
        exe_path="$bundle_dir/Contents/MacOS/$exe_name"
        if [[ -f "$exe_path" ]]; then
            SKIP_PATHS+=("$exe_path")
            echo "  Will defer: ${exe_path#"$APP_PATH"/}"
        fi
    fi
done < <(find "$APP_PATH" -name "Info.plist" -path "*/Contents/Info.plist" -print0)

# Step 1: Sign all Mach-O files except bundle executables.
echo ""
echo "==> Signing Mach-O binaries..."
find "$APP_PATH" -type f | while read -r f; do
    if ! file "$f" | grep -q "Mach-O"; then
        continue
    fi

    # Check if this file is a bundle executable we should skip
    skip=false
    for skip_path in "${SKIP_PATHS[@]}"; do
        if [[ "$f" == "$skip_path" ]]; then
            skip=true
            break
        fi
    done

    if $skip; then
        continue
    fi

    echo "  Signing: ${f#"$APP_PATH"/}"
    codesign "${CODESIGN_FLAGS[@]}" "$f"
done

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
