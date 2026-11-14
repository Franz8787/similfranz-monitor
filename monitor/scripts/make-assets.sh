#!/bin/bash
# Genera icone e launch image (AppKit, macOS) in assets/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; OUT="$ROOT/build/tools"; mkdir -p "$OUT"
xcrun clang -fobjc-arc -framework AppKit "$ROOT/scripts/make-assets.m" -o "$OUT/make-assets"
"$OUT/make-assets" "$ROOT/assets"
