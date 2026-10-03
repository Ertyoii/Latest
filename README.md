# Latest

A macOS utility that finds updates for App Store, Sparkle, and Homebrew applications. This fork is maintained by [ertyoii](https://github.com/Ertyoii) and targets macOS 26+.

![Latest](latest.png)

## Development

Development and CI use `master`. Requires Xcode 26.6 or later and `ripgrep`.
Use the `Latest` scheme in `Latest.xcodeproj`, or run:

```sh
brew install ripgrep
./script/build_and_run.sh
./script/test.sh
./script/format.sh --check
```

`test.sh` runs offline behavior, architecture, and offscreen layout checks in a background test host, with coverage disabled. It does not activate Latest or open test windows. Add `--coverage` when measuring coverage; use `-only-testing:'Latest Tests/Class/method'` for a focused check.

`./script/test.sh --ui` opts into native window, mouse/keyboard, accessibility, and screenshot checks; these can take focus. `--all` runs both lanes and is used by CI on its dedicated macOS 26 desktop with Xcode 26.6. Individual tests have a 90-second default timeout and a 180-second maximum. CI caches the pinned package downloads and uploads test results and production window captures. Benchmarks and live catalog audits keep their separate scripts and never run as part of these commands.

Sidebar visual tests open `LatestMainWindowScene` with offline data and inspect/crop its actual rows, using the renderer selected by the current OS. Full-window captures go under `build/production-visuals/main-window-scene`. When same-host original captures exist in `build/production-visual-reference/main-window-scene`, every pixel is compared; existing mismatches remain failures, and absent references do not establish parity. The 14 macOS 26 [component references](Tests/VisualBaselines/macos-26/README.md) retain production detail, locations, update-action, and toolbar coverage. The old gallery’s independent sidebar implementation has been removed; its historical sidebar pixels remain excluded from detail comparisons. Compare UI changes with the original on the same system before updating a reference.

Run `./script/format.sh` to format Swift sources. Use the same Xcode toolchain for reproducible output; `.swift-format` defines the formatting rules.

### Testing macOS 26 locally

The host OS controls native appearance; selecting Xcode 26 on macOS 27 does not
reproduce macOS 26. On an Apple Silicon Mac, use a [Tart VM](https://tart.run/quick-start/):

```sh
brew install cirruslabs/cli/tart
./script/macos26_vm.sh setup
./script/macos26_vm.sh run
```

The VM and downloads stay under `build/macos26-vm`. Its public image includes
Xcode 26.5 and downloads about 70 GB compressed; it can exercise the macOS 26
renderer, while CI remains the exact Xcode 26.6 gate. Set `LATEST_VM_IMAGE` to a
matching image when one is available. Log in with the image's `admin`/`admin`
account. The host checkout is shared read-only; clone it onto the guest disk:

```sh
git clone --no-hardlinks '/Volumes/My Shared Files/latest' ~/Latest
cd ~/Latest
./script/build_and_run.sh
./script/test.sh --all
cp -R build/production-visuals '/Volumes/My Shared Files/artifacts/'
```

Run the app and UI suite while the VM desktop is unlocked. For an exact compiler
reproduction, install Xcode 26.6 in the guest and set `DEVELOPER_DIR` to its
`Contents/Developer` directory. CI also uploads its real macOS 26 production
window captures with each run's test-results artifact.

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

The macOS 27 keyboard workload still exceeds the 8.33 ms CPU target. Scrolling, startup, detail rendering, and memory growth pass their budgets. Frame captures deliver all queued arrows without selection bounce or unintended reversals, but the smoothness and one-frame input-delay gates remain unmet; 120 Hz presentation has not been verified. Keep failed reports under `build/` and distinguish correct navigation from smooth presentation.

## Release notes

Add each app version to `Latest/Resources/LatestReleaseNotes.json` for offline Latest Dev notes. The release menu opens this fork's GitHub releases; automatic self-updates require a separately configured signed appcast.

`./script/audit_release_notes.sh` runs offline regression tests. Add `--catalog /path/to/cask.json` for a live Homebrew catalog audit, or `--installed` for installed apps. Reports and rendered HTML go under `build/`. `audit_release_note_coverage.sh` checks source routes, which do not guarantee usable notes.

## License

Based on [Latest by Max Langer and contributors](https://github.com/mangerlahn/Latest). Fork modifications © 2026 ertyoii; upstream and dependency notices are retained.

Distributed under [GPL version 3](LICENSE.md). Binary distributions must include corresponding source. This software comes without warranty.
