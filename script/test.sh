#!/usr/bin/env bash
set -euo pipefail

PROJECT="Latest.xcodeproj"
SCHEME="Latest"
CONFIGURATION="Debug"
MODE=background
COVERAGE=NO
FILTERS=()
HAS_ONLY_FILTER=false
for argument in "$@"; do
  case "$argument" in
    --ui) MODE=ui ;;
    --all) MODE=all ;;
    --coverage) COVERAGE=YES ;;
    -only-testing:*) FILTERS+=("$argument"); HAS_ONLY_FILTER=true ;;
    -skip-testing:*) FILTERS+=("$argument") ;;
    --help)
      echo "Usage: $0 [--ui|--all] [--coverage] [-only-testing:target/class/method]"
      echo "Default: offline background checks. --ui: window/input checks. --all: both."
      exit 0 ;;
    *) echo "Unknown argument: $argument" >&2; exit 2 ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
RESULT_BUNDLE="$BUILD_DIR/Latest-Tests-$(date +%Y%m%d-%H%M%S).xcresult"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

/usr/bin/python3 -m unittest discover -s "$ROOT_DIR/script/tests"
"$ROOT_DIR/script/check_structure.sh"

export TEST_RUNNER_LATEST_UI_TESTS=0
if [[ "$MODE" != background ]]; then
  export TEST_RUNNER_LATEST_UI_TESTS=1
  echo "UI tests open production windows and may take keyboard focus."
fi
if [[ "$MODE" == ui && "$HAS_ONLY_FILTER" == false ]]; then
  for suite in MigrationInteractionContractTest MigrationVisualRegressionTest ProductionVisualParityTest ReleaseNotesHeaderLayoutTest; do
    FILTERS+=("-only-testing:Latest Tests/$suite")
  done
fi

# Benchmarks have dedicated Release runners. Never pick them up from a stale flag file.
FILTERS+=(
  "-skip-testing:Latest Tests/MigrationPerformanceTest"
  "-skip-testing:Latest Tests/MigrationFrameCadenceTest"
  "-skip-testing:Latest Tests/ComplexityBenchmarkTest/testComplexityBenchmarks"
)
echo "Running $MODE tests (coverage=$COVERAGE)"

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
  -enableCodeCoverage "$COVERAGE" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 120 \
  "${FILTERS[@]}" \
  test
