#!/usr/bin/env bash
set -euo pipefail

PROJECT="Latest.xcodeproj"
SCHEME="Latest"
CONFIGURATION="Release"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
RESULT_BUNDLE="$BUILD_DIR/Latest-Complexity-Benchmark-$(date +%Y%m%d-%H%M%S).xcresult"
LOG_FILE="$BUILD_DIR/complexity-benchmark.log"
REPORT_FILE="$BUILD_DIR/complexity-benchmark.txt"
FLAG_FILE="$BUILD_DIR/run-complexity-benchmarks"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

rm -f "$LOG_FILE" "$REPORT_FILE"
touch "$FLAG_FILE"
trap 'rm -f "$FLAG_FILE"' EXIT

xcodebuild \
  -project "$ROOT_DIR/$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -enableCodeCoverage NO \
  ENABLE_TESTABILITY=YES \
  -only-testing:"Latest Tests/ComplexityBenchmarkTest/testComplexityBenchmarks" \
  test 2>&1 | tee "$LOG_FILE"

grep "BENCHMARK" "$LOG_FILE" > "$REPORT_FILE"

echo
echo "Complexity benchmark summary:"
cat "$REPORT_FILE"

awk '
BEGIN {
	budgets["app_data_store_update_batch"] = 40
	budgets["update_result_acceptance_overlap"] = 40
	budgets["app_list_snapshot_build_and_lookup"] = 12
	budgets["app_list_search_refilter"] = 160
	budgets["app_list_search_full_rebuild"] = 360
	budgets["version_comparison_repeated_parse"] = 75
	budgets["release_notes_markup_parse_and_render"] = 160
	budgets["release_notes_persistent_cache_read"] = 45
	budgets["update_repository_catalog_decode"] = 550
	budgets["update_repository_compact_index_decode"] = 180
	budgets["update_repository_entry_metadata_and_matching"] = 280
	budgets["update_repository_lazy_metadata_and_matching"] = 15
	budgets["bundle_collection_path_filtering"] = 170
	# Synthetic sleeping child tasks measure scheduler overhead, not network or
	# end-to-end app latency. Preserve the existing absolute ceiling.
	budgets["update_check_scheduler_fixture"] = 120
}

$1 == "BENCHMARK" {
	delete values
	for (fieldIndex = 2; fieldIndex <= NF; fieldIndex++) {
		split($fieldIndex, pair, "=")
		values[pair[1]] = pair[2]
	}
	name = values["name"]
	p95[name] = values["p95_ms"] + 0
	seen[name] = 1
}

END {
	failed = 0
	for (name in budgets) {
		if (!seen[name]) {
			printf "PERFORMANCE GATE FAIL missing=%s\n", name > "/dev/stderr"
			failed = 1
		} else if (p95[name] > budgets[name]) {
			printf "PERFORMANCE GATE FAIL name=%s p95_ms=%.3f budget_ms=%.3f\n", name, p95[name], budgets[name] > "/dev/stderr"
			failed = 1
		} else {
			printf "PERFORMANCE GATE PASS name=%s p95_ms=%.3f budget_ms=%.3f\n", name, p95[name], budgets[name]
		}
	}

	if (seen["app_list_search_refilter"] && seen["app_list_search_full_rebuild"] &&
		p95["app_list_search_refilter"] > p95["app_list_search_full_rebuild"] * 0.70) {
		printf "PERFORMANCE GATE FAIL search refilter no longer preserves a 30%% improvement\n" > "/dev/stderr"
		failed = 1
	}

	if (seen["update_repository_compact_index_decode"] && seen["update_repository_catalog_decode"] &&
		p95["update_repository_compact_index_decode"] > p95["update_repository_catalog_decode"] * 0.60) {
		printf "PERFORMANCE GATE FAIL compact repository decode is not at least 40%% faster\n" > "/dev/stderr"
		failed = 1
	}

	exit failed
}
' "$REPORT_FILE"
