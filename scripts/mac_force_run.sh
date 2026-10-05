#!/bin/bash
# Find every ToDo42 checkout, sync THIS one to Build 176, close Xcode, open the right project.
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

BRANCH="cursor/multi-pair-isolation-ac25"
echo "3) GIT SYNC → origin/${BRANCH} (Build 176 multi-pair fix)"
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git reset --hard "origin/${BRANCH}"
bash scripts/confirm_build.sh
echo "   AppBuild.swift now:"
grep -n 'static let number' ToDo42/AppBuild.swift
STAMP=$(sed -n 's/.*static let number = "\([0-9]*\)".*/\1/p' ToDo42/AppBuild.swift | head -1)
if [[ "$STAMP" != "176" ]]; then
  echo "ERROR: expected Build 176 after sync, got ${STAMP:-?}."
  echo "Wrong folder or fetch failed. Path must be this checkout: $ROOT"
  exit 1
fi
echo

echo "4) QUIT XCODE + CLEAR DERIVEDDATA (fixes 'Couldn't create workspace arena')"
osascript -e 'quit app "Xcode"' >/dev/null 2>&1 || true
sleep 2
# Kill leftover build helpers that hold DerivedData locks.
pkill -9 -f 'Xcode' 2>/dev/null || true
pkill -9 -f 'XCBuild' 2>/dev/null || true
pkill -9 -f 'SourceKitService' 2>/dev/null || true
pkill -9 -f 'SWBBuildService' 2>/dev/null || true
pkill -9 -f 'com.apple.dt.SKAgent' 2>/dev/null || true
sleep 1
DD="${HOME}/Library/Developer/Xcode/DerivedData"
if [[ -d "$DD" ]]; then
  # Drop uchg/flags that block delete, then remove ToDo42 arenas (and whole
  # DerivedData if a ToDo42 folder still cannot be removed).
  chflags -R nouchg,noschg "$DD"/ToDo42-* 2>/dev/null || true
  rm -rf "$DD"/ToDo42-* 2>/dev/null || true
  if compgen -G "$DD/ToDo42-*" > /dev/null; then
    echo "   ToDo42 DerivedData still stuck — clearing ALL DerivedData"
    chflags -R nouchg,noschg "$DD" 2>/dev/null || true
    rm -rf "$DD" 2>/dev/null || true
  fi
fi
rm -rf "${HOME}/Library/Caches/com.apple.dt.Xcode" 2>/dev/null || true
rm -rf "${HOME}/Library/Developer/Xcode/iOS DeviceSupport"/*/Symbols/System/Library/Caches 2>/dev/null || true
mkdir -p "${HOME}/Library/Developer/Xcode/DerivedData"
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
echo "  • Destination = Deena’s iPhone (not Chris, not a Simulator)"
echo "  • Product → Clean Build Folder"
echo "  • Product → Run"
echo
echo "PROOF YOU GOT 176:"
echo "  1. In-app bottom label:   Build 176"
echo "  2. Xcode console:         >>> Save4Two AppBuild 176 SRC <<<"
echo
echo "If Help/bottom still says Build 130/135, Xcode opened a different folder."
echo "Do NOT delete the app (that wipes items). Restore via Pair → iCloud."
echo
echo "If you still see 'Couldn't create workspace arena' / Unable to write info.plist:"
echo "  • Apple menu → Log Out, log back in, re-run this script"
echo "  • Or reboot the Mac, then re-run this script"
echo "=============================================="
