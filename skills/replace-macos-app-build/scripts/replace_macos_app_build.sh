#!/usr/bin/env bash
set -euo pipefail

PROJECT=""
SCHEME=""
CONFIGURATION="Debug"
DERIVED_DATA="build/DerivedData"
APP_NAME=""
INSTALL_NAME=""
BUNDLE_ID=""
CODE_SIGNING_ALLOWED_VALUE="NO"
CLEAN_ARTIFACTS=0
RESTART_DOCK=0
OPEN_APP=0
DRY_RUN=0
ARTIFACT_NAMES=()

usage() {
  cat <<'USAGE'
Usage:
  replace_macos_app_build.sh --project App.xcodeproj --scheme Scheme --app-name "App Dev" [options]

Options:
  --project PATH          Xcode project to build.
  --scheme NAME           Xcode scheme to build.
  --configuration NAME    Build configuration. Default: Debug.
  --derived-data PATH     DerivedData output. Default: build/DerivedData.
  --app-name NAME         Built app product name without .app.
  --install-name NAME     Installed app name in /Applications. Defaults to --app-name.
  --bundle-id ID          Expected bundle id. If omitted, read from built Info.plist.
  --artifact-name NAME    Extra stale .app product name to clean. Repeatable.
  --code-signing VALUE    CODE_SIGNING_ALLOWED value. Default: NO.
  --clean-artifacts       Remove stale duplicate app bundles from build/ and Xcode DerivedData.
  --restart-dock          Restart Dock after registration.
  --open                  Open the installed app after replacement.
  --dry-run               Print destructive/copy commands without executing them.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --scheme) SCHEME="$2"; shift 2 ;;
    --configuration) CONFIGURATION="$2"; shift 2 ;;
    --derived-data) DERIVED_DATA="$2"; shift 2 ;;
    --app-name) APP_NAME="$2"; shift 2 ;;
    --install-name) INSTALL_NAME="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --artifact-name) ARTIFACT_NAMES+=("$2"); shift 2 ;;
    --code-signing) CODE_SIGNING_ALLOWED_VALUE="$2"; shift 2 ;;
    --clean-artifacts) CLEAN_ARTIFACTS=1; shift ;;
    --restart-dock) RESTART_DOCK=1; shift ;;
    --open) OPEN_APP=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$PROJECT" || -z "$SCHEME" || -z "$APP_NAME" ]]; then
  usage >&2
  exit 2
fi

if [[ -z "$INSTALL_NAME" ]]; then
  INSTALL_NAME="$APP_NAME"
fi

ARTIFACT_NAMES+=("$APP_NAME")
if [[ "$INSTALL_NAME" != "$APP_NAME" ]]; then
  ARTIFACT_NAMES+=("$INSTALL_NAME")
fi

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

PROJECT_ROOT="$(pwd)"
BUILT_APP="$PROJECT_ROOT/$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
INSTALLED_APP="/Applications/$INSTALL_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "Building $SCHEME ($CONFIGURATION)..."
run xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED_VALUE"

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Built app not found: $BUILT_APP" >&2
  exit 1
fi

if [[ -z "$BUNDLE_ID" ]]; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT_APP/Contents/Info.plist")"
fi

MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUILT_APP/Contents/Info.plist")"

echo "Built app: $BUILT_APP"
echo "Install target: $INSTALLED_APP"
echo "Bundle id: $BUNDLE_ID"
echo "Version: $MARKETING_VERSION ($BUILD_VERSION)"

if [[ "$DRY_RUN" -eq 0 ]]; then
  if [[ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null || true)" == "true" ]]; then
    echo "Quitting running app..."
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in {1..50}; do
      if [[ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null || true)" != "true" ]]; then
        break
      fi
      sleep 0.2
    done
  fi
else
  echo "[dry-run] would quit running app with bundle id $BUNDLE_ID before replacement"
fi

echo "Replacing installed app..."
run rsync -a --delete "$BUILT_APP/" "$INSTALLED_APP/"

echo "Registering LaunchServices and Spotlight..."
run "$LSREGISTER" -f -R -trusted "$INSTALLED_APP"
run mdimport "$INSTALLED_APP"

if [[ "$CLEAN_ARTIFACTS" -eq 1 ]]; then
  echo "Cleaning stale duplicate app bundles..."
  while IFS= read -r -d '' candidate; do
    case "$candidate" in
      "$BUILT_APP"|"$INSTALLED_APP") continue ;;
    esac
    echo "Removing $candidate"
    run rm -rf "$candidate"
  done < <(
    for artifact_name in "${ARTIFACT_NAMES[@]}"; do
      find "$PROJECT_ROOT/build" -name "$artifact_name.app" -type d -print0 2>/dev/null || true
      find "$HOME/Library/Developer/Xcode/DerivedData" -name "$artifact_name.app" -type d -print0 2>/dev/null || true
    done
  )
fi

if [[ "$RESTART_DOCK" -eq 1 ]]; then
  echo "Restarting Dock..."
  run killall Dock
fi

if [[ "$OPEN_APP" -eq 1 ]]; then
  echo "Opening installed app..."
  run open -a "$INSTALLED_APP"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  echo "Verifying LaunchServices..."
  osascript -e "POSIX path of (path to app id \"$BUNDLE_ID\")"
fi
