# Latest

A macOS utility that finds updates for App Store, Sparkle, and Homebrew applications. This fork is maintained by [ertyoii](https://github.com/Ertyoii) and targets macOS 26+.

![Latest](latest.png)

## Development

Requires Xcode 26.5 or later and `ripgrep`. Development and CI use `master`; CI uses Xcode 26.6. Open the `Latest` scheme in `Latest.xcodeproj`, or run:

```sh
brew install ripgrep
./script/build_and_run.sh
./script/test.sh
./script/format.sh --check
```

`build_and_run.sh --help` lists launch, debugger, and logging options. Add `--signed` after a mode for an Apple Development build; the App Store installation helper requires the app and helper to share a valid signing identity.

`test.sh` runs script regressions, architecture checks, offline behavior, and offscreen layout tests in a background host. Use `-only-testing:'Latest Tests/Class/method'` to focus XCTest. Coverage is opt-in with `--coverage`; run `./script/format.sh` to apply the pinned formatting rules with your Xcode toolchain.

`./script/test.sh --ui` runs window, input, accessibility, and screenshot checks and may take focus. `--all` includes both lanes. Benchmarks and live catalog audits have separate commands. For another host OS, see [testing on macOS 26](docs/macos26-testing.md).

## Reading the code

The [development guide](docs/Development.md) gives a reading order, design rationale, and links to Swift and SwiftUI guidance.

| Directory | Responsibility |
| --- | --- |
| `Latest/App` | Assembly, scenes, commands, and lifecycle |
| `Latest/Domain` | Immutable app metadata and version rules |
| `Latest/Features` | SwiftUI presentation and feature state |
| `Latest/Services` | Discovery, update checking, and release notes |
| `Latest/Platform` | AppKit, WebKit compatibility, update sources, and installers |
| `Latest/Support` | Preferences, presentation helpers, and shared infrastructure |
| `Tests` | Behavior, integration, visual, and performance contracts |
| `script` | Local build, validation, measurement, and audit commands |

SwiftUI owns the scenes, search, rows, settings, and detail controls. macOS 26 and 27 share `UpdatesScrollList`, including row geometry, selection, keyboard navigation, and context menus. A small AppKit bridge configures overlay scroll indicators and disables edge bounce. Release notes use WebKit for text selection and scrolling; native services and window hooks remain at platform boundaries.

Discovery publishes complete scans so rows appear in their final order. Refresh keeps the previous list and selection visible. Keyboard selection updates the detail header immediately and waits for selection to settle before hashing and loading notes; mouse selection loads notes immediately.

## Updating applications

Features call `AppUpdating`; platform adapters own the update mechanism. Sparkle is pinned through Swift Package Manager. Native Mac App Store apps update within Latest; macOS 26.1+ uses a privileged helper. Wrapped iOS apps open the App Store. Helper registration errors are displayed, and pending updates can resume after System Settings approval.

Signed standalone bundle replacement supports Docker Desktop, Telegram Desktop, Zed, Chrome, Bruno, Discord, 1Password, and Delta. Homebrew downloads require the expected bundle identifier and cask. Each install fetches fresh metadata, verifies available checksums, signing identity, architecture, and minimum OS, and keeps the original until replacement succeeds. Running apps require confirmation to quit and reopen; package installers and companion services use separate paths.

Obsidian's installed version comes from its ASAR payload; Delta's comes from executable metadata. Obsidian public payload updates verify the vendor checksum and RSA signature. Early-access preferences are respected: authenticated updates open Obsidian, and incompatible launchers open the official installer page. Ghostty uses its official Sparkle feed.

## Release notes

`Latest/Resources/LatestReleaseNotes.json` supplies version-matched offline Latest Dev notes. The release menu opens this fork's GitHub releases; automatic self-updates require a separately configured signed appcast.

Notes can load even if update checking fails. A failed or metadata-only source falls back to the vendor catalog. Notes target the available update or installed version; broad-version and latest-section fallbacks retain a degraded quality rating. Preparation, display, and new cache entries share immutable semantic text; older RTF caches use a narrow compatibility reader.

```sh
./script/audit_release_notes.sh
./script/audit_release_notes.sh --installed
./script/audit_release_notes.sh --catalog /path/to/cask.json
```

The default audit is offline. Live audits save reports and HTML under `build/` and use an isolated cache. `audit_release_note_coverage.sh` checks source routes, not whether the remote notes are usable.

## Performance and visual checks

```sh
./script/benchmark_complexity.sh
./script/benchmark_app.sh current
```

Optional Release benchmarks measure data processing, startup, selection, release notes, and memory. Compare results on the same hardware and workload. Reports and test output go under `build/`.

The UI lane checks keyboard navigation, focus, selection, scrolling, accessibility, and appearance. Performance measurements supplement these behavior checks.

Visual tests capture the production window with offline data at a fixed position and inactive state. Images in `build/production-visuals/main-window-scene` compare pixel-for-pixel with same-host originals in `build/production-visual-reference/main-window-scene`; the test skips explicitly when originals are absent. Preserve those originals and their provenance. The macOS 26 [component references](Tests/VisualBaselines/macos-26/README.md) are checked in separately.

Build products, logs, and captures can be regenerated. Keep visual references and any configured macOS 26 VM when cleaning `build/`.

## License

Based on [Latest by Max Langer and contributors](https://github.com/mangerlahn/Latest). Fork modifications © 2026 ertyoii; upstream and dependency notices are retained. Full GPL and Sparkle notices are available offline in Help → Licenses.

Distributed under [GPL version 3](LICENSE.md). Binary distributions must include corresponding source. This software comes without warranty.
