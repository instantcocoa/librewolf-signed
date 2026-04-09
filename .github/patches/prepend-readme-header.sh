#!/usr/bin/env bash
# prepend-readme-header.sh
#
# Prepend our signed macOS build header to README.md after upstream syncs.
# The upstream sync overwrites README.md, so we re-add our install info.

set -euo pipefail

README="README.md"

if [[ ! -f "$README" ]]; then
  echo "[readme-header] $README not found, skipping."
  exit 0
fi

# Skip if our header is already present
if grep -q 'LibreWolf macOS (Signed & Notarized)' "$README"; then
  echo "[readme-header] Header already present, skipping."
  exit 0
fi

HEADER='# LibreWolf macOS (Signed & Notarized)

Signed and notarized macOS universal binary builds of [LibreWolf](https://librewolf.net), produced automatically from upstream releases.

## Install

```bash
brew tap instantcocoa/tap
brew install --cask librewolf-signed
```

Or download the latest DMG from [Releases](../../releases).

---

'

echo "[readme-header] Prepending signed build header to README.md."
printf '%s' "$HEADER" | cat - "$README" > "${README}.tmp" && mv "${README}.tmp" "$README"
