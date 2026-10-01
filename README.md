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

Run `./script/format.sh` to format Swift sources. Use the same Xcode toolchain for reproducible output; `.swift-format` defines the formatting rules.

## Architecture and SwiftUI migration

- `Latest/App`: assembly and lifecycle through `AppEnvironment`
- `Latest/Features`: SwiftUI presentation and feature state
- `Latest/Domain`: framework-independent models and version rules
- `Latest/Services`: discovery, updates, and release notes
- `Latest/Platform`: AppKit, App Store, Sparkle, and installer integrations
- `Latest/Support`: shared infrastructure and presentation helpers

Search, section headings, app rows, progress/error controls, and detail action buttons use SwiftUI. `UpdatesTableBridge` retains native table selection, scrolling, pinned headers, menus, and accessibility. Release notes use WebKit inside a SwiftUI container; window access remains AppKit.

Arrow navigation commits selection and scrolling together, keeping rows contiguous. The detail header follows immediately; notes load after keyboard selection settles. Mouse selection loads notes immediately.

Features depend on `AppUpdating`. Sparkle is pinned through Swift Package Manager. `UpdateInstaller` and the headers/module maps in `Frameworks` are required for App Store updates over XPC.

## Performance checks

```sh
./script/benchmark_complexity.sh
./script/benchmark_migration.sh current
./script/benchmark_frames.sh current
```

These use Release builds without coverage. Compare runs on the same hardware and workload. The frame benchmark captures a visible production window with 300 offline apps, tests held arrows at system repeat/30/60 keys per second, and saves measurements and reports under `build/`. Keep its window focused and unobstructed.

Native row steps follow the keyboard repeat rate. About 60 changed frames per second was measured with 60 keys per second on a 60 Hz display; ordinary held keys do not produce continuous 60 FPS motion. The strict one-frame input-delay gate remains unmet. Benchmark exit failures must be investigated; 120 Hz presentation has not been verified.

## Release notes

Add each app version to `Latest/Resources/LatestReleaseNotes.json` for offline Latest Dev notes. The release menu opens this fork's GitHub releases; automatic self-updates require a separately configured signed appcast.

`./script/audit_release_notes.sh` runs offline regression tests. Add `--catalog /path/to/cask.json` for a live Homebrew catalog audit, or `--installed` for installed apps. Reports and rendered HTML go under `build/`. `audit_release_note_coverage.sh` checks source routes, which do not guarantee usable notes.

## License

Based on [Latest by Max Langer and contributors](https://github.com/mangerlahn/Latest). Fork modifications © 2026 ertyoii; upstream and dependency notices are retained.

Distributed under [GPL version 3](LICENSE.md). Binary distributions must include corresponding source. This software comes without warranty.
