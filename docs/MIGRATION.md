# MIGRATION.md — Storyboard/AppKit to SwiftUI Pixel-Parity Remake

Repository: `Ertyoii/Latest`  
Primary branch inspected: `develop`  
Goal: remove the legacy `Main.storyboard` / controller-driven UI and replace it with a modern SwiftUI-based macOS UI while preserving the existing app layout, interactions, visual density, localization behavior, and update functionality.

---

## 1. Objective

This migration is **not** a visual redesign. The target is a pixel-level remake of the current app using a modern SwiftUI-first architecture.

The end state should be:

```text
SwiftUI app lifecycle
  -> SwiftUI main window
      -> SwiftUI split layout
          -> SwiftUI updates sidebar
          -> SwiftUI release notes detail pane
  -> SwiftUI commands/menus where practical
  -> SwiftUI settings window
  -> small AppKit bridges only where they preserve native macOS behavior
```

The app should still feel like the original Latest app. The user should not feel that the UI was replaced by a generic SwiftUI mockup.

---

### Evaluation after repo audit

The overall plan is sound: a parallel SwiftUI implementation behind a flag is the right migration shape for this app. The main adjustments after checking the current repo are:

1. The visible release notes pane is `NSTextView` + `NSAttributedString`, not a live `WKWebView`. WebKit exists in the loading/conversion path, so the first SwiftUI detail pane should bridge the current attributed text rendering rather than switch the visible body to `WKWebView`.
2. `AppProviding.addObserver` currently requires an `NSObject` observer, and `UpdateCheckCoordinator.progressDelegate` is a single weak delegate. SwiftUI view models need an observation adapter or `NSObject` inheritance, and update-check progress should be extracted before both UIs can safely coexist.
3. `Main.storyboard` contained more than the main window: app menu wiring, the main window, settings scenes, localized storyboard strings, and release-note support UI. The active app no longer loads it: menu wiring, main-window creation, settings, release-note header/content, and support-state popover creation are programmatic. Old localized `Main.strings` files may still exist on disk as inert historical artifacts until a cleanup sweep removes or migrates any remaining useful strings.
4. The feature-flag launch path must avoid starting the old controller and the new SwiftUI window at the same time. The old `MainWindowController.windowDidLoad()` currently starts an update check immediately.
5. The project currently targets macOS 26 and Swift 6, so new SwiftUI-only state can use the Observation framework where it helps. Do not let that become a reason to rewrite existing model logic during the first pass.

### Implementation update: main-window parity pass

The first implemented SwiftUI path must preserve the original window geometry during parity verification. Creating a temporary screenshot-only frame such as `1004 x 495` makes the SwiftUI UI look wider than the original app and pollutes the `MainWindowSize` autosaved frame.

As of the 2026-06-03 lifecycle pass, the SwiftUI-main launch path no longer depends on `NSMainStoryboardFile`. `Latest/main.swift` creates and installs `AppDelegate`, `AppDelegate` builds the main menu programmatically, and `MainWindowController.makeProgrammaticSwiftUIMainWindowController()` creates the main `NSWindow` at the approved default content size: `768 x 516` points. This keeps launch independent from storyboard auto-instantiation while preserving the original window metrics.

Pixel parity currently depends on narrow AppKit bridges, but the active SwiftUI-main path no longer instantiates the main-window storyboard controllers. After the 2026-06-04 parity pass, the migration-owned `NSSplitViewController` hosts SwiftUI `NSHostingController` split children: `UpdatesSidebarView` for the sidebar and `ReleaseNotesDetailView` for the detail pane. The sidebar still uses an AppKit `NSTableView` bridge and the detail pane still uses the programmatic AppKit release-note controller/text/error/loading widgets, but those views are now created in code instead of loaded from `Main.storyboard`.

```text
programmatic NSWindow
  -> MainWindowController
      -> migration-owned NSSplitViewController
          -> SwiftUI UpdatesSidebarView with locked NSTableView/AppKit row bridge
          -> SwiftUI ReleaseNotesDetailView with programmatic ReleaseNotesViewController bridge
          -> SwiftUI/AppCommands environment for toolbar/menu command routing
```

Do not switch back to a hand-laid, pure SwiftUI text/list approximation until pixel parity is proven against the storyboard-era UI. The screenshot harness must capture natural window size; it must not call `setFrame`, `setContentSize`, or otherwise resize the window before comparison.

### Verification update: 2026-06-01 parity pass

Current embedded SwiftUI verification results:

1. Window geometry matched the storyboard path during the first parity pass at the then-current autosaved size: `860 x 300` points. That was a historical comparison frame only; the current user-approved target is `768 x 516` points.
2. The width distortion was caused by the earlier separate-window path and an over-large detail minimum width. The active path now uses the storyboard-created `NSWindow`, restores the pre-swap frame, and keeps the detail minimum width low enough that AppKit does not expand the window.
3. Whole-window screenshot comparison is visually near-identical at normal scale. Remaining amplified differences are concentrated in native text/icon antialiasing, the `NSSearchField` rasterization, and shadow/activation variance. The last measured thresholded diff was about `0.873%` of pixels over delta `8`, `0.4236%` over delta `32`, and `0.2997%` over delta `64`.
4. Behavior checks passed in the live debug app:
   - `Command-F` focuses the bridged `NSSearchField` as an `AXSearchField`.
   - `Escape` resigns the search field focus back to the window.
   - Typing an impossible search query filtered the sidebar from `41` rows to `0`, and clearing it restored `41` rows.
   - `Command-W` closed the main window and the debug app exited.
5. `./script/test.sh` passed with `79` tests executed, `2` skipped, and `0` failures.
6. After verification, `UseSwiftUIMainWindow` must be cleared. If a local `MainWindowSize` default is written for manual QA, use the current default size (`768 x 516`) rather than the old screenshot-only comparison frame.

### Verification update: 2026-06-02 default-size and release-notes pass

Current embedded SwiftUI verification results:

1. The main-window default is `768 x 516` points: 768 points wide by 516 points high. On a Retina display, screenshots of that window can appear around `1536 x 1032` image pixels before shadow/crop padding; compare Accessibility/window frame points for size verification, not screenshot bitmap dimensions.
2. The storyboard `contentRect`, SwiftUI visual metrics, and migration notes all use the `768 x 516` default. The prior `850 x 300` target was tried and rejected during QA; do not reintroduce it.
3. The SwiftUI sidebar table must not accept horizontal content movement. The bridged table uses a locked horizontal scroll view/clip view and keeps the document/table-column width aligned to the visible clip width. A horizontal CG scroll probe over the sidebar kept the `Cursor` row text at the same x-position before and after scrolling.
4. Row selection and release-note detail were verified with a real CG mouse click on a settled update row. The detail pane changed from the empty state to `Cursor`, `Version: 3.5.38 -> 3.6.31`, and no new `Latest Dev` crash report appeared during a 60-second selected release-note watch.
5. Plain AppleScript `click at` is not reliable for this row-selection QA because it can interact through Accessibility without delivering the same AppKit mouse-down path as a user click. Use a real click, CG mouse event, or manual QA for this specific flow.
6. `./script/test.sh` passed with `79` tests executed, `2` skipped, and `0` failures after the default-size, horizontal-scroll, and release-note crash fixes.
7. Settings remain intentionally storyboard/AppKit-owned during this pass. In the SwiftUI-main run, the Settings menu opened the `General` settings window, the `Locations` toolbar item switched to the `440 x 384` locations tab, and switching back restored the `General` `440 x 309` window.
8. A second release-note selection crash was reproduced in `Latest Dev-2026-06-02-094545.ips`. Root cause: `UpdatesTableRepresentable.updateNSView` called `NSTableView.reloadData()` during a SwiftUI/AppKit layout pass, which triggered AppKit constraint invalidation recursion and an `EXC_BREAKPOINT` in `_postWindowNeedsUpdateConstraints`.
9. The table bridge now coalesces SwiftUI updates and reloads the `NSTableView` only when a lightweight content signature changes. Selection-only updates refresh visible row state without rebuilding the whole table. Re-verification after this fix: row click rendered Cursor release notes, horizontal CG scroll did not move the sidebar content, the `Limited support` popover opened, the process stayed alive, and no crash report newer than `Latest Dev-2026-06-02-094545.ips` appeared.
10. `./script/test.sh` passed again after the table coalescing fix with `79` tests executed, `2` skipped, and `0` failures. Result bundle: `build/Latest-Tests-20260602-100039.xcresult`.
11. The default split position is `308 / 460` points: 308 points for the sidebar, 460 for release notes. App rows must let `NSTableView` provide the default source-list row view (`rowViewForRow` returns `nil` for app rows); only section headers return `UpdateGroupRowView`. A custom app row selection painter diverged from the storyboard and must not be restored.
12. The SwiftUI sidebar must be fixed at `308` points in the embedded split controller. In this parity path, `NSSplitViewItem.minimumThickness` and `maximumThickness` are both `308`; do not let the divider drag the whole sidebar left/right during QA. The bridged `NSTableView` also clamps its document origin to `x = 0` during layout and scroll-wheel handling.
13. The release-notes header must preserve the storyboard vertical geometry: app header content is anchored `15` points above the header bottom, leaving the larger top gap. A SwiftUI-only header with `.padding(.top, 15).padding(.bottom, 40)` reverses the storyboard geometry and makes the release-note page look wrong.
14. For pixel-level parity, the current SwiftUI split hosts the programmatic `ReleaseNotesViewController` through `NSViewControllerRepresentable`. This deliberately keeps the original `NSVisualEffectView`, `UpdateButton`, support-state button cell, 64-point app icon, loading/error controllers, and `ReleaseNotesTextViewController` inset/scroll behavior while the main split, sidebar state, toolbar/menu commands, and selection shell are SwiftUI-owned.
15. `MainWindowController` must be retained while the storyboard-created main window is alive. During SwiftUI flag launches, a process can otherwise remain alive and run update checks while tools report no accessible window. The active controller singleton is cleared in `windowWillClose`.
16. Clean build verification after the sidebar/header/window-retention corrections: `xcodebuild -project Latest.xcodeproj -scheme Latest -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build` succeeded on 2026-06-02. `git diff --check` succeeded, and no crash report newer than `Latest Dev-2026-06-02-094545.ips` appeared after relaunch.
17. Local tooling caveat from the same run: shell `screencapture`, System Events windows, and Computer Use reported black captures or `cgWindowNotFound` for the debug bundle even while the app itself reported the main `NSWindow` as visible at frame `(530, 159, 768, 516)`. When this happens, trust app-side/window-frame diagnostics and manual visual QA over AX-only capture until the local Screen Recording/Accessibility state is reset.
18. The release-note pane must not be loaded twice for one row selection. The SwiftUI pass originally triggered `ReleaseNotesViewModel.display(app:)` from both `MainWindowController` and `MainWindowView`; the parity bridge now lets the hosted legacy controller load the selected app exactly once per display key.
19. Clean verification after the full release-note controller bridge and sidebar source-list style update: `xcodebuild -project Latest.xcodeproj -scheme Latest -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build` succeeded on 2026-06-02. `./script/test.sh` also passed with `79` tests executed, `2` skipped, and `0` failures. Result bundle: `build/Latest-Tests-20260602-175809.xcresult`. No crash report newer than `Latest Dev-2026-06-02-094545.ips` appeared after launch attempts. Current shell/AX/CG tooling could not see any windows from the local session (`CGWindowList` returned zero total windows), so final visual QA still needs manual confirmation on the user-visible desktop.
20. SwiftUI-mode menu actions for sort order, show installed updates, and show ignored updates now route through `AppCommands` instead of directly mutating `AppListSettings` from `MainWindowController`. At the 2026-06-02 checkpoint, the unused pure SwiftUI release-note replacement files were also removed from the app target so the hosted storyboard controller was the only compiled release-note loading/rendering path; the later 2026-06-04 pass replaced that hosted controller with a programmatic AppKit controller. Verification after this cleanup: `xcodebuild -project Latest.xcodeproj -scheme Latest -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build` succeeded, and `./script/test.sh` passed with `79` tests executed, `2` skipped, and `0` failures. Result bundle: `build/Latest-Tests-20260602-180418.xcresult`.
21. The hand-laid SwiftUI sidebar row/header approximation was not pixel-level. The 2026-06-03 intermediate parity split instantiated `UpdateTableViewControllerIdentifier` and `ReleaseNotesViewControllerIdentifier` directly from `Main.storyboard` while the row geometry was being measured, fixed the sidebar split item at `308` points, wired `UpdateTableViewController.selectionDidChange` into `UpdatesListViewModel.selectedApp`, wired `searchQueryDidChange` into the SwiftUI search state, and let the original list controller drive the original release-note controller. That historical bridge preserved the storyboard row prototypes, `contentInsets.top = 78`, search field constraints, source-list selection, release-note header constraints, `UpdateButton`, support-state button cell, and `NSTextView` insets while the migrated window path kept SwiftUI command/progress ownership. The later 2026-06-04 pass recreated those main-window scenes programmatically. Verification on 2026-06-03: `git diff --check` passed, `xcodebuild -project Latest.xcodeproj -scheme Latest -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build` succeeded, `./script/test.sh` passed with `79` tests executed, `2` skipped, and `0` failures, result bundle `build/Latest-Tests-20260603-192038.xcresult`, fresh launch PID `62232` ran with `--swiftui-main-window`, and no `Latest Dev` crash report newer than `Latest Dev-2026-06-02-094545.ips` appeared.
22. Launch-storyboard removal is now real, but it required an explicit AppKit entry point. After removing `NSMainStoryboardFile`, a first fresh launch stayed alive with zero windows because the old storyboard had also connected `AppDelegate` to `NSApp`. The fix is `Latest/main.swift`, which retains `AppDelegate`, assigns it to `NSApplication.shared.delegate`, and then enters `NSApplicationMain`; `AppDelegate` is no longer marked `@main`. At the 2026-06-03 checkpoint, the SwiftUI-main path created the main window through `MainWindowController.makeProgrammaticSwiftUIMainWindowController()`, installed a programmatic main menu, and temporarily hosted storyboard list/release-note controllers for pixel parity; the later 2026-06-04 pass replaced those hosted storyboard controllers with programmatic views. Verification on 2026-06-03: built app `Info.plist` returned `Entry, ":NSMainStoryboardFile", Does Not Exist`; `xcodebuild -project Latest.xcodeproj -scheme Latest -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build` succeeded; `./script/test.sh` passed with `79` tests executed, `2` skipped, and `0` failures, result bundle `build/Latest-Tests-20260603-194539.xcresult`; fresh launch PID `80708` ran with `--swiftui-main-window`; Accessibility reported `1` standard window titled `Latest – 9 Updates Available` at frame position `(530, 405)` and size `776 x 516`; and screenshot capture showed the Latest window in front with the bridged storyboard sidebar and empty release-note state visible.
23. Settings are now SwiftUI-owned instead of storyboard-owned. `AppDelegate.showSettings(_:)` creates `SettingsWindowController.makeController()`, which hosts `SettingsRootView` and uses a programmatic selectable `NSToolbar` for the `General` and `Locations` tabs. The SwiftUI settings model preserves the existing `AppListSettings`, `InstallHelper`, and `AppDirectoryStore` behavior. Verification on 2026-06-03: opening Preferences through `Cmd+,` produced a `General` window at `440 x 309`; switching the toolbar to `Locations` changed the title and resized to `440 x 384`; switching back restored `General` at `440 x 309`; `xcodebuild -project Latest.xcodeproj -scheme Latest -configuration Debug -derivedDataPath ./.derivedData CODE_SIGNING_ALLOWED=NO build` succeeded; and `./script/test.sh` passed with `79` tests executed, `2` skipped, and `0` failures. Result bundle: `build/Latest-Tests-20260603-201559.xcresult`.
24. The release-note support-state popover is now programmatic instead of storyboard-segue-owned. `ReleaseNotesViewController` uses a programmatic header button with `SupportStatusButtonCell` for pixel parity, and the button creates a retained `NSPopover` with `SupportStatusInfoViewController.makeController(app:)`; the support-info destination scene and `presentSupportStateInfo` segue were removed from `Main.storyboard`. Verification on 2026-06-03: after a fresh SwiftUI-main launch, a real Quartz row click selected `1Password`, the release-note header exposed the `Limited` support button, a real Quartz click opened the migrated `Limited support` popover, and screenshot `/tmp/latest-support-popover-retained-20260603.png` showed the programmatic popover anchored to the support button.
25. The active SwiftUI main split no longer loads either main-window storyboard child controller. `SwiftUIMainWindowController.makeSplitViewController(environment:)` creates `NSHostingController` children for `UpdatesSidebarView` and `ReleaseNotesDetailView`; the sidebar uses a SwiftUI-owned `NSTableView` bridge, and `ReleaseNotesViewController` recreates the old release-note header/content programmatically. The header keeps the storyboard material, 64-point app icon, title/support row, version/date labels, trailing `UpdateButton`, separator, loading/error controllers, and `NSTextView` release-note content. The support badge must stay transparent: `SupportStatusButtonCell` draws only the 16-point status image and attributed title, while the button itself is borderless so `Limited` does not get a pill/shadow background. The `Limited` title uses `NSColor.controlAccentColor` with the small bold system font to keep the old blue-tinted text treatment without bringing back the rounded background. The title row itself, not the full title/version label stack, must be vertically centered against the 64-point icon; otherwise `ExpressVPN`/`Limited` sits visibly too high when the optional date row is detached. Its title row is a fixed 19-point AppKit row matching the storyboard frames: app name at `x = -2, y = 1, height = 16`, support button at `y = 0, height = 19`, and an 8-point gap after the title field. The external update label must be centered directly under the 59-point `UpdateButton`; it is placed in a fixed-width trailing action container and centered on the button instead of being constrained inside the container edges, because edge constraints pull `in ExpressVPN` left. The support-info popover is programmatic and uses the storyboard content metrics (`325 x 98` points for limited/no-support states, `300`-point info row width) with `loadViewIfNeeded()` before assigning `NSPopover.contentSize`.
26. Settings parity was retuned after direct comparison with the old storyboard settings scenes. The SwiftUI settings window still uses an AppKit `NSWindowController` and selectable `NSToolbar`, but the content now matches the original fixed view sizes: `General` content is `440 x 219` points inside a `440 x 309` frame, and `Locations` content is `440 x 296` points inside a `440 x 384` frame. `GeneralSettingsView` uses native AppKit checkbox bridges at the storyboard grid positions, and the helper row uses an AppKit representable with the old storyboard frames: separator at `y = 8`, helper label at `x = -2, y = 19, width = 319, height = 30`, and Enable button at `x = 335, y = 19, width = 65, height = 30`. `LocationsSettingsView` uses a bordered `NSTableView` bridge plus the original plus/minus `NSSegmentedControl` shape instead of a generic SwiftUI form/list.
27. Final 2026-06-04 verification for the no-storyboard SwiftUI/programmatic path: `xcodebuild -quiet -project Latest.xcodeproj -scheme Latest -configuration Debug -destination platform=macOS -derivedDataPath ./.derivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build` succeeded; a fresh debug launch reported the stable window frame `776 x 516` through Accessibility, matching the `768 x 516` content target plus window accounting; Computer Use selected `ExpressVPN`, saw the release-note detail content, exposed `button Limited` with no pill background, showed full centered `text in ExpressVPN` directly under `button Update`, and opened the compact `Limited support` popover; Computer Use also verified the SwiftUI-owned `General` Settings pane with the AppKit helper row and the `Locations` pane with the native toolbar, compact content, table rows, and plus/minus control; follow-up Computer Use checks selected `Zed` and `ExpressVPN`, verified the app title/support row uses the measured storyboard offsets, keeps the blue-tinted support-title color, and centers the title row against the app icon; `rg -n "NSStoryboard|instantiateInitialController|instantiateController\\(|NSMainStoryboardFile|Main\\.storyboard|Base\\.lproj/Main\\.storyboard" Latest Tests Latest.xcodeproj/project.pbxproj` returned no matches; `find ".derivedData/Build/Products/Debug/Latest Dev.app" -name 'Main.storyboard*' -print` returned no built storyboard resource; `git diff --check` passed; and `./script/test.sh` passed with `79` tests executed, `2` skipped, and `0` failures. Result bundle: `build/Latest-Tests-20260604-200730.xcresult`.
28. Verification gotcha: installing over `/Applications/Latest Dev.app` is not enough when an older `Latest Dev` process is still running from DerivedData. Always quit/kill stale `Latest Dev` processes, confirm `ps ax -o pid=,command= | rg 'Latest Dev.app|Latest Dev'` shows only `/Applications/Latest Dev.app/Contents/MacOS/Latest Dev`, and then use Computer Use against that installed process before trusting screenshot parity.

---

## 2. Non-goals

Do not do these during the first migration pass:

1. Do not redesign the product.
2. Do not replace the update-checking logic.
3. Do not change sorting/filtering semantics.
4. Do not rewrite Sparkle/App Store/Homebrew update logic.
5. Do not remove legacy AppKit controllers or inert storyboard localization artifacts merely to claim purity. Remove them only after their behavior is covered by the SwiftUI/programmatic path or proven unused.
6. Do not use default SwiftUI `List` styling if it prevents exact layout parity.
7. Do not hardcode English strings; preserve localization.
8. Do not remove AppKit completely just to claim the app is “pure SwiftUI.” Small AppKit bridges are acceptable when they protect native behavior.

---

## 3. Current repo facts that drive the migration

### 3.1 App entry and storyboard

Current app entry is explicit AppKit bootstrap code:

```swift
// Latest/main.swift
private let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
```

`Latest/Resources/Info.plist` no longer declares:

```xml
<key>NSMainStoryboardFile</key>
<string>Main</string>
```

The no-storyboard launch path depends on `Latest/main.swift` retaining the app delegate and assigning it to `NSApplication.shared.delegate` before `NSApplicationMain`. Without that explicit hookup, the process can stay alive with zero windows because the old storyboard was the object that previously connected `AppDelegate` to `NSApp`.

The current project settings also matter:

```text
SWIFT_VERSION = 6.0
MACOSX_DEPLOYMENT_TARGET = 26.0
INFOPLIST_FILE = $(SRCROOT)/Latest/Resources/Info.plist
```

New SwiftUI-only state can use the modern Observation framework, but that should be an implementation choice at the UI edge. The existing model/update pipeline should remain intact for the first pass.

### 3.2 Main window

Current main window behavior is controlled by `MainWindowController`.

Important existing behavior:

```swift
window?.titlebarAppearsTransparent = true
window?.toolbarStyle = .unified
splitViewController.splitView.autosaveName = "MainSplitView"
detailItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
```

These must be preserved or intentionally replaced.

### 3.3 Main layout

The main window is structurally:

```text
NSSplitViewController
  left: UpdateTableViewController
  right: ReleaseNotesViewController
```

The left split item is intentionally non-collapsible.

### 3.4 Updates list

The current list is an `NSTableView` with custom cells and section rows.

Important hard-coded measurements:

```swift
section header row height = 27
app row height = 65
scroll view content top inset = 78
scroll view bottom scroller inset = 10
```

These are visual requirements, not implementation accidents.

### 3.5 App row content

Current app row displays:

```text
app icon
app name
current version
new version, hidden when unavailable
update date
update button
support-state indicator image, conditionally hidden
```

### 3.6 Release notes detail pane

Current detail view displays:

```text
header visual effect background
app icon
app name
version text
update date
update button
external update label
support-state button
release notes body
loading state
error/empty state
```

Although the release notes controller imports `WebKit`, the visible release notes body is currently rendered by `ReleaseNotesTextViewController` as an `NSTextView` inside an `NSScrollView`. `ReleaseNotesProvider` returns `NSAttributedString` after converting HTML, Markdown, GitHub release data, changelog pages, or fallback web content.

The SwiftUI parity version currently hosts a programmatic AppKit `ReleaseNotesViewController` instead of recreating this pane in pure SwiftUI. Keep that bridge until a pure SwiftUI/AppKit-hybrid replacement matches the original header, loading state, error/empty state, text insets, scroll offset, support popover, update button, and external-updater label in manual pixel QA.

### 3.7 State model

The current state model is already useful and should be kept at first:

```text
App
AppListSnapshot
AppListSettings
IconCache
ReleaseNotesProvider
UpdateCheckCoordinator
UpdateQueue
```

`AppListSnapshot` already handles filtering, sorting, and section partitioning. Do not duplicate that logic in SwiftUI.

### 3.8 Existing tests

There are already tests around `AppListSnapshot` and table diff behavior. Keep them and add SwiftUI-specific UI/snapshot tests on top.

---

## 4. Migration strategy

Use a **strangler-fig migration**:

```text
Old storyboard UI remains shippable
New SwiftUI UI is added in parallel
Feature flag controls which UI launches
Pixel parity is verified
Storyboard is removed only after main-window parity and every remaining storyboard scene is replaced or moved
```

This avoids the most common failure mode: deleting the working UI first and ending up with a half-finished SwiftUI clone.

---

## 5. Recommended branch and commit structure

Create a long-lived migration branch:

```bash
git checkout develop
git checkout -b remake/swiftui-pixel-parity
```

Recommended commits:

```text
1. docs: add SwiftUI pixel-parity migration plan
2. test: add deterministic UI fixture data
3. test: add baseline screenshot capture support
4. ui: add SwiftUI design tokens and visual metrics
5. ui: add SwiftUI update row view
6. ui: add SwiftUI section header view
7. ui: add SwiftUI updates sidebar view
8. ui: add SwiftUI release notes detail view
9. ui: add SwiftUI main split window behind feature flag
10. ui: add toolbar and command routing
11. ui: port contextual row actions and menus
12. ui: bridge existing settings or move settings out of Main.storyboard
13. test: add pixel comparison tests
14. chore: switch default launch path to SwiftUI
15. ui: port settings window and support-state popover if still storyboard-backed
16. chore: remove Main.storyboard and legacy controllers
17. chore: clean project references and localized Main.strings
```

---

## 6. Visual parity baseline

Before writing SwiftUI views, capture a reference pack from the current app.

Create:

```text
Tests/VisualBaselines/Legacy/
  01-empty-light.png
  02-empty-dark.png
  03-checking-updates-light.png
  04-updates-available-light.png
  05-updates-available-dark.png
  06-selected-app-detail-light.png
  07-release-notes-loading.png
  08-release-notes-error.png
  09-unsupported-app-state.png
  10-search-filtered.png
  11-context-menu.png
  12-row-action-leading.png
  13-row-action-trailing.png
  14-update-button-progress.png
  15-update-button-error.png
  16-inactive-window-selection.png
  17-settings-general.png
  18-settings-locations.png
```

Also record geometry in a text file:

```text
Tests/VisualBaselines/Legacy/measurements.md
```

Include:

```text
window width
window height
sidebar width
split divider x position
titlebar height
toolbar item x positions
search field frame
section header height
app row height
app icon frame
app title text baseline
version text baseline
update button frame
detail header height
detail icon frame
release notes scroll origin
toolbar item order
inactive selected row appearance
update button progress/error frames
```

Known measurements from code:

```text
app row height: 65
section header height: 27
storyboard list scroll top content inset: 78
SwiftUI table scroll top content inset: 35, with the search/header overlay fixed above it
scroll view bottom scroller inset: 10
release notes text inset: 14
main window storyboard/default content size: 768 wide x 516 high
rejected historical comparison/default sizes: 860 wide x 300 high, then 850 wide x 300 high
main window minimum size: 350 wide x 300 high
sidebar minimum width: 300
sidebar ideal width / split position: 308
SwiftUI parity sidebar min and max split thickness: 308
detail minimum width: 460
release notes header storyboard height: 119
release notes header content bottom inset: 15
release notes text initial scroll y after inset: -238
```

The storyboard design canvas size was previously `1004 x 495`, which was not the launch window size. Do not force the window to `1004 x 495` for screenshots. Do not use the rejected `850 x 300` target either. The current default target is 768 points wide by 516 points high, and comparison captures should use the same natural/autosaved frame for both legacy and SwiftUI paths. On Retina displays, screenshot bitmap dimensions are larger than point dimensions.

Everything else should be measured from screenshots or the existing storyboard.

---

## 7. Proposed new source layout

Add a dedicated SwiftUI folder without disturbing the old UI at first:

```text
Latest/
  SwiftUI/
    App/
      LatestSwiftUIApp.swift              # final @main entry, not enabled immediately
      LegacyAppDelegateAdapter.swift      # only if needed after @main conversion
      AppEnvironment.swift
      AppCommands.swift
      AppProviderObservationAdapter.swift
      UpdateCheckingService.swift

    MainWindow/
      MainWindowView.swift
      MainSplitView.swift
      MainWindowAccessor.swift            # AppKit bridge for NSWindow-level behavior
      MainToolbar.swift

    Updates/
      UpdatesListViewModel.swift
      UpdatesSidebarView.swift
      UpdateRowView.swift
      UpdateSectionHeaderView.swift
      UpdateRowContextMenu.swift
      UpdateSearchFieldView.swift
      UpdateRowSwipeActionsBridge.swift    # optional AppKit bridge if native row actions matter

    ReleaseNotes/
      ReleaseNotesDetailView.swift         # SwiftUI bridge hosting programmatic AppKit ReleaseNotesViewController

    Settings/
      SettingsWindowView.swift
      GeneralSettingsView.swift
      LocationsSettingsView.swift

    Shared/
      DesignTokens.swift
      VisualMetrics.swift
      NativeImageView.swift
      HighlightedText.swift
      PixelParityDebugOverlay.swift

Tests/
  VisualBaselines/
  VisualSnapshotTests/
  SwiftUIFixtureData/
```

---

## 8. Design tokens and visual metrics

Add a single source of truth for all measured dimensions.

```swift
import SwiftUI

@MainActor
enum VisualMetrics {
    static let appRowHeight: CGFloat = 65
    static let sectionHeaderHeight: CGFloat = 27
    static let listTopInset: CGFloat = 36
    static let scrollBottomInset: CGFloat = 10
    static let releaseNotesTextInset: CGFloat = 14

    static let mainWindowDefaultWidth: CGFloat = 768
    static let mainWindowDefaultHeight: CGFloat = 516

    static let sidebarMinWidth: CGFloat = 300
    static let sidebarIdealWidth: CGFloat = 308
    static let detailMinWidth: CGFloat = 460
    static let mainWindowMinWidth: CGFloat = 350
    static let mainWindowMinHeight: CGFloat = 300

    static let appIconSize: CGFloat = 50
    static let detailIconSize: CGFloat = 64

    static let rowHorizontalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 8
    static let rowTextSpacing: CGFloat = 2

    static let detailHeaderHeight: CGFloat = 119
    static let detailHeaderHorizontalPadding: CGFloat = 20
}

@MainActor
enum DesignTokens {
    static let rowCornerRadius: CGFloat = 0
    static let selectedRowCornerRadius: CGFloat = 6

    static let primaryText = Color.primary
    static let secondaryText = Color.secondary

    static let appNameFont = Font.body
    static let versionFont = Font.caption
    static let sectionFont = Font.caption.weight(.semibold)
}
```

These values should be treated as implementation assets. Do not scatter magic numbers across views.

---

## 9. State and view model plan

### 9.1 Keep existing model types first

Do not rewrite `App`, `AppListSnapshot`, `AppListSettings`, `UpdateCheckCoordinator`, `IconCache`, `ReleaseNotesProvider`, or `UpdateQueue` in the first pass.

The SwiftUI layer should wrap existing state.

### 9.2 Add `UpdatesListViewModel`

`AppListSettings` can observe any `Observer`, but `AppProviding.addObserver` currently requires an `NSObject`. Either inherit from `NSObject` in the view model or create a small NSObject-backed adapter. Do not call `AppListSnapshot.contains(_:)` to decide visibility; it tracks the source app set, while `firstIndex(of:)` tracks visible entries.

```swift
@MainActor
final class UpdatesListViewModel: NSObject, ObservableObject, Observer {
    nonisolated let id = UUID()

    @Published private(set) var snapshot: AppListSnapshot
    @Published var selectedApp: App?
    @Published var searchQuery: String = ""
    @Published private(set) var isCheckingForUpdates = false

    init(initialApps: [App] = []) {
        self.snapshot = AppListSnapshot(withApps: initialApps, filterQuery: nil)
        super.init()
    }

    func startObserving() {
        AppListSettings.shared.add(self) { [weak self] in
            self?.refreshSnapshot(animated: true)
        }

        UpdateCheckCoordinator.shared.appProvider.addObserver(self) { [weak self] apps in
            self?.snapshot = AppListSnapshot(
                withApps: apps,
                filterQuery: self?.normalizedSearchQuery
            )
            self?.maintainSelectionAfterSnapshotChange()
        }
    }

    func stopObserving() {
        AppListSettings.shared.removeObserver(withID: id)
        UpdateCheckCoordinator.shared.appProvider.removeObserver(self)
    }

    func setSearchQuery(_ query: String) {
        searchQuery = query
        snapshot = snapshot.updated(with: normalizedSearchQuery)
        maintainSelectionAfterSnapshotChange()
    }

    func checkForUpdates() {
        // Call through to existing controller logic extracted into a service,
        // or move the old `checkForUpdates()` behavior out of UpdateTableViewController.
    }

    func updateAll() {
        let apps = UpdateCheckCoordinator.shared.appProvider.updatableApps
        apps.forEach { app in
            if !app.isUpdating {
                app.performUpdate(isBulkUpdate: true)
            }
        }
    }

    private var normalizedSearchQuery: String? {
        searchQuery.isEmpty ? nil : searchQuery
    }

    private func refreshSnapshot(animated: Bool) {
        snapshot = snapshot.updated(with: normalizedSearchQuery)
        maintainSelectionAfterSnapshotChange()
    }

    private func maintainSelectionAfterSnapshotChange() {
        guard let selectedApp else { return }
        if snapshot.firstIndex(of: selectedApp) == nil {
            self.selectedApp = nil
        }
    }
}
```

If using the Observation framework instead of `ObservableObject`, keep the same lifetime requirements: retain the observer while the window is alive, remove it when the window closes, and keep all observer callbacks on the main actor.

Important: the old `UpdateTableViewController.checkForUpdates()` behavior should be extracted into a non-view service before the old controller is deleted. Do not make SwiftUI call methods on an `NSViewController`.

The same applies to `MainWindowController.updateAll(_:)`: preserve the App Store preparation/fallback path before performing built-in updates. A simplified SwiftUI `updateAll()` that only loops over `updatableApps` would drop existing App Store behavior.

Also note that `UpdateCheckCoordinator.progressDelegate` is currently a single weak delegate. During the feature-flag period, do not let the old window controller and the SwiftUI service compete for this delegate. Extract progress reporting into one service, then have whichever UI is active observe that service.

Recommended service:

```swift
@MainActor
final class UpdateCheckingService: UpdateCheckProgressReporting {
    static let shared = UpdateCheckingService()

    var onProgressChanged: ((UpdateCheckingProgress) -> Void)?

    func checkForUpdates() {
        // Move existing controller-owned check/update flow here.
    }
}
```

---

## 10. App lifecycle migration

There are two safe options.

### Option A — current safest parity path

Keep the explicit AppKit bootstrap in `Latest/main.swift`, install `AppDelegate` programmatically, and create the main `NSWindow` in code when `UseSwiftUIMainWindow` or `--swiftui-main-window` is enabled.

Use this during parity work because it removes storyboard auto-launch while still preserving the old main-window metrics, autosaved frame name, toolbar/titlebar behavior, and split-view restoration rules in `MainWindowController`.

The legacy storyboard main window starts an update check in `MainWindowController.windowDidLoad()`. In flag mode, route programmatic window creation directly into a SwiftUI setup path so the old table controller does not kick off scanning, claim `progressDelegate`, or leave old content visible behind the SwiftUI content.

Example:

```swift
final class MainWindowController: NSWindowController {
    override func windowDidLoad() {
        super.windowDidLoad()

        if LaunchMode.useSwiftUIMainWindow {
            configureSwiftUIMainWindow()
            return
        }

        configureLegacyStoryboardWindow()
    }

    private func configureSwiftUIMainWindow() {
        let storyboardFrame = window?.frame
        let environment = AppEnvironment.live()
        contentViewController = SwiftUIMainWindowController.makeSplitViewController(environment: environment)

        if let storyboardFrame {
            window?.setFrame(storyboardFrame, display: false)
        }

        bindSwiftUIEnvironment(environment)
        environment.start()
    }
}
```

Feature flag:

```swift
enum LaunchMode {
    static var useSwiftUIMainWindow: Bool {
        CommandLine.arguments.contains("--swiftui-main-window")
            || UserDefaults.standard.bool(forKey: "UseSwiftUIMainWindow")
    }
}
```

`AppDelegate` should not create or retain another main-window controller in this path. It may activate the app after launch when the SwiftUI flag is enabled:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if LaunchMode.useSwiftUIMainWindow {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

`SwiftUIMainWindowController` is factory-only in the current branch. It must not instantiate or show a second `NSWindow` during parity verification.

### Option B — final path

Convert from the current explicit AppKit bootstrap to a full SwiftUI lifecycle.

Steps:

1. Keep `Latest/main.swift` and programmatic `AppDelegate` launch until the SwiftUI scenes, settings, commands, popovers, and localized string migration are proven.
2. Rename `AppDelegate` to `LegacyAppDelegate` or keep `AppDelegate` without `@main`.
3. Delete `Latest/main.swift` from the main app target only when the SwiftUI `@main App` replaces it.
4. Add:

```swift
import SwiftUI

@main
struct LatestApp: SwiftUI.App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment.live

    var body: some Scene {
        WindowGroup {
            MainWindowView(environment: environment)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            LatestCommands(environment: environment)
        }

        Settings {
            SettingsWindowView(environment: environment)
        }
    }
}
```

Because the existing `AppDelegate` now also installs the main menu and explicitly presents the main window, this conversion should wait until equivalent SwiftUI commands, settings, and window-presentation behavior are proven.

Removing `NSMainStoryboardFile` stops storyboard auto-launch. The current branch also removed `Main.storyboard` from the active programmatic path; keep the source/build no-storyboard checks in place until localized historical `Main.strings` entries and stale controller classes are cleaned up deliberately.

---

## 11. Main window remake

### 11.1 Target structure

```swift
struct MainWindowView: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        MainSplitView(
            updatesViewModel: environment.updatesListViewModel,
            searchFocusController: environment.searchFocusController
        )
        .background(WindowAccessor { window in
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.title = Bundle.main.localizedInfoDictionary?[kCFBundleNameKey as String] as? String ?? "Latest"
            _ = window.setFrameAutosaveName("MainWindowSize")
        })
        .toolbar {
            MainToolbar(environment: environment)
        }
    }
}
```

Also preserve the old `view.window?.subtitle` update count and dock badge behavior from `UpdateTableViewController.updateTitleAndBatch()`. Those are app-chrome behaviors, so route them through the environment/service layer rather than a row/list view.

### 11.2 Split layout

Avoid accepting SwiftUI defaults blindly. Use `NavigationSplitView` only if it can match the old split view precisely. If not, use `HSplitView` with fixed/minimum constraints.

Preferred first implementation:

```swift
struct MainSplitView: View {
    @ObservedObject var updatesViewModel: UpdatesListViewModel
    @ObservedObject var searchFocusController: SearchFocusController

    var body: some View {
        HSplitView {
            UpdatesSidebarView(viewModel: updatesViewModel, searchFocusController: searchFocusController)
                .frame(width: VisualMetrics.sidebarIdealWidth)

            ReleaseNotesDetailView(updatesViewModel: updatesViewModel)
                .frame(minWidth: VisualMetrics.detailMinWidth)
        }
    }
}
```

The current parity implementation uses an `NSSplitViewController` bridge with SwiftUI views embedded as `NSHostingController`s so the sidebar item can be fixed at `308` points. Pixel parity beats architectural purity.

Whatever implementation is chosen, preserve the old split autosave key `MainSplitView` so existing users keep their divider position.

---

## 12. Updates sidebar remake

### 12.1 Do not start with `List`

`List` is attractive but risky for this app because the existing UI depends on:

```text
exact row heights
custom group rows
custom selection behavior
custom top inset
custom context menu
custom row actions
precise AppKit table density
```

Start with:

```swift
ScrollView {
    LazyVStack(spacing: 0) { ... }
}
```

Only switch to `List` if it matches the old layout under light/dark mode, localization, selection, and hover states.

### 12.2 Sidebar view skeleton

```swift
struct UpdatesSidebarView: View {
    @ObservedObject var viewModel: UpdatesListViewModel

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(indexedEntries, id: \.id) { item in
                        switch item.entry {
                        case .section(let section):
                            UpdateSectionHeaderView(section: section)
                                .frame(height: VisualMetrics.sectionHeaderHeight)

                        case .app(let app):
                            UpdateRowView(
                                app: app,
                                isSelected: viewModel.selectedApp?.identifier == app.identifier,
                                filterQuery: viewModel.snapshot.filterQuery,
                                onSelect: { viewModel.selectedApp = app },
                                onUpdate: { app.performUpdate() },
                                onOpen: { app.open() },
                                onReveal: { app.showInFinder() },
                                onIgnore: { UpdateCheckCoordinator.shared.appProvider.setIgnoredState(true, for: app) },
                                onUnignore: { UpdateCheckCoordinator.shared.appProvider.setIgnoredState(false, for: app) }
                            )
                            .frame(height: VisualMetrics.appRowHeight)
                        }
                    }
                }
                .padding(.top, VisualMetrics.listTopInset)
                .padding(.bottom, VisualMetrics.scrollBottomInset)
            }

            UpdatesSidebarHeaderView(viewModel: viewModel)
        }
    }
}
```

### 12.3 Sidebar header/search

Recreate the old search behavior:

```text
empty string -> nil filter query
ESC -> resign first responder
Find command -> focus search field
```

The old `UpdateSearchField` has custom ESC behavior, so SwiftUI may need an `NSSearchField` wrapper to match it exactly.

Recommended first pass:

```swift
struct SearchFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = UpdateSearchField()
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
}
```

---

## 13. Update row remake

### 13.1 Required row states

Each row must support:

```text
normal
hovered
selected
selected + inactive window
updating
ignored
unsupported / limited support indicator visible
external updater
search-highlighted name
long app name truncation
long version string truncation
light mode
dark mode
```

### 13.2 Row skeleton

```swift
struct UpdateRowView: View {
    let app: App
    let isSelected: Bool
    let filterQuery: String?

    let onSelect: () -> Void
    let onUpdate: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onIgnore: () -> Void
    let onUnignore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(app: app)
                .frame(width: VisualMetrics.appIconSize, height: VisualMetrics.appIconSize)

            VStack(alignment: .leading, spacing: VisualMetrics.rowTextSpacing) {
                HighlightedAppNameText(app: app, query: filterQuery)
                    .lineLimit(1)

                VersionLine(app: app)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(rowDateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    SupportStateIndicator(app: app)
                    UpdateActionButton(app: app, action: onUpdate)
                }
            }
        }
        .padding(.horizontal, VisualMetrics.rowHorizontalPadding)
        .contentShape(Rectangle())
        .background(rowBackground)
        .onTapGesture(perform: onSelect)
        .contextMenu { rowContextMenu }
    }
}
```

### 13.3 Search highlighting

The old `App.highlightedName(for:)` returns an `NSAttributedString` and fades non-matching text. Preserve that behavior.

Use `AttributedString` conversion if possible; otherwise bridge through `NSTextField`.

Do not replace this with a generic bold highlight unless you accept a visual change.

### 13.4 Icon loading

Keep `IconCache.shared.icon(for:)` initially. Wrap it:

```swift
@MainActor
final class AppIconLoader: ObservableObject {
    @Published var image: NSImage?

    func loadIcon(for app: App) {
        IconCache.shared.icon(for: app) { [weak self] image in
            self?.image = image
        }
    }
}
```

### 13.5 Update button parity

The old `UpdateButton` is not a plain push button. It switches between hidden, update, open, indeterminate, circular progress/cancel, and error states through `UpdateQueue`, and `UpdateButtonCell` custom-draws the pill/progress indicator. The SwiftUI version should either wrap this AppKit control first or recreate every state before replacing it.

---

## 14. Row actions and context menu

The current table supports:

```text
trailing row action: update
leading row actions: open, reveal in Finder
context menu: update, open, reveal, ignore, unignore
```

SwiftUI on macOS may not reproduce `NSTableViewRowAction` behavior exactly. Use this priority order:

1. Recreate context menu in SwiftUI.
2. Recreate visible buttons/menus needed for functionality.
3. If swipe/row actions are essential to parity, add an AppKit-backed row-action bridge.

Context menu mapping:

```swift
@ViewBuilder
var rowContextMenu: some View {
    if app.updateAvailable && !app.isUpdating {
        Button(updateTitle(for: app), action: onUpdate)
    }

    Button(String(localized: "OpenAction"), action: onOpen)
    Button(String(localized: "RevealAction"), action: onReveal)

    if app.isIgnored {
        Button(String(localized: "UnignoreAction"), action: onUnignore)
    } else {
        Button(String(localized: "IgnoreAction"), action: onIgnore)
    }
}
```

Keep title logic identical:

```text
if externalUpdaterName exists -> ExternalUpdateAction
else -> UpdateAction
```

---

## 15. Release notes detail remake

Current parity path: `SwiftUIMainWindowController` hosts `ReleaseNotesDetailView`, which wraps the programmatic AppKit `ReleaseNotesViewController`. That controller owns release-note loading, empty/error/loading state, header layout, update button, support-state button, and text insets. The support-state popover content is also programmatic. Do not wire a parallel SwiftUI release-note loader while that bridge is active.

The sections below are deferred pure-replacement notes. Use them only after pixel QA proves the replacement matches the hosted programmatic AppKit controller.

### 15.1 Deferred state model

```swift
enum ReleaseNotesViewState {
    case empty(LatestError)
    case loading(App)
    case error(App?, Error)
    case loaded(App, NSAttributedString)
}
```

### 15.2 View model

```swift
@MainActor
final class ReleaseNotesViewModel: ObservableObject {
    @Published private(set) var state: ReleaseNotesViewState

    private let provider: ReleaseNotesProvider
    private var loadingDelayTask: Task<Void, Never>?
    private var currentRequestID = UUID()

    init(provider: ReleaseNotesProvider = ReleaseNotesProvider()) {
        self.provider = provider
        self.state = .empty(Self.noSelectionError)
    }

    func display(app: App?) {
        loadingDelayTask?.cancel()
        let requestID = UUID()
        currentRequestID = requestID

        guard let app else {
            state = .empty(Self.noSelectionError)
            return
        }

        loadingDelayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.currentRequestID == requestID else { return }
                self?.state = .loading(app)
            }
        }

        provider.releaseNotes(for: app) { [weak self] result in
            Task { @MainActor in
                guard self?.currentRequestID == requestID else { return }
                self?.loadingDelayTask?.cancel()

                switch result {
                case .success(let notes):
                    self?.state = .loaded(app, notes)
                case .failure(let error):
                    self?.state = .error(app, error)
                }
            }
        }
    }
}
```

This would keep the old behavior where the loading indicator is delayed slightly to avoid flicker. Do not enable it alongside the hosted programmatic controller, or row selection will fetch release notes twice.

### 15.3 Header

The old header uses `NSVisualEffectView`. SwiftUI `Material` may be close, but not always pixel-identical. When replacing the hosted controller, start with a small AppKit bridge:

```swift
struct NativeVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}
```

### 15.4 Release notes body

When replacing the hosted controller, start with an `NSTextView` wrapper because the old visible body is an attributed-text view. Preserve `ReleaseNotesTextViewController.format(_:)` behavior: strip custom colors/backgrounds/shadows, reset the base font, keep bold/italic/link attributes, and apply the same scroll/content insets.

```swift
struct AttributedTextViewRepresentable: NSViewRepresentable {
    let text: NSAttributedString
    let topInset: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(text)
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: topInset + VisualMetrics.releaseNotesTextInset,
            left: VisualMetrics.releaseNotesTextInset,
            bottom: VisualMetrics.releaseNotesTextInset,
            right: VisualMetrics.releaseNotesTextInset
        )
    }
}
```

Do not replace this with `Text`, `Markdown`, or a live `WKWebView` until you compare typography, link handling, scroll behavior, selection, and release note formatting.

---

## 16. Toolbar and commands

Current toolbar contains:

```text
flexible space
progress indicator
check for updates button
update all button
sidebar tracking separator
```

SwiftUI toolbar should preserve the same visible order and validation behavior.
The `.sidebarTrackingSeparator` is part of the current unified-toolbar/sidebar polish; if SwiftUI toolbar APIs cannot reproduce it, use an `NSToolbar` bridge for the first parity pass.

```swift
struct MainToolbar: ToolbarContent {
    @ObservedObject var environment: AppEnvironment

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Spacer()

            if environment.updateCheckingState.isRunning {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                environment.commands.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(String(localized: "CheckForUpdatesToolbarItemToolTip"))
            .disabled(environment.updateCheckingState.isRunning)

            Button {
                environment.commands.updateAll()
            } label: {
                Image("custom.arrow.down.square.stack")
            }
            .help(String(localized: "UpdateAllToolbarItemToolTip"))
            .disabled(!environment.updateCheckingState.hasUpdatesAvailable)
        }
    }
}
```

If SwiftUI toolbar placement cannot reproduce the old toolbar exactly, keep an `NSToolbar` bridge until the final cleanup.

### 16.1 Commands/menu mapping

Create one command object and route all menu/toolbar actions through it:

```swift
@MainActor
final class AppCommands: ObservableObject {
    func reload()
    func updateAll()
    func focusSearch()
    func visitWebsite()
    func donate()
    func changeSortOrder(_ order: AppListSettings.SortOptions)
    func toggleShowInstalledUpdates()
    func toggleShowIgnoredUpdates()
}
```

This replaces scattered `@IBAction` methods.

---

## 17. Settings migration

Settings now use a SwiftUI-owned window after the 2026-06-03 lifecycle pass.

The current implementation keeps an AppKit `NSWindowController`/`NSToolbar` shell because the original window uses toolbar-tab selection and precise per-tab frame sizes. The content itself is SwiftUI:

```text
SettingsWindowController
  -> SettingsRootView
      -> GeneralSettingsView
      -> LocationsSettingsView
```

The storyboard settings scene is no longer instantiated from `AppDelegate`. Keep the old settings controllers only until the project cleanup phase removes stale storyboard scenes, localized `Main.strings` entries, and Xcode references.

Recommended sequence:

```text
Phase 1: keep existing settings controllers - done historically
Phase 2: expose settings model/state cleanly - done through SettingsViewModel
Phase 3: rebuild General tab in SwiftUI - done
Phase 4: rebuild Locations tab in SwiftUI - done
Phase 5: recreate storyboard frame sizing - done with explicit 440 x 219 / 440 x 296 content sizes and 440 x 309 / 440 x 384 window frames
Phase 6: remove SettingsTabViewController and related storyboard scenes during final storyboard cleanup
```

Settings parity requirements:

```text
same tab labels
same window title behavior
same content size per tab
same frame size per tab
same UserDefaults keys
same localization keys
native checkbox metrics in General
bordered NSTableView and plus/minus NSSegmentedControl metrics in Locations
```

---

## 18. Localization migration

The project has many localized `Main.strings` entries because storyboard UI text is localized through Interface Builder.

During migration:

1. Move all user-facing UI strings into `Localizable.strings` / `Localizable.stringsdict`.
2. Do not delete localized `Main.strings` until no storyboard scenes reference them.
3. Audit menu, toolbar, settings, row context menu, and support-state popover strings, because those are currently partly storyboard-owned.
4. Add a localization audit test that catches missing keys.
5. Test long strings in German/Russian and RTL behavior in Arabic/Hebrew if supported.

Recommended convention:

```swift
Text(String(localized: "AvailableUpdatesSection"))
```

Do not use plain string literals in SwiftUI views except for debug-only labels.

---

## 19. Test strategy

### 19.1 Keep existing unit tests

Keep tests for:

```text
AppListSnapshot
AppStoreCheckerOperation
AppDataStore
UpdateQueue
ReleaseNotesAudit
Version parsing/sanitization
```

These protect the app logic during UI migration.

### 19.2 Add deterministic UI fixture data

Create fake apps with stable:

```text
name
bundle identifier
current version
remote version
update date
modification date
source
support status
icon
release notes
update state
ignored state
```

Example fixture set:

```text
Alpha.app       update available, Sparkle, built-in update
Beta.app        installed, no update
Gamma.app       ignored update
Delta.app       unsupported
Epsilon.app     external updater
LongName.app    very long app name
LongVersion.app very long version string
```

### 19.3 Snapshot tests

Minimum scenarios:

```text
empty state
checking progress indeterminate
available updates grouped
installed apps section visible
ignored apps section visible
search filtered list
selected row
release notes loading
release notes loaded
release notes error
update button indeterminate/progress/error
inactive window selected row
window subtitle and dock badge count
context menu
settings general
settings locations
```

### 19.4 Pixel comparison rules

Use two classes of validation:

#### Whole-screen tolerance

```text
overall changed pixels <= agreed threshold
color delta threshold small enough to catch accidental styling drift
```

#### Anchor-based exact checks

Check geometry for key elements:

```text
split divider x
first row y
row height
section header height
app icon frame
app name baseline
update button frame
detail header height
release notes origin
```

Anchor checks are more important than whole-image tolerance because antialiasing can create harmless pixel noise.

### 19.5 Manual QA checklist

Run through:

```text
launch app
close main window -> app terminates
check for updates
confirm only one update check starts in SwiftUI flag mode
update all
update App Store-backed app path or fallback handling
select app
load release notes
verify release notes text selection and links
open external links
use search
press ESC in search
use Cmd+F
change sort order
show/hide installed updates
show/hide ignored updates
right-click row context menu
open app
reveal app in Finder
ignore/unignore app
cancel an in-progress update
show update error and retry/cancel alert
switch light/dark mode
switch accent color
resize window
move split divider
quit/relaunch and confirm split autosave behavior
open settings
switch settings tabs
```

---

## 20. Cutover checklist

Do not switch the default launch path to SwiftUI until all of this is true:

```text
[ ] SwiftUI main window opens without storyboard.
[ ] App still terminates after closing the last window.
[ ] Check for updates works.
[ ] SwiftUI flag mode does not trigger a duplicate old-controller update check.
[ ] Progress indicator behavior matches old UI.
[ ] Update all works.
[ ] App Store update preparation/fallback behavior still works.
[ ] App row update action works.
[ ] App row progress/cancel/error states work.
[ ] App row open action works.
[ ] Reveal in Finder works.
[ ] Ignore/unignore works.
[ ] Search works.
[ ] ESC exits search focus.
[ ] Cmd+F focuses search.
[ ] Sort menu works.
[ ] Show installed updates toggle works.
[ ] Show ignored updates toggle works.
[ ] Selection persists correctly across snapshot updates.
[ ] Release notes empty/loading/error/loaded states work.
[ ] Release notes attributed formatting, selection, insets, and links match baseline.
[ ] App icon loading does not flicker.
[ ] Window subtitle and Dock badge update counts match baseline.
[ ] Light mode matches baseline.
[ ] Dark mode matches baseline.
[ ] Localized strings work.
[ ] Settings still work, either as SwiftUI or bridged AppKit.
[ ] Existing unit tests pass.
[ ] New visual tests pass.
```

---

## 21. Storyboard removal checklist

Only after cutover:

### 21.1 Remove launch storyboard linkage

Done in the 2026-06-03 lifecycle pass: `Latest/Resources/Info.plist` no longer contains:

```xml
<key>NSMainStoryboardFile</key>
<string>Main</string>
```

Keep this key absent. The replacement launch owner is `Latest/main.swift` plus `AppDelegate.showMainWindowIfNeeded()`.

### 21.2 Remove storyboard resource

Remove `Main.storyboard in Resources` from the app target.

Do this only after the main-window parity bridges and localized storyboard strings no longer depend on `Main.storyboard`. Removing `NSMainStoryboardFile` for launch is safe earlier; removing the storyboard resource is not.

### 21.3 Delete old main-window controllers after replacement

Delete only after equivalent SwiftUI behavior exists:

```text
Latest/Interface/Main Window/Window Controllers/MainWindowController.swift
Latest/Interface/Main Window/Window Controllers/MainWindowController+Toolbar.swift
Latest/Interface/Main Window/Update Table View/Controller/UpdateTableViewController.swift
Latest/Interface/Main Window/Update Table View/Controller/UpdateTableViewController+Actions.swift
Latest/Interface/Main Window/Update Table View/Controller/UpdateTableView+Search.swift
Latest/Interface/Main Window/Update Table View/Views/UpdateCell.swift
Latest/Interface/Main Window/Update Table View/Views/UpdateGroupCellView.swift
Latest/Interface/Main Window/Update Table View/Views/UpdateGroupRowView.swift
Latest/Interface/Main Window/Update Table View/Views/UpdateTableView.swift
Latest/Interface/Main Window/Release Notes/ReleaseNotesViewController.swift
Latest/Interface/Main Window/Release Notes/Controller/ReleaseNotesLoadingViewController.swift
Latest/Interface/Main Window/Release Notes/Controller/ReleaseNotesErrorViewController.swift
Latest/Interface/Main Window/Release Notes/Controller/ReleaseNotesTextViewController.swift
```

Keep reusable non-UI logic if any is discovered during extraction.

Delete these only after popover equivalents exist and stale settings scenes have been removed from storyboard/project resources:

```text
Latest/Interface/Main Window/Release Notes/SupportState/SupportStatusInfoViewController.swift
Latest/Interface/Main Window/Release Notes/SupportState/SupportStatusButtonCell.swift
Latest/Interface/Settings/SettingsTabViewController.swift
Latest/Interface/Settings/General/GeneralSettingsViewController.swift
Latest/Interface/Settings/Locations/AppLocationViewController.swift
Latest/Interface/Settings/Locations/AppDirectoryCellView.swift
```

### 21.4 Remove localized `Main.strings`

Delete localized `Main.strings` only after every storyboard-owned string has been moved to Swift localization files.

### 21.5 Clean Xcode project

Remove stale references from:

```text
PBXBuildFile
PBXFileReference
PBXGroup
PBXResourcesBuildPhase
PBXSourcesBuildPhase
PBXVariantGroup
```

Prefer using Xcode project operations or a project-generation tool if available. Manual `.pbxproj` edits are possible but easy to corrupt.

---

## 22. Risk register

| Risk | Why it matters | Mitigation |
|---|---|---|
| SwiftUI `List` does not match `NSTableView` density | Main screen will look subtly wrong | Use `ScrollView + LazyVStack`, or bridge `NSTableView` if needed |
| Toolbar placement differs | macOS toolbar polish is very visible | Start with SwiftUI toolbar; fall back to `NSToolbar` bridge if needed |
| Release notes rendering changes | Current visible body is attributed text in `NSTextView`, not live WebKit | Wrap `NSTextView` and reuse `NSAttributedString` formatting first |
| Search focus/ESC behavior changes | Existing custom `NSSearchField` handles ESC | Use `NSSearchField` bridge initially |
| App icons flicker | Existing cell avoids unnecessary image updates | Cache icons and avoid resetting image when app identity is unchanged |
| Selection lost after updates | Snapshot changes frequently | Maintain selection by app identifier |
| Localization regressions | Storyboard strings are localized in many languages | Move keys deliberately and audit missing keys |
| Settings window resize behavior changes | Current settings has custom animated resizing and toolbar-tab sizing | Use an AppKit window/toolbar shell with fixed SwiftUI content sizes |
| Removing `Main.storyboard` breaks parity bridges/localization | Storyboard scenes are now replaced, but localized historical `Main.strings` may still contain strings worth auditing | Keep source/build no-storyboard checks in verification and migrate/delete localized strings deliberately |
| Duplicate update checks in flag mode | The old main controller starts scanning in `windowDidLoad()` | Gate old startup when SwiftUI main window is enabled |
| Progress reporting conflicts | `UpdateCheckCoordinator.progressDelegate` is a single weak delegate | Extract one progress service and have active UI observe it |
| Observer API mismatch | `AppProviding.addObserver` requires `NSObject` | Use NSObject-backed view models/adapters and remove observers on close |
| Removing storyboard too early | Breaks launch path and localized resources | Remove only after SwiftUI launch path passes checklist |
| Hidden controller logic | Some behavior may live inside old view controllers | Extract behavior to services before deleting controllers |

---

## 23. Implementation order in detail

### Phase 1 — Documentation and baseline

Deliverables:

```text
MIGRATION.md
baseline screenshots
measurements.md
fixture app data plan
```

No production code changes except tests/utilities.

### Phase 2 — Extract controller-owned behavior

Move logic out of view controllers into services/view models:

```text
checkForUpdates flow
updateAll flow
App Store update preparation/fallback
progress reporting
row actions
sort/toggle menu actions
search state
release notes loading state
app-provider observation adapter
window subtitle and Dock badge update count
```

The old AppKit UI should still call the extracted services. This reduces migration risk.

### Phase 3 — Add SwiftUI views with fixture data

Build views in isolation:

```text
UpdateRowView
UpdateSectionHeaderView
UpdatesSidebarView
ReleaseNotesDetailView hosting the programmatic AppKit ReleaseNotesViewController
```

Use fixture data first. Do not connect to live update scanning yet.

### Phase 4 — Add SwiftUI main window behind flag

Historical flag strategy: keep the old storyboard launch path while first adding SwiftUI behind a flag.

Add either:

```text
UserDefaults flag: UseSwiftUIMainWindow
Launch argument: --swiftui-main-window
```

or a compile flag:

```text
SWIFTUI_MAIN_WINDOW
```

When enabled in that historical strategy, do not create a second main window. Let the storyboard create the original `NSWindow`, then replace `MainWindowController.contentViewController` with the SwiftUI-hosted split view. Preserve the pre-swap frame and split position so screenshot comparison starts from the original window geometry. The current no-storyboard path instead creates the `NSWindow` programmatically at the approved default size.

### Phase 5 — Connect live model

Connect SwiftUI view models to:

```text
UpdateCheckCoordinator.shared.appProvider
AppListSettings.shared
UpdateQueue.shared
IconCache.shared
ReleaseNotesProvider
```

At this stage, SwiftUI UI should be functionally complete but not yet default.

### Phase 6 — Pixel parity loop

For each scenario:

```text
reset any screenshot-polluted MainWindowSize autosave if needed
launch old storyboard path and wait for update scanning to settle
capture old screenshot at natural window size
launch SwiftUI flag path and wait for the same data state
capture SwiftUI screenshot at the same natural window size
compare geometry
compare whole image
adjust metrics/styles
repeat
```

Do this before deleting any old UI code. The verification harness must not resize the window; a forced frame can create false positive or false negative parity results and can save the wrong frame into user defaults.

### Phase 7 — Switch default launch path

After parity:

```text
remove @main from AppDelegate
add SwiftUI @main App
remove NSMainStoryboardFile
make SwiftUI main window default
keep old controllers temporarily but unreachable
```

Run full QA.

### Phase 8 — Migrate or isolate remaining storyboard scenes

Before deleting `Main.storyboard`, handle every non-main-window scene that used to live there:

```text
settings window
general settings tab
locations settings tab
menu/storyboard-owned localized strings
```

Settings, the support-state popover, the sidebar, and the release-note pane are already ported out of storyboard-owned presentation. The remaining cleanup work is auditing menu/storyboard-owned localized strings and deleting stale legacy controller classes only after the current programmatic path remains verified.

### Phase 9 — Delete legacy UI

Delete storyboard and old controllers only after the SwiftUI launch path is proven.

### Phase 10 — Settings cleanup follow-up

Remove stale settings storyboard scenes and legacy settings controller classes after localization and storyboard-resource cleanup are ready.

---

## 24. Definition of done

The migration is done only when:

```text
[ ] App launches without Main.storyboard.
[ ] No main window UI depends on IBOutlet/IBAction controller wiring.
[ ] Main window is SwiftUI-first.
[ ] Update list is SwiftUI-first or intentionally AppKit-bridged for parity.
[ ] Release notes detail is SwiftUI-owned or intentionally AppKit-bridged for parity.
[ ] Menus and toolbar actions are routed through command objects/services.
[ ] Settings and support-state popover no longer depend on storyboard resources.
[ ] Storyboard resources are removed from the app target.
[ ] Localized storyboard strings are either migrated or deleted safely.
[ ] Existing unit tests pass.
[ ] Pixel parity tests pass.
[ ] Manual QA checklist passes.
[ ] No dead AppKit controller files remain in the target.
```

---

## 25. Practical recommendation

For this specific project, the best migration path is:

```text
SwiftUI for structure and state:
  main window
  split layout
  update rows
  section headers
  release notes state handling
  menus/commands

AppKit bridges where needed:
  NSWindow configuration
  NSToolbar if SwiftUI toolbar drifts
  UpdateTableViewController during pixel-parity sidebar verification
  ReleaseNotesViewController during pixel-parity release-note verification
  NSSearchField for ESC/focus parity
  NSVisualEffectView for exact header material
  NSTextView for attributed release notes display
  existing WebKit loader only inside ReleaseNotesProvider fallback
  existing settings window during first pass
```

This is the fastest route to a modern app that still looks like the original. A forced pure-SwiftUI rewrite would likely be slower and visually worse.
