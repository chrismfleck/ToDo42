#!/bin/bash
# Find every ToDo42 checkout, sync THIS one to Build 150, close Xcode, open the right project.
set -euo pipefail

echo "=============================================="
echo "1) WHERE IS THIS SCRIPT RUNNING FROM?"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "   $ROOT"
echo "=============================================="
echo

echo "2) OTHER AppBuild.swift COPIES (stale Xcode folders cause Build 130):"
FOUND=0
while IFS= read -r f; do
  FOUND=1
  NUM=$(sed -n 's/.*static let number = "\([0-9]*\)".*/\1/p' "$f" | head -1)
  echo "   Build ${NUM:-?}  →  $f"
done < <(
  {
    mdfind 'kMDItemFSName == AppBuild.swift' 2>/dev/null || true
    for d in \
      "$HOME/ToDo42" \
      "$HOME/Documents/ToDo42" \
      "$HOME/Developer/ToDo42" \
      "$HOME/src/ToDo42" \
      "$HOME/Projects/ToDo42" \
      "$HOME/Desktop/ToDo42" \
      "$HOME/code/ToDo42"
    do
      [[ -f "$d/ToDo42/AppBuild.swift" ]] && echo "$d/ToDo42/AppBuild.swift"
    done
  } | sort -u
)
if [[ "$FOUND" -eq 0 ]]; then
  echo "   (none found via Spotlight — still check Xcode → File → Open Recent)"
fi
echo

echo "3) GIT SYNC → origin/cursor/save4two-unified-ac25"
git fetch origin cursor/save4two-unified-ac25
git checkout cursor/save4two-unified-ac25
git reset --hard origin/cursor/save4two-unified-ac25
bash scripts/confirm_build.sh
echo "   AppBuild.swift now:"
grep -n 'static let number' ToDo42/AppBuild.swift
echo

echo "4) QUIT XCODE + CLEAR CACHES"
osascript -e 'quit app "Xcode"' >/dev/null 2>&1 || true
sleep 2
rm -rf "${HOME}/Library/Developer/Xcode/DerivedData/ToDo42-"* 2>/dev/null || true
rm -rf "${HOME}/Library/Caches/com.apple.dt.Xcode" 2>/dev/null || true
echo "   Done."
echo

echo "5) OPEN ONLY THIS PROJECT"
open "${ROOT}/ToDo42.xcodeproj"
echo "   ${ROOT}/ToDo42.xcodeproj"
echo
echo "=============================================="
echo "IN XCODE NOW:"
echo "  • File → Project Settings / Open Recent — path MUST be:"
echo "    ${ROOT}"
echo "  • Destination = your physical iPhone"
echo "  • Product → Clean Build Folder"
echo "  • Product → Run"
echo
echo "PROOF YOU GOT 150:"
echo "  1. In-app bottom label:   Build 150"
echo "  2. Xcode console:         >>> Save4Two AppBuild 150 SRC <<<"
echo
echo "If Help/bottom still says Build 130/135, Xcode opened a different folder."
echo "Do NOT delete the app (that wipes items). Restore via Pair → iCloud."
echo "=============================================="
