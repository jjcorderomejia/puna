#!/usr/bin/env bash
# Run ONCE to vendor Claudex source locally.
# After this, delete or ignore the remote repo — we never need it again.
set -euo pipefail

DEST="/home/jjcm/puna/claudex-src"

if [[ -d "$DEST" ]]; then
  echo "[puna] claudex-src already exists — skipping. Delete it and re-run to refresh."
  exit 0
fi

echo "[puna] Cloning Claudex into $DEST ..."
git clone --depth 1 https://github.com/l3tchupkt/Claudex "$DEST"

# Strip git history — we own this copy now
rm -rf "$DEST/.git"

echo "[puna] Vendored. The remote repo is no longer needed."
