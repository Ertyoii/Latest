---
name: replace-macos-app-build
description: Build and install the latest local macOS app bundle into /Applications, make Spotlight/LaunchServices/Dock resolve to that installed bundle, and clean stale duplicate .app build artifacts. Use when a user asks to replace the Spotlight or Dock app with the newest local build, update /Applications/SomeApp.app from an Xcode build, remove old DerivedData/build app copies, or make macOS launch the installed app instead of a debug artifact.
---

# Replace macOS App Build

## Quick Start

Use `scripts/replace_macos_app_build.sh` for the fragile filesystem and LaunchServices work instead of hand-writing ad hoc commands.

From the app repo:

```bash
skills/replace-macos-app-build/scripts/replace_macos_app_build.sh \
  --project Latest.xcodeproj \
  --scheme Latest \
  --configuration Debug \
  --derived-data build/DerivedData \
  --app-name "Latest Dev" \
  --install-name "Latest Dev" \
  --artifact-name "Latest" \
  --clean-artifacts \
  --open
```

## Workflow

1. Confirm the app identity before replacing anything:
   - Source build bundle path.
   - Installed `/Applications/<install-name>.app` path.
   - `CFBundleIdentifier`, `CFBundleShortVersionString`, `CFBundleVersion`, and executable name.

2. Build the app:
   - Use `xcodebuild build`.
   - Prefer a project-local DerivedData path such as `build/DerivedData`.
   - Use `CODE_SIGNING_ALLOWED=NO` for local debug replacement unless the user explicitly needs signed distribution behavior.

3. Replace the installed app:
   - Copy from the built product to `/Applications/<install-name>.app` with `rsync -a --delete`.
   - Do not remove unrelated apps.

4. Refresh macOS app resolution:
   - Register the installed app with LaunchServices using `lsregister -f -R -trusted`.
   - Run `mdimport` on the installed app so Spotlight re-indexes metadata.
   - If the user specifically wants Dock cleanup or the Dock still points at a stale app, restart Dock with `killall Dock`; otherwise avoid disturbing Dock.
   - Open the installed app when requested so the running Dock icon resolves to `/Applications`.

5. Clean stale artifacts:
  - Remove duplicate build products with the exact app name under repo-local `build/` and `~/Library/Developer/Xcode/DerivedData`.
   - Use repeated `--artifact-name` values for old product names that should also be removed, such as a prior `Latest.app` after switching to `Latest Dev.app`.
   - Preserve the fresh build product used for installation unless the caller explicitly cleans all build output.
   - Never delete `/Applications/<install-name>.app` during cleanup.

6. Verify:
   - `osascript -e 'POSIX path of (path to app id "<bundle-id>")'` should resolve to `/Applications/<install-name>.app/`.
   - `osascript -e 'tell application id "<bundle-id>" to version'` should report the new marketing version after launch.
   - The installed `Info.plist` should show the expected version/build.

## Notes

- If Spotlight metadata commands briefly report “could not find” immediately after `mdimport`, trust filesystem plus LaunchServices checks first and mention Spotlight may lag.
- If there is no persistent Dock item for the app, there is no Dock plist entry to rewrite; launching the installed bundle is enough for the running Dock icon.
- If multiple matching app bundles exist, enumerate them first and keep `/Applications` as the source of truth.
