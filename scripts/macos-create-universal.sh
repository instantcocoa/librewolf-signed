#!/usr/bin/env bash
#
# macos-create-universal.sh
#
# Merges an arm64 .app and an x86_64 .app into a universal (fat) .app bundle.
# Usage: ./scripts/macos-create-universal.sh <arm64.app> <x86_64.app> <output.app>
#

set -euo pipefail

ARM64_APP="$1"
X86_64_APP="$2"
OUTPUT_APP="$3"

if [[ -z "$ARM64_APP" || -z "$X86_64_APP" || -z "$OUTPUT_APP" ]]; then
    echo "Usage: $0 <arm64.app> <x86_64.app> <output.app>"
    exit 1
fi

if [[ ! -d "$ARM64_APP" || ! -d "$X86_64_APP" ]]; then
    echo "Error: Both input .app bundles must exist as directories."
    exit 1
fi

echo "Creating universal binary..."
echo "  arm64:  $ARM64_APP"
echo "  x86_64: $X86_64_APP"
echo "  output: $OUTPUT_APP"

# Start with the arm64 build as the base
rm -rf "$OUTPUT_APP"
cp -a "$ARM64_APP" "$OUTPUT_APP"

# Find all Mach-O files in the arm64 .app and merge with x86_64 counterparts
merge_count=0
skip_count=0

while IFS= read -r -d '' arm64_file; do
    rel_path="${arm64_file#"$ARM64_APP"/}"
    x86_file="$X86_64_APP/$rel_path"
    out_file="$OUTPUT_APP/$rel_path"

    # Skip if no x86_64 counterpart
    if [[ ! -f "$x86_file" ]]; then
        skip_count=$((skip_count + 1))
        continue
    fi

    # Check if this is a Mach-O file
    if ! file "$arm64_file" | grep -q "Mach-O"; then
        continue
    fi

    # Check if the x86_64 file is also Mach-O
    if ! file "$x86_file" | grep -q "Mach-O"; then
        echo "Warning: $rel_path is Mach-O in arm64 but not in x86_64, skipping merge"
        skip_count=$((skip_count + 1))
        continue
    fi

    # Merge with lipo
    lipo -create "$arm64_file" "$x86_file" -output "$out_file"
    merge_count=$((merge_count + 1))

done < <(find "$ARM64_APP" -type f -print0)

echo ""
echo "Universal binary merge complete:"
echo "  Merged: $merge_count Mach-O files"
echo "  Skipped: $skip_count files (no counterpart or not Mach-O)"

# Verify a few key binaries
echo ""
echo "Verification:"
main_binary=$(find "$OUTPUT_APP/Contents/MacOS" -maxdepth 1 -type f | head -1)
if [[ -n "$main_binary" ]]; then
    echo "  Main binary:"
    lipo -info "$main_binary"
fi
