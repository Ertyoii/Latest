#!/usr/bin/env bash
set -euo pipefail

LABEL="${1:-current}"
if [[ ! "$LABEL" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Label must contain only letters, numbers, underscores, or hyphens." >&2
  exit 2
fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/build/frame-benchmark-$LABEL-$(date +%Y%m%d-%H%M%S)"
FLAG="$ROOT_DIR/build/run-frame-benchmark"
mkdir -p "$OUTPUT" "$ROOT_DIR/build/ModuleCache"
if ! (set -C; printf '%s\n' "$OUTPUT" > "$FLAG") 2>/dev/null; then
  echo "Another frame benchmark is active: $FLAG" >&2
  exit 2
fi
trap 'rm -f "$FLAG"' EXIT
git -C "$ROOT_DIR" rev-parse HEAD > "$OUTPUT/revision.txt"
git -C "$ROOT_DIR" status --short >> "$OUTPUT/revision.txt"
git -C "$ROOT_DIR" diff --binary -- Latest Latest.xcodeproj Tests script > "$OUTPUT/changes.patch"
mkdir -p "$OUTPUT/method"
cp "$ROOT_DIR/Tests/Migration/MigrationFrameCadenceTest.swift" \
  "$ROOT_DIR/script/analyze_frame_benchmark.py" "$ROOT_DIR/script/benchmark_frames.sh" "$OUTPUT/method/"
shasum -a 256 "$ROOT_DIR/Latest/Platform/AppKit/UpdatesTableSupport.swift" \
  "$ROOT_DIR/Latest/Platform/AppKit/UpdatesTableBridge.swift" \
  "$ROOT_DIR/Latest/Features/Updates/UpdatesScrollList.swift" \
  "$ROOT_DIR/Tests/Migration/SidebarInputFixture.swift" \
  "$ROOT_DIR/Tests/App/AppFixtures.swift" \
  "$ROOT_DIR/Latest/Features/Updates/UpdateRowView.swift" \
  "$ROOT_DIR/Latest/Features/ReleaseNotes/ReleaseNotesDetailViewModel.swift" "$OUTPUT"/method/* > "$OUTPUT/sources.sha256"
sw_vers > "$OUTPUT/environment.txt"
xcodebuild -version >> "$OUTPUT/environment.txt"
uname -m >> "$OUTPUT/environment.txt"
echo "When the test window appears, click its titlebar if macOS leaves it inactive."
echo "Measurement starts only when focused; keep the window unobstructed until it closes."

# Build once; fast/slow held-key trials, warmup, and controls share one process.
# Keep the display awake and leave the benchmark window unobstructed.
caffeinate -d -i -u xcodebuild \
  -project "$ROOT_DIR/Latest.xcodeproj" -scheme Latest -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$ROOT_DIR/build/DerivedData" \
  -resultBundlePath "$OUTPUT/tests.xcresult" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CLANG_MODULE_CACHE_PATH="$ROOT_DIR/build/ModuleCache" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  -enableCodeCoverage NO ENABLE_TESTABILITY=YES \
  -only-testing:'Latest Tests/MigrationFrameCadenceTest/testHeldArrowPresentationCadence' \
  test > "$OUTPUT/test.log" 2>&1 || {
    tail -60 "$OUTPUT/test.log"
    exit 1
  }
if [[ ! -f "$OUTPUT/raw.json" ]]; then
  echo "No measurement was produced; inspect $OUTPUT/test.log (the test may have skipped)." >&2
  exit 1
fi
/usr/bin/python3 "$ROOT_DIR/script/analyze_frame_benchmark.py" "$OUTPUT/raw.json"
