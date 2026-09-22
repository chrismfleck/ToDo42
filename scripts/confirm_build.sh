#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
EXPECTED=138
echo "branch: $(git branch --show-current)"
echo "commit: $(git rev-parse --short HEAD)"
PROJECT=$(grep -m1 'CURRENT_PROJECT_VERSION' ToDo42.xcodeproj/project.pbxproj | tr -dc '0-9')
STAMP=$(sed -n 's/.*static let number = "\([0-9]*\)".*/\1/p' ToDo42/AppBuild.swift | head -1)
PLIST_KEY=$(grep -m1 'INFOPLIST_KEY_CFBundleVersion' ToDo42.xcodeproj/project.pbxproj)
echo "Build $PROJECT (project)"
echo "Build $STAMP (AppBuild.swift stamp)"
echo "plist key: $PLIST_KEY"
if [[ "$PROJECT" != "$EXPECTED" || "$STAMP" != "$EXPECTED" ]]; then
  echo "FAIL: expected Build $EXPECTED"
  exit 1
fi
if [[ "$PLIST_KEY" == *"= 130;"* ]]; then
  echo "FAIL: CFBundleVersion still pinned to 130 (phone will keep old install)"
  exit 1
fi
echo "OK — Build $EXPECTED. Do NOT delete the app. Run: bash scripts/mac_force_run.sh"
