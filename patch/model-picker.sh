#!/usr/bin/env bash
# Patch Claudex source to surface DeepSeek model names in the /model picker.
# Run AFTER ./vendor.sh, BEFORE ./deploy.sh --build
set -euo pipefail

SRC="/home/jjcm/puna/claudex-src"

if [[ ! -d "$SRC" ]]; then
  echo "[patch] claudex-src not found — run ./vendor.sh first"
  exit 1
fi

# Replace every hardcoded Anthropic model identifier with the DeepSeek equivalents.
# Claudex bundles model lists in JS/TS source; sed handles all occurrences.
find "$SRC/src" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.json" \) | while read -r f; do
  sed -i \
    -e 's/claude-opus-4-[0-9]*/deepseek-reasoner/g' \
    -e 's/claude-sonnet-4-[0-9]*/deepseek-chat/g' \
    -e 's/claude-haiku-4-[0-9]*/deepseek-chat/g' \
    -e 's/claude-3-5-sonnet-[0-9]*/deepseek-chat/g' \
    -e 's/claude-3-opus-[0-9]*/deepseek-reasoner/g' \
    -e 's/claude-3-haiku-[0-9]*/deepseek-chat/g' \
    "$f"
done

echo "[patch] model-picker patched — Claudex will show deepseek-chat / deepseek-reasoner"
