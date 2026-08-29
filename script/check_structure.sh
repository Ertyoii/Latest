#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_roots=(
  Latest/App
  Latest/Features
  Latest/Domain
  Latest/Services
  Latest/Platform
  Latest/Support
)

for root in "${required_roots[@]}"; do
  if [[ ! -d "$root" ]]; then
    echo "Missing architecture root: $root" >&2
    exit 1
  fi
done

legacy_roots=(
  Latest/Model
  Latest/SwiftUI
  "Latest/View Model"
  Latest/Interface
  Latest/Utilities
)

for root in "${legacy_roots[@]}"; do
  if [[ -d "$root" ]] && [[ -n "$(find "$root" -type f -name '*.swift' -print -quit)" ]]; then
    echo "Swift source reintroduced under legacy root: $root" >&2
    exit 1
  fi
done

while IFS= read -r source; do
  line_count="$(wc -l < "$source" | tr -d ' ')"
  if (( line_count > 1500 )); then
    echo "Swift file exceeds the 1,500-line architecture ceiling: $source ($line_count lines)" >&2
    exit 1
  fi
done < <(rg --files Latest Tests -g '*.swift')

if rg -n 'NSWorkspace\.shared\.(open|activateFileViewer)|NSApplication\.shared' Latest/Domain; then
  echo "Domain source contains a direct macOS side effect" >&2
  exit 1
fi

if rg -n 'LOCAL_.*FIXTURE|localUATFixture' Latest/App/LatestApplication.swift; then
  echo "The runnable app must not replace live discovery with a local fixture" >&2
  exit 1
fi

plutil -lint Latest.xcodeproj/project.pbxproj >/dev/null
git diff --check

echo "Architecture and repository structure checks passed."
