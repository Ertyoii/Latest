#!/usr/bin/env bash
set -euo pipefail

PROJECT="Latest.xcodeproj"
SCHEME="Latest"
CONFIGURATION="Debug"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
RESULT_BUNDLE="$BUILD_DIR/Latest-ReleaseNotes-Audit-$(date +%Y%m%d-%H%M%S).xcresult"
AUDIT_REPORT="$BUILD_DIR/release-notes-audit.txt"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

echo "Offline release-note fixture audit:"
echo "- AppCleaner: multi-release HTML is trimmed to the current version"
echo "- BetterDisplay-style blanks: empty output is rejected"
echo "- Bruno/Rectangle/Obsidian: version-only and link-only stubs are rejected or followed"
echo "- Cursor: plain-text and compact Sparkle changelog line breaks are preserved"
echo "- IINA: duplicate leading version titles are collapsed"
echo "- Notion-style website chrome is rejected instead of rendered"
echo "- Thunder-style binary/mojibake payloads and downloadable URLs are rejected"
echo "- CodexBar: markdown headings and bullets still render cleanly"
echo "- Installed-app audit: every discoverable app is checked through Latest's update and release-note pipeline"

only_testing=(
  "Latest Tests/VersionParserTest/testMarkdownReleaseNotesAreRenderedAsRichTextLists"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupKeepsOnlyRelevantVersionSection"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupKeepsOnlyCurrentReleaseFromHTMLHistory"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupRejectsVersionOnlyAndLinkOnlyText"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupPreservesPlainTextChangelogLineBreaks"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupSeparatesCompactedSparkleChangelogText"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupDeduplicatesRepeatedLeadingVersionTitle"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupRejectsNavigationPageNoise"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupRejectsMojibakeText"
  "Latest Tests/VersionParserTest/testReleaseNotesProviderRejectsDownloadLikeReleaseNotesURL"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupSeparatesHTMLChangelogHeadings"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupExtractsFirstSectionFromVersionlessChangelog"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupStopsCursorSectionAtNextDatedEntry"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupSkipsVersionNavigationWhenFindingRelevantSection"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupIgnoresZedReactServerDescriptionReference"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupExtractsZedReleasePayloadBeforeVersionNavigation"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupExtractsRelevantSectionFromHTMLWithoutRendering"
  "Latest Tests/VersionParserTest/testReleaseNotesMarkupExtractsFirstReleaseNotesURLFromStubText"
  "Latest Tests/ReleaseNotesAuditTest/testInstalledApplicationReleaseNotesAudit"
)

xcode_args=(
  -project "$ROOT_DIR/$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "platform=macOS"
  -derivedDataPath "$DERIVED_DATA"
  -resultBundlePath "$RESULT_BUNDLE"
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
  OTHER_SWIFT_FLAGS="-DLATEST_RELEASE_NOTES_AUDIT"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=""
)

for test_name in "${only_testing[@]}"; do
  xcode_args+=("-only-testing:$test_name")
done

xcodebuild "${xcode_args[@]}" test

echo
echo "Installed-app release-note audit report:"
cat "$AUDIT_REPORT"
