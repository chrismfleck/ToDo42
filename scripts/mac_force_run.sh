#!/bin/bash
# Sync this checkout to the multi-pair branch, close Xcode, open the right project.
# After git reset, the script re-execs itself so stamp checks always match the
# newly pulled files (hard-coded 176 vs 177 used to fail mid-run).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BRANCH="cursor/multi-pair-isolation-ac25"

if [[ "${1:-}" != "--after-sync" ]]; then
  echo "=============================================="
  echo "1) WHERE IS THIS SCRIPT RUNNING FROM?"
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

  echo "3) GIT SYNC → origin/${BRANCH}"
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git reset --hard "origin/${BRANCH}"
  # Re-exec the freshly pulled script so EXPECTED/PROOF stamps match this commit.
  exec bash "$ROOT/scripts/mac_force_run.sh" --after-sync
fi

STAMP=$(sed -n 's/.*static let number = "\([0-9]*\)".*/\1/p' ToDo42/AppBuild.swift | head -1)
EXPECTED=$(sed -n 's/^EXPECTED=\([0-9]*\).*/\1/p' scripts/confirm_build.sh | head -1)
echo "   Synced. AppBuild stamp=${STAMP:-?}  confirm_build EXPECTED=${EXPECTED:-?}"
bash scripts/confirm_build.sh
echo "   AppBuild.swift now:"
grep -n 'static let number' ToDo42/AppBuild.swift
if [[ -z "${STAMP:-}" || -z "${EXPECTED:-}" || "$STAMP" != "$EXPECTED" ]]; then
  echo "ERROR: AppBuild stamp ${STAMP:-?} does not match confirm_build EXPECTED ${EXPECTED:-?}."
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
echo "  • Destination = Chris’s or Deena’s iPhone (not a Simulator)"
echo "  • Product → Clean Build Folder"
echo "  • Product → Run"
echo
echo "PROOF YOU GOT ${STAMP}:"
echo "  1. In-app bottom label:   Build ${STAMP}"
echo "  2. Xcode console:         >>> Save4Two AppBuild ${STAMP} SRC <<<"
echo
echo "If Help/bottom still says Build 130/135, Xcode opened a different folder."
echo "Do NOT delete the app (that wipes items). Restore via Pair → iCloud."
echo
echo "If you still see 'Couldn't create workspace arena' / Unable to write info.plist:"
echo "  • Apple menu → Log Out, log back in, re-run this script"
echo "  • Or reboot the Mac, then re-run this script"
echo "=============================================="
