#!/usr/bin/env bash
set -euo pipefail

# Render an immutable pre-refactor app with the same SDK, display and capture
# harness as the candidate. Never generate references from the candidate app.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REFERENCE_COMMIT=85f3a865255c0473184ac4d476540a0a24a87166
REFERENCE_ROOT="$(mktemp -d /tmp/latest-ci-reference.XXXXXX)"
trap 'git -C "$ROOT_DIR" worktree remove --force "$REFERENCE_ROOT"' EXIT
git -C "$ROOT_DIR" worktree add --detach "$REFERENCE_ROOT" "$REFERENCE_COMMIT"
python3 - "$ROOT_DIR" "$REFERENCE_ROOT" <<'PYTHON'
from pathlib import Path
import json
import re
import sys
root, reference = map(Path, sys.argv[1:])
# The gallery is test harness code too. Copy its active scenarios so retired
# experimental surfaces do not leave unmatched enum cases in the reference.
gallery = Path("Tests/Migration/MigrationGallery.swift")
(reference / gallery).write_bytes((root / gallery).read_bytes())
relative = Path("Tests/Migration/MigrationVisualRegressionTest.swift")
source = (root / relative).read_text().split("/// Captures the shipping composition,")[0]
# Only this disposable original-app harness records without asserting against
# another machine's images. Candidate tests retain every comparison.
source = source.replace("\t\tguard let baselineData =", "\t\treturn\n\t\tguard let baselineData =", 1)
(reference / relative).write_text(source)
lock = Path("Latest.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
(reference / lock).parent.mkdir(parents=True, exist_ok=True)
candidate_lock = json.loads((root / lock).read_text())
candidate_pin = next(
    pin for pin in candidate_lock["pins"] if pin["identity"] == "sparkle"
)

# The historical project predates the checked-in lockfile and declares an
# older exact Sparkle version. Keep the reference renderer on the same package
# version as the candidate so visual differences describe source changes, not
# dependency changes. The reference source remains the immutable commit; this
# only normalizes disposable build inputs in the temporary worktree.
project = reference / "Latest.xcodeproj/project.pbxproj"
project_text = project.read_text()
project_text, replacements = re.subn(
    r'(XCRemoteSwiftPackageReference "Sparkle".*?version = )[^;]+(;)',
    rf"\g<1>{candidate_pin['state']['version']}\g<2>",
    project_text,
    count=1,
    flags=re.S,
)
if replacements != 1:
    raise SystemExit("Could not normalize the reference Sparkle requirement")
project.write_text(project_text)
(reference / lock).write_text(json.dumps(candidate_lock, indent=2) + "\n")
PYTHON
mkdir -p /tmp/latest-visual-output
xcodebuild -project "$REFERENCE_ROOT/Latest.xcodeproj" -scheme Latest \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$REFERENCE_ROOT/build/DerivedData" \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  -only-testing:'Latest Tests/MigrationVisualRegressionTest/testMigrationGalleryRenderedRegions' test
mkdir -p "$ROOT_DIR/build/ci-visual-reference"
cp /tmp/latest-visual-output/*-actual.png "$ROOT_DIR/build/ci-visual-reference/"
python3 - "$ROOT_DIR/build/ci-visual-reference" <<'PYTHON'
from pathlib import Path
import sys
images = list(Path(sys.argv[1]).glob("*-actual.png"))
assert len(images) == 14, f"Expected 14 original-app captures, got {len(images)}"
PYTHON
