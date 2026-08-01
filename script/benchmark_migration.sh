#!/usr/bin/env bash
set -euo pipefail

LABEL="${1:-current}"
SIDEBAR_IMPLEMENTATION="${2:-}"
if [[ ! "$LABEL" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Benchmark label must contain only letters, numbers, underscores, or hyphens." >&2
  exit 2
fi
if [[ -n "$SIDEBAR_IMPLEMENTATION" && "$SIDEBAR_IMPLEMENTATION" != "legacy" && "$SIDEBAR_IMPLEMENTATION" != "native" ]]; then
  echo "Sidebar implementation must be legacy, native, or omitted." >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
RESULT_BUNDLE="$BUILD_DIR/Latest-Migration-Benchmark-$LABEL-$(date +%Y%m%d-%H%M%S).xcresult"
LOG_FILE="$BUILD_DIR/migration-benchmark-$LABEL.log"
REPORT_FILE="$BUILD_DIR/migration-benchmark-$LABEL.txt"
FLAG_FILE="$BUILD_DIR/run-migration-benchmarks"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"
rm -f "$LOG_FILE" "$REPORT_FILE"
printf '%s\n' "$SIDEBAR_IMPLEMENTATION" > "$FLAG_FILE"
trap 'rm -f "$FLAG_FILE"' EXIT

if [[ -n "$SIDEBAR_IMPLEMENTATION" ]]; then
  export LATEST_SIDEBAR_IMPLEMENTATION="$SIDEBAR_IMPLEMENTATION"
fi

xcodebuild \
  -project "$ROOT_DIR/Latest.xcodeproj" \
  -scheme Latest \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -enableCodeCoverage NO \
  -only-testing:'Latest Tests/MigrationPerformanceTest/testMigrationPerformanceMatrix' \
  test 2>&1 | tee "$LOG_FILE"

rg '^MIGRATION_(CONFIGURATION|BENCHMARK|MEMORY)' "$LOG_FILE" > "$REPORT_FILE"

echo
echo "Migration benchmark summary ($LABEL):"
cat "$REPORT_FILE"
