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

## License

See [LICENSE.md](LICENSE.md).
