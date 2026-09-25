#!/usr/bin/env bash
#
# Build the Save4Two marketing site into a clean, ready-to-upload folder for
# Cloudflare Pages (Direct Upload / drag-and-drop in the dashboard).
#
# Output:
#   dist/                 <- the folder you upload to Cloudflare Pages
#   dist/save4two-site.zip? (no; see below)
#   save4two-site.zip     <- optional zip of dist/ for dashboard upload
#
# Usage:
#   scripts/build_site.sh          # build dist/ only
#   scripts/build_site.sh --zip    # also create save4two-site.zip
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_ROOT/website"
OUT_DIR="$REPO_ROOT/dist"
ZIP_PATH="$REPO_ROOT/save4two-site.zip"

# Files that make up the deployable static site.
FILES=(
  index.html
  privacy.html
  app-icon.png
  app-screenshot.png
  _redirects
)

echo "Building static site from: $SRC_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

for f in "${FILES[@]}"; do
  if [[ ! -f "$SRC_DIR/$f" ]]; then
    echo "ERROR: missing expected file: website/$f" >&2
    exit 1
  fi
  cp "$SRC_DIR/$f" "$OUT_DIR/$f"
done

echo "Wrote deploy folder: $OUT_DIR"
ls -la "$OUT_DIR"

if [[ "${1:-}" == "--zip" ]]; then
  rm -f "$ZIP_PATH"
  ( cd "$OUT_DIR" && zip -r -q "$ZIP_PATH" . )
  echo "Wrote upload zip: $ZIP_PATH"
fi

echo "Done. Upload the 'dist' folder (or save4two-site.zip) to Cloudflare Pages."
