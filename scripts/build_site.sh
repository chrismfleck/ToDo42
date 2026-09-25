#!/usr/bin/env bash
#
# Build the Save4Two marketing site into a clean, ready-to-upload folder for
# Cloudflare Pages (Direct Upload / drag-and-drop in the dashboard).
#
# The site under website/ is plain static files (HTML, images, and a Cloudflare
# Pages _redirects rule), so there is no compile step: this copies the whole
# website/ folder into dist/ and drops OS/editor junk. New assets added to
# website/ are picked up automatically.
#
# Output:
#   dist/               <- the folder you upload to Cloudflare Pages
#   save4two-site.zip   <- optional zip of dist/ for dashboard upload (--zip)
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

if [[ ! -f "$SRC_DIR/index.html" ]]; then
  echo "ERROR: website/index.html not found — nothing to build." >&2
  exit 1
fi

echo "Building static site from: $SRC_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Copy the entire site (including dotfiles like _redirects), then remove junk.
cp -R "$SRC_DIR"/. "$OUT_DIR"/
find "$OUT_DIR" -type f \( -name '.DS_Store' -o -name '.AppleDouble' \) -delete

echo "Wrote deploy folder: $OUT_DIR"
ls -la "$OUT_DIR"

if [[ "${1:-}" == "--zip" ]]; then
  rm -f "$ZIP_PATH"
  ( cd "$OUT_DIR" && zip -r -q "$ZIP_PATH" . )
  echo "Wrote upload zip: $ZIP_PATH"
fi

echo "Done. Upload the 'dist' folder (or save4two-site.zip) to Cloudflare Pages."
