# Latest

A macOS utility that finds updates for App Store, Sparkle, and Homebrew applications. This fork is maintained by [ertyoii](https://github.com/Ertyoii) and targets macOS 26+.

![Latest](latest.png)

## Development

Requires Xcode 26.6 or later and `ripgrep`. Use the `Latest` scheme in `Latest.xcodeproj`, or run:

```sh
brew install ripgrep
./script/build_and_run.sh
./script/test.sh
./script/format.sh --check
```

`test.sh` checks architecture, behavior, and visual regressions. CI also compares reviewed macOS 26 references in [Tests/VisualBaselines](Tests/VisualBaselines/macos-26/README.md). Compare UI changes with the original on the same system before updating a reference.

Full-window tests open the production SwiftUI scene with offline data. They save settled native window captures under `build/production-visuals/main-window-scene` and compare every pixel when same-host original captures exist in `build/production-visual-reference/main-window-scene`. The gallery references cover component scenarios; they do not represent the complete production window.

Run `./script/format.sh` to format Swift sources. Use the same Xcode toolchain for reproducible output; `.swift-format` defines the formatting rules.

## Architecture and SwiftUI migration

- `Latest/App`: assembly and lifecycle through `AppEnvironment`
- `Latest/Features`: SwiftUI presentation and feature state
- `Latest/Domain`: framework-independent models and version rules
- `Latest/Services`: discovery, updates, and release notes
- `Latest/Platform`: AppKit, App Store, Sparkle, and installer integrations
- `Latest/Support`: shared infrastructure and presentation helpers

Search, section headings, app rows, progress/error controls, and detail action buttons use SwiftUI. On macOS 27 with the macOS 27 SDK, `UpdatesScrollList` also owns selection, scrolling, pinned headings, context menus, swipe actions, and accessibility. macOS 26 and Xcode 26 builds retain `UpdatesTableBridge`, because SwiftUI's custom-scroll swipe container requires macOS 27. Release notes use WebKit inside a SwiftUI container. SwiftUI controls the main window's toolbar chrome; `WindowAccessor` only preserves helper-alert suppression choices on Cancel and Escape.

Release-note preparation, display and new cache entries share immutable semantic text runs. Existing RTF caches and legacy vendor encodings are decoded through a narrow AppKit compatibility reader.

Application-wide appearance, system icons, Finder actions and Dock badges retain narrow AppKit integrations. A window's `preferredColorScheme` does not apply the app's chosen appearance to every native panel. The SwiftUI sidebar preserves the original 60-point rows, 27-point headings, and content alignment. Its inactive selection uses a different system gray, accepted for this migration; subtle dark heading compositing and icon edge differences remain. Original full-window references remain intact, so strict pixel checks report these differences.

Arrow navigation commits selection and scrolling together, keeping rows contiguous. The detail header follows immediately; notes load after keyboard selection settles. Mouse selection loads notes immediately.

Features depend on `AppUpdating`. Sparkle is pinned through Swift Package Manager. Native Mac App Store apps update within Latest; on macOS 26.1 and newer a privileged helper installs the App Store package. Wrapped iOS apps use the native App Store. Helper registration errors are shown, and a pending update resumes after approval in System Settings. The app and embedded helper must share a valid signing identity; use `./script/build_and_run.sh --verify --signed` for a signed local build. Unsigned test builds can run but cannot enable the helper.

## Performance checks

```sh
./script/benchmark_complexity.sh
./script/benchmark_migration.sh current
./script/benchmark_frames.sh current
```

These use Release builds without coverage. Compare runs on the same hardware and workload. The frame benchmark opens the production SwiftUI window scene with 300 offline apps, tests held arrows at system repeat/30/60 keys per second, and saves measurements and reports under `build/`. Its calibration overlay preserves the hosting view and keyboard responder. The fixture is a load test; use the live app for ordinary visual and input acceptance. Keep the benchmark window focused and unobstructed.

On macOS 27, the same 1,500-app production-window workload measured keyboard rendering p95 at about 29 ms for the SwiftUI sidebar and 15 ms for the retained native renderer. Both exceed the 8.33 ms target. Scrolling, startup, detail rendering, and memory growth passed their respective CPU/memory budgets. In a valid 300-app frame capture on a 60 Hz display, SwiftUI delivered all queued arrows but presented about 30–33 distinct row changes per second at 60 keys per second. Headers stayed fixed, with no selection bounce or unintended reversals. The smoothness and strict one-frame input-delay gates remain unmet; 120 Hz presentation has not been verified. Preserve failing benchmark results rather than treating a moving selection as a smoothness pass.

## Release notes

Add each app version to `Latest/Resources/LatestReleaseNotes.json` for offline Latest Dev notes. The release menu opens this fork's GitHub releases; automatic self-updates require a separately configured signed appcast.

`./script/audit_release_notes.sh` runs offline regression tests. Add `--catalog /path/to/cask.json` for a live Homebrew catalog audit, or `--installed` for installed apps. Reports and rendered HTML go under `build/`. `audit_release_note_coverage.sh` checks source routes, which do not guarantee usable notes.

## License

Based on [Latest by Max Langer and contributors](https://github.com/mangerlahn/Latest). Fork modifications © 2026 ertyoii; upstream and dependency notices are retained.

Distributed under [GPL version 3](LICENSE.md). Binary distributions must include corresponding source. This software comes without warranty.
