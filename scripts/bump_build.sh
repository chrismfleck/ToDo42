#!/bin/bash
# Bump AppBuild.swift stamp AND CURRENT_PROJECT_VERSION (plist) together.
# Usage: bash scripts/bump_build.sh 202
# Never bump one without the other — App Store / Help label must match.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+$ ]]; then
  echo "Usage: bash scripts/bump_build.sh <build-number>"
  exit 1
fi
NEW="$1"

OLD=$(sed -n 's/.*static let number = "\([0-9]*\)".*/\1/p' ToDo42/AppBuild.swift | head -1)
if [[ -z "$OLD" ]]; then
  echo "FAIL: could not read AppBuild.swift stamp"
  exit 1
fi
if [[ "$NEW" -le "$OLD" ]]; then
  echo "FAIL: new build $NEW must be greater than current $OLD"
  exit 1
fi

echo "Bumping build $OLD → $NEW (AppBuild + CURRENT_PROJECT_VERSION + confirm_build)"

# AppBuild stamp
sed -i '' -e "s/static let number = \"$OLD\"/static let number = \"$NEW\"/" ToDo42/AppBuild.swift 2>/dev/null \
  || sed -i -e "s/static let number = \"$OLD\"/static let number = \"$NEW\"/" ToDo42/AppBuild.swift

# confirm_build EXPECTED=
sed -i '' -e "s/^EXPECTED=${OLD}$/EXPECTED=${NEW}/" scripts/confirm_build.sh 2>/dev/null \
  || sed -i -e "s/^EXPECTED=${OLD}$/EXPECTED=${NEW}/" scripts/confirm_build.sh

# Xcode CURRENT_PROJECT_VERSION (feeds CFBundleVersion / plist)
sed -i '' -e "s/CURRENT_PROJECT_VERSION = ${OLD};/CURRENT_PROJECT_VERSION = ${NEW};/g" ToDo42.xcodeproj/project.pbxproj 2>/dev/null \
  || sed -i -e "s/CURRENT_PROJECT_VERSION = ${OLD};/CURRENT_PROJECT_VERSION = ${NEW};/g" ToDo42.xcodeproj/project.pbxproj

# Run Script phase hard-coded stamp check inside pbxproj
python3 - "$OLD" "$NEW" <<'PY'
import sys
from pathlib import Path
old, new = sys.argv[1], sys.argv[2]
p = Path("ToDo42.xcodeproj/project.pbxproj")
text = p.read_text()
# Matches both raw and escaped-quote forms used in the shellScript string.
replacements = [
    (f'!= \\"{old}\\"', f'!= \\"{new}\\"'),
    (f'(expected {old})', f'(expected {new})'),
    (f'!= "{old}"', f'!= "{new}"'),
]
changed = False
for a, b in replacements:
    if a in text:
        text = text.replace(a, b)
        changed = True
if not changed:
    raise SystemExit(f"FAIL: could not update pbxproj run-script stamp {old} → {new}")
p.write_text(text)
print(f"pbxproj run-script stamp {old} → {new}")
PY

bash scripts/confirm_build.sh
echo "OK — AppBuild and plist are both $NEW. Commit these files together."
