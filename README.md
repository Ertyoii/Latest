# Latest

A macOS utility that finds updates for App Store, Sparkle, and Homebrew applications. This fork targets macOS 26+ and is built from source.

![Latest](latest.png)

## Build

Requires macOS 26, Xcode 26.6, and `ripgrep`.

```sh
brew install ripgrep
./script/build_and_run.sh
```

Open `Latest.xcodeproj` and use the `Latest` scheme to work in Xcode. Run all architecture, behavior, performance, and visual checks with:

```sh
./script/test.sh
```

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

See [LICENSE.md](LICENSE.md).
