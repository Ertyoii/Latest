#!/usr/bin/env bash
set -euo pipefail

LABEL="${1:-current}"
SIDEBAR_IMPLEMENTATION="${2:-appkit}"
if [[ ! "$LABEL" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Benchmark label must contain only letters, numbers, underscores, or hyphens." >&2
  exit 2
fi
if [[ "$SIDEBAR_IMPLEMENTATION" != "appkit" ]]; then
  echo "The shipping sidebar benchmark uses the measured AppKit parity renderer; use appkit or omit the second argument." >&2
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

LATEST_SIDEBAR_IMPLEMENTATION="$SIDEBAR_IMPLEMENTATION" xcodebuild \
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

awk '
BEGIN {
	budgets["cold_launch_to_populated_sidebar_fixture"] = 65
	statistics["cold_launch_to_populated_sidebar_fixture"] = "p50_ms"
	budgets["sidebar_scroll_frame_main_thread"] = 28
	statistics["sidebar_scroll_frame_main_thread"] = "p95_ms"
	budgets["sidebar_long_jump_main_thread"] = 50
	statistics["sidebar_long_jump_main_thread"] = "p95_ms"
	budgets["selection_to_detail"] = 8
	statistics["selection_to_detail"] = "p95_ms"
}

$1 == "MIGRATION_BENCHMARK" {
	delete values
	for (fieldIndex = 2; fieldIndex <= NF; fieldIndex++) {
		split($fieldIndex, pair, "=")
		values[pair[1]] = pair[2]
	}
	name = values["name"]
	if (name in budgets) {
		observed[name] = values[statistics[name]] + 0
		seen[name] = 1
	}
}

$1 == "MIGRATION_MEMORY" {
	delete values
	for (fieldIndex = 2; fieldIndex <= NF; fieldIndex++) {
		split($fieldIndex, pair, "=")
		values[pair[1]] = pair[2]
	}
	if (values["name"] ~ /^repeated_selection(_[0-9]+)?$/) {
		memoryDelta = values["delta_bytes"] + 0
		memorySeen = 1
	}
}

END {
	failed = 0
	for (name in budgets) {
		if (!seen[name]) {
			printf "MIGRATION GATE FAIL missing=%s\n", name > "/dev/stderr"
			failed = 1
		} else if (observed[name] > budgets[name]) {
			printf "MIGRATION GATE FAIL name=%s statistic=%s observed_ms=%.3f budget_ms=%.3f\n", name, statistics[name], observed[name], budgets[name] > "/dev/stderr"
			failed = 1
		} else {
			printf "MIGRATION GATE PASS name=%s statistic=%s observed_ms=%.3f budget_ms=%.3f\n", name, statistics[name], observed[name], budgets[name]
		}
	}
	if (!memorySeen) {
		print "MIGRATION GATE FAIL missing=repeated_selection_memory" > "/dev/stderr"
		failed = 1
	} else if (memoryDelta > 24 * 1024 * 1024) {
		printf "MIGRATION GATE FAIL name=repeated_selection_memory delta_bytes=%d budget_bytes=%d\n", memoryDelta, 24 * 1024 * 1024 > "/dev/stderr"
		failed = 1
	} else {
		printf "MIGRATION GATE PASS name=repeated_selection_memory delta_bytes=%d budget_bytes=%d\n", memoryDelta, 24 * 1024 * 1024
	}
	exit failed
}
' "$REPORT_FILE"

warning_count="$(rg -c 'reentrant operation in its NSTableView delegate|Publishing changes from within view updates' "$LOG_FILE" || true)"
if ((warning_count > 0)); then
	echo "MIGRATION GATE FAIL runtime_warning_count=$warning_count" >&2
	exit 1
fi
echo "MIGRATION GATE PASS runtime_warning_count=0"
