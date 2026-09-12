# Latest

A macOS utility that finds updates for App Store, Sparkle, and Homebrew applications. This independently maintained fork by [ertyoii](https://github.com/Ertyoii) targets macOS 26+ and is built from source.

![Latest](latest.png)

## Build

Requires macOS 26, Xcode 26.6, and `ripgrep`.

```sh
brew install ripgrep
./script/build_and_run.sh
```

Open `Latest.xcodeproj` and use the `Latest` scheme to work in Xcode. Run the architecture, behavior, and visual checks with:

```sh
./script/test.sh
```

Run the opt-in performance suites with:

```sh
./script/benchmark_complexity.sh
./script/benchmark_migration.sh current
```

These use optimized Release builds with testability enabled and coverage disabled.
Small workloads collect 30 samples; scrolling and repeated selection collect more.
The migration report includes cold, disk-cache, and memory-cache selection through
SwiftUI, the real release-notes provider, and the rendered text view, plus resident
memory and live heap bytes/blocks. Cold means an empty application cache with
embedded HTML, not a cold OS filesystem cache or a live network request.
The sleeping-task scheduler fixture and immediate-provider selection fixture remain
separate from the full selection-to-render measurements. The overlap fixture
measures generation acceptance and store writes under concurrent refreshes.
Compare results only under the same build configuration, hardware, and workload;
Debug measurements are not a Release baseline. Live heap deltas are retained
allocations, not total allocation churn or peak memory.

GitHub CI is optional for local development. The existing workflow runs the checks on a clean macOS runner, including exact visual comparisons with a fixed reference. Keep it enabled for independent regression checks; it is not needed to launch the app locally.

The app's release menu opens this fork's GitHub releases. It does not use the original project's automatic update feed. Automatic self-updates require a separately configured, signed appcast for this fork.

## Architecture

- `Latest/App`: application assembly and lifecycle
- `Latest/Features`: SwiftUI presentation and feature state
- `Latest/Domain`: framework-independent models and version rules
- `Latest/Services`: discovery, update orchestration, and release notes
- `Latest/Platform`: AppKit, App Store, Sparkle, and install-helper integrations
- `Latest/Support`: shared infrastructure and presentation helpers

Dependencies are assembled in `AppEnvironment`. Features use the `AppUpdating` boundary instead of update queue implementations. The shipping sidebar is `UpdatesTableBridge`; its AppKit behavior and geometry are intentional.

Sparkle is pinned through Swift Package Manager. `Frameworks/CommerceKit` and `Frameworks/StoreFoundation` are required for App Store integration.

`UpdateInstaller` is a separate privileged helper target that installs App Store update packages and writes their receipts. The main app communicates with it over XPC. `Frameworks` contains headers and module maps for the macOS App Store frameworks; both folders are required by the current implementation.

## Swift formatting

Use the Swift toolchain's `swift-format` through Xcode (`xcrun swift-format`). The checked-in `.swift-format` records the defaults from version 6.3.0: two-space indentation, a 100-column line-length target, sorted imports, and trailing commas in multiline collections. Multiline string contents are not reflowed.

```sh
./script/format.sh         # Format all tracked project Swift files
./script/format.sh --check # Verify formatting without changing files
```

The scope includes the app, tests, installer helper, and Swift scripts. Generated files and downloaded dependencies are excluded. The check compares formatter output; broader naming and refactoring lint rules are separate from formatting. Use the same Xcode toolchain for reproducible results.

## License

Based on [Latest by Max Langer and contributors](https://github.com/mangerlahn/Latest). Thank you to the original authors for making this project available.

Fork development and modifications © 2026 ertyoii. This modified version includes changes through September 6, 2026. Existing upstream and third-party copyright notices are retained; Git history records individual contributions. File creation credit does not imply sole authorship of derived code.

Distributed under GNU GPL version 3; see [LICENSE.md](LICENSE.md). When distributing binaries, provide the corresponding source under the GPL. This software comes without warranty. Dependency notices are included in the app's About credits.
