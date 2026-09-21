#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
EXPECTED=117
echo "branch: $(git branch --show-current)"
echo "commit: $(git rev-parse --short HEAD)"
PROJECT=$(grep -m1 'CURRENT_PROJECT_VERSION' ToDo42.xcodeproj/project.pbxproj | tr -dc '0-9')
STAMP=$(sed -n 's/.*static let number = "\([0-9]*\)".*/\1/p' ToDo42/AppBuild.swift | head -1)
echo "Build $PROJECT (project)"
echo "Build $STAMP (AppBuild.swift stamp)"
if [[ "$PROJECT" != "$EXPECTED" || "$STAMP" != "$EXPECTED" ]]; then
  echo "FAIL: expected Build $EXPECTED"
  exit 1
fi
echo "OK — Build $EXPECTED. Next: open THIS project and delete DerivedData."
