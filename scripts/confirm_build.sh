#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "branch: $(git branch --show-current)"
echo "commit: $(git rev-parse --short HEAD)"
BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' ToDo42.xcodeproj/project.pbxproj | tr -dc '0-9')
echo "project build: $BUILD"
if [[ ! -f ToDo42/AppBuild.swift ]]; then
  echo "FAIL: ToDo42/AppBuild.swift missing — you are not on the Save4Two unified branch tip."
  exit 1
fi
if [[ "$BUILD" -lt 116 ]]; then
  echo "FAIL: expected Build 116+, got $BUILD. Run: git pull origin cursor/save4two-unified-ac25"
  exit 1
fi
echo "OK — open Xcode and run. Help + home must say Build $BUILD."
