#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
MODE="fast"
RUN_INSTALLED_AUDIT=false
HOMEBREW_CASK_CATALOG=""

usage() {
  cat <<'EOF'
usage: script/evaluate_optimization.sh [--full] [--installed] [--homebrew-cask PATH|-]

Fast mode runs focused release-note tests plus Release artifact/security checks.
Full mode also runs the complete test suite, complexity budgets, and the
shipping AppKit parity sidebar through latency, memory, and runtime-warning gates.
EOF
}

while (($#)); do
  case "$1" in
    --full)
      MODE="full"
      shift
      ;;
    --installed)
      RUN_INSTALLED_AUDIT=true
      shift
      ;;
    --homebrew-cask)
      if (($# < 2)); then
        echo "error: --homebrew-cask requires a path or -" >&2
        usage >&2
        exit 2
      fi
      HOMEBREW_CASK_CATALOG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

audit_arguments=()
if [[ "$RUN_INSTALLED_AUDIT" == true ]]; then
  audit_arguments+=(--installed)
fi
if [[ -n "$HOMEBREW_CASK_CATALOG" ]]; then
  audit_arguments+=(--homebrew-cask "$HOMEBREW_CASK_CATALOG")
fi

echo "EVALUATION phase=release_notes mode=$MODE"
if [[ "$RUN_INSTALLED_AUDIT" == true || -n "$HOMEBREW_CASK_CATALOG" ]]; then
  "$ROOT_DIR/script/audit_release_notes.sh" "${audit_arguments[@]}"
else
  "$ROOT_DIR/script/audit_release_notes.sh"
fi

echo
echo "EVALUATION phase=catalog_and_plist_validation"
jq empty "$ROOT_DIR/Latest/Resources/ReleaseNotesSources.json"
plutil -lint "$ROOT_DIR/Latest/Resources/Info.plist"

if [[ "$MODE" == "full" ]]; then
  echo
  echo "EVALUATION phase=complete_test_suite"
  "$ROOT_DIR/script/test.sh"

  echo
  echo "EVALUATION phase=complexity_budgets"
  "$ROOT_DIR/script/benchmark_complexity.sh"

	echo
	echo "EVALUATION phase=appkit_sidebar_latency_memory_and_runtime_gates"
	"$ROOT_DIR/script/benchmark_migration.sh" "evaluation-appkit" appkit
fi

echo
echo "EVALUATION phase=release_build"
xcodebuild \
  -project "$ROOT_DIR/Latest.xcodeproj" \
  -scheme Latest \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CLANG_COVERAGE_MAPPING=NO \
  ENABLE_CODE_COVERAGE=NO \
  build

echo
echo "EVALUATION phase=release_artifact"
"$ROOT_DIR/script/audit_release_artifact.sh" "$DERIVED_DATA/Build/Products/Release/Latest Dev.app"

echo
echo "EVALUATION RESULT pass mode=$MODE"
