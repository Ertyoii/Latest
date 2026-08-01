#!/usr/bin/env bash
set -euo pipefail

REPORT_ONLY=false
if [[ "${1:-}" == "--report-only" ]]; then
  REPORT_ONLY=true
  shift
fi

if (($# < 2 || $# > 3)); then
  echo "usage: $0 [--report-only] LEGACY_REPORT NATIVE_REPORT [NATIVE_LOG]" >&2
  exit 2
fi

LEGACY_REPORT="$1"
NATIVE_REPORT="$2"
NATIVE_LOG="${3:-${NATIVE_REPORT%.txt}.log}"

for report in "$LEGACY_REPORT" "$NATIVE_REPORT"; do
  if [[ ! -f "$report" ]]; then
    echo "error: benchmark report not found: $report" >&2
    exit 2
  fi
done

metric() {
  local report="$1"
  local benchmark="$2"
  local statistic="$3"
  awk -v benchmark="$benchmark" -v statistic="$statistic" '
    $1 == "MIGRATION_BENCHMARK" {
      delete values
      for (field_index = 2; field_index <= NF; field_index++) {
        split($field_index, pair, "=")
        values[pair[1]] = pair[2]
      }
      if (values["name"] == benchmark) {
        print values[statistic]
        found = 1
        exit
      }
    }
    END { if (!found) exit 1 }
  ' "$report"
}

blocked=0
compare_metric() {
  local benchmark="$1"
  local statistic="$2"
  local maximum_ratio="$3"
  local legacy_value native_value ratio
  legacy_value="$(metric "$LEGACY_REPORT" "$benchmark" "$statistic")"
  native_value="$(metric "$NATIVE_REPORT" "$benchmark" "$statistic")"
  ratio="$(awk -v legacy="$legacy_value" -v native="$native_value" 'BEGIN { printf "%.3f", native / legacy }')"

  if awk -v ratio="$ratio" -v maximum="$maximum_ratio" 'BEGIN { exit !(ratio <= maximum) }'; then
    echo "NATIVE CUTOVER PASS name=$benchmark statistic=$statistic legacy_ms=$legacy_value native_ms=$native_value ratio=$ratio maximum_ratio=$maximum_ratio"
  else
    echo "NATIVE CUTOVER BLOCKED name=$benchmark statistic=$statistic legacy_ms=$legacy_value native_ms=$native_value ratio=$ratio maximum_ratio=$maximum_ratio"
    blocked=1
  fi
}

# Median is used for cold launch because a single XCTWaiter scheduling spike can
# dominate this short fixture. Scrolling and selection use p95 to protect input
# responsiveness and tail latency.
compare_metric "cold_launch_to_populated_sidebar_fixture" "p50_ms" "1.15"
compare_metric "sidebar_scroll_frame_main_thread" "p95_ms" "1.15"
compare_metric "selection_to_detail" "p95_ms" "1.20"

warning_count=0
if [[ -f "$NATIVE_LOG" ]]; then
  warning_count="$(rg -c 'reentrant operation in its NSTableView delegate' "$NATIVE_LOG" || true)"
fi
if ((warning_count > 0)); then
  echo "NATIVE CUTOVER BLOCKED runtime_warning=nstableview_reentrancy count=$warning_count"
  blocked=1
else
  echo "NATIVE CUTOVER PASS runtime_warning=nstableview_reentrancy count=0"
fi

if ((blocked)); then
  echo "NATIVE CUTOVER RESULT blocked; retain the reviewed UpdatesTableBridge"
  if [[ "$REPORT_ONLY" == false ]]; then
    exit 1
  fi
else
  echo "NATIVE CUTOVER RESULT eligible for visual, keyboard, and accessibility parity review"
fi
