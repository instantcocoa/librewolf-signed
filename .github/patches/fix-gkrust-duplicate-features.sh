#!/usr/bin/env bash
# fix-gkrust-duplicate-features.sh
#
# Starting with Firefox 149.0.2, glean_disable_upload is already present in
# gkrust-features.mozbuild. The upstream LibreWolf librewolf-patches.py adds
# it unconditionally, causing a "features for gkrust should not contain
# duplicates" build failure.
#
# This patch makes the addition conditional. Safe to re-apply on every sync —
# once upstream fixes their script this becomes a no-op.

set -euo pipefail

PATCHES_PY="scripts/librewolf-patches.py"

if [[ ! -f "$PATCHES_PY" ]]; then
  echo "[fix-gkrust] $PATCHES_PY not found, skipping."
  exit 0
fi

# Check if the unconditional sed is still present
if grep -q 'glean_disable_upload' "$PATCHES_PY" && ! grep -q 'grep.*glean_disable_upload' "$PATCHES_PY"; then
  python3 -c "
import re, sys

path = '$PATCHES_PY'
with open(path) as f:
    content = f.read()

old = '''exec(\"sed -i '/# This must remain last./i gkrust_features += [\\\\\"glean_disable_upload\\\\\"]\\\\\\n' toolkit/library/rust/gkrust-features.mozbuild\")'''
new = '''exec(\"grep -q glean_disable_upload toolkit/library/rust/gkrust-features.mozbuild || sed -i '/# This must remain last./i gkrust_features += [\\\\\"glean_disable_upload\\\\\"]\\\\\\n' toolkit/library/rust/gkrust-features.mozbuild\")'''

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('[fix-gkrust] Patched — glean_disable_upload is now added only if missing.')
else:
    print('[fix-gkrust] Exact pattern not found, attempting line-level fix...')
    lines = content.split('\n')
    patched = False
    for i, line in enumerate(lines):
        if 'glean_disable_upload' in line and 'grep' not in line and 'sed' in line:
            lines[i] = line.replace(\"sed -i\", \"grep -q glean_disable_upload toolkit/library/rust/gkrust-features.mozbuild || sed -i\")
            patched = True
            break
    if patched:
        with open(path, 'w') as f:
            f.write('\n'.join(lines))
        print('[fix-gkrust] Patched (line-level) — glean_disable_upload is now added only if missing.')
    else:
        print('[fix-gkrust] Could not patch automatically. Manual intervention needed.', file=sys.stderr)
        sys.exit(1)
"
else
  echo "[fix-gkrust] Already fixed or pattern changed upstream, skipping."
fi
