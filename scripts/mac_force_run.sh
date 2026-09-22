#!/bin/bash
# Open the CORRECT ToDo42 project from this git checkout and force a clean rebuild.
# Do NOT delete the app on the phone — that wipes local items. Re-pair / Restore instead.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== SOURCE FOLDER (Xcode must open THIS path) ==="
echo "$ROOT"
echo

git fetch origin cursor/save4two-unified-ac25
git checkout cursor/save4two-unified-ac25
git reset --hard origin/cursor/save4two-unified-ac25

bash scripts/confirm_build.sh
echo
echo "AppBuild.swift:"
grep -n 'static let number' ToDo42/AppBuild.swift
echo "CFBundleVersion keys:"
grep -n 'INFOPLIST_KEY_CFBundleVersion\|CURRENT_PROJECT_VERSION' ToDo42.xcodeproj/project.pbxproj | head
echo

rm -rf "${HOME}/Library/Developer/Xcode/DerivedData/ToDo42-"* 2>/dev/null || true
echo "Cleared ToDo42 DerivedData."
echo

open "${ROOT}/ToDo42.xcodeproj"
echo "Opened: ${ROOT}/ToDo42.xcodeproj"
echo
echo "IN XCODE:"
echo "  1. File → Open Recent — confirm path is exactly:"
echo "     ${ROOT}/ToDo42.xcodeproj"
echo "  2. Product → Destination → your iPhone (not a simulator copy of an old app)"
echo "  3. Product → Clean Build Folder"
echo "  4. Product → Run"
echo "  5. Home screen bottom must say Build 134 (not 130)."
echo
echo "ITEMS: deleting the app cleared pairing. Tap the heart+ Pair button →"
echo "  Restore from iCloud with your old 6-digit Messages code (or re-join)."
