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
  -> SwiftUI settings window eventually
  -> small AppKit bridges only where they preserve native macOS behavior
```

The app should still feel like the original Latest app. The user should not feel that the UI was replaced by a generic SwiftUI mockup.

---

### Evaluation after repo audit

The overall plan is sound: a parallel SwiftUI implementation behind a flag is the right migration shape for this app. The main adjustments after checking the current repo are:

1. The visible release notes pane is `NSTextView` + `NSAttributedString`, not a live `WKWebView`. WebKit exists in the loading/conversion path, so the first SwiftUI detail pane should bridge the current attributed text rendering rather than switch the visible body to `WKWebView`.
2. `AppProviding.addObserver` currently requires an `NSObject` observer, and `UpdateCheckCoordinator.progressDelegate` is a single weak delegate. SwiftUI view models need an observation adapter or `NSObject` inheritance, and update-check progress should be extracted before both UIs can safely coexist.
3. `Main.storyboard` contains more than the main window: app menu wiring, the main window, settings, localized storyboard strings, and the support-state popover. Removing the storyboard resource must wait until settings and popovers are migrated or moved out of `Main.storyboard`.
4. The feature-flag launch path must avoid starting the old controller and the new SwiftUI window at the same time. The old `MainWindowController.windowDidLoad()` currently starts an update check immediately.
5. The project currently targets macOS 26 and Swift 6, so new SwiftUI-only state can use the Observation framework where it helps. Do not let that become a reason to rewrite existing model logic during the first pass.

---

## 2. Non-goals

Do not do these during the first migration pass:

1. Do not redesign the product.
2. Do not replace the update-checking logic.
3. Do not change sorting/filtering semantics.
4. Do not rewrite Sparkle/App Store/Homebrew update logic.
5. Do not delete `Main.storyboard` before the SwiftUI main window, settings, support-state popover, and menu/localization replacements are visually and functionally proven.
6. Do not use default SwiftUI `List` styling if it prevents exact layout parity.
7. Do not hardcode English strings; preserve localization.
8. Do not remove AppKit completely just to claim the app is “pure SwiftUI.” Small AppKit bridges are acceptable when they protect native behavior.

---

## 3. Current repo facts that drive the migration

### 3.1 App entry and storyboard

Current app entry is:

```swift
@main
class AppDelegate: NSObject, NSApplicationDelegate
```

`Latest/Resources/Info.plist` still declares:

```xml
<key>NSMainStoryboardFile</key>
<string>Main</string>
```

So the app is currently launched through the storyboard-backed window scene. A SwiftUI `@main App` cannot be added until the existing `@main` annotation is removed or converted.

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

The SwiftUI version should initially preserve that `NSAttributedString`/`NSTextView` rendering path. Keep `WebContentLoader` and WebKit in the provider fallback path, but do not switch the visible detail pane to a live `WKWebView` unless pixel comparison proves it is closer.

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
list content top inset: 78
scroll view bottom scroller inset: 10
release notes text inset: 14
main window storyboard content size: 1004 x 495
main window minimum size: 350 x 300
release notes header storyboard height: 119
```

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
      ReleaseNotesDetailView.swift
      ReleaseNotesHeaderView.swift
      ReleaseNotesContentView.swift
      ReleaseNotesLoadingView.swift
      ReleaseNotesErrorView.swift
      AttributedTextViewRepresentable.swift
      WebViewFallbackSupport.swift         # only if provider fallback needs UI-owned WebKit later
      SupportStatePopoverView.swift

    Settings/
      SettingsWindowView.swift
      GeneralSettingsView.swift
      LocationsSettingsView.swift

    Shared/
      DesignTokens.swift
      VisualMetrics.swift
      NativeVisualEffectView.swift
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
    static let listTopInset: CGFloat = 78
    static let scrollBottomInset: CGFloat = 10
    static let releaseNotesTextInset: CGFloat = 14

    // Measure these from the current app before finalizing.
    static let sidebarMinWidth: CGFloat = 320
    static let sidebarIdealWidth: CGFloat = 360
    static let detailMinWidth: CGFloat = 480
    static let mainWindowMinWidth: CGFloat = 350
    static let mainWindowMinHeight: CGFloat = 300

    static let appIconSize: CGFloat = 40
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

### Option A — safest initial path

Keep `AppDelegate @main` temporarily and create a SwiftUI-hosted replacement window behind a flag.

Use this for early parity work because it avoids changing launch semantics too soon.

The current storyboard main window starts an update check in `MainWindowController.windowDidLoad()`. In flag mode, gate that startup path so the old controller does not kick off scanning, claim `progressDelegate`, or flash a second window before the SwiftUI window is shown.

Example:

```swift
final class SwiftUIMainWindowController: NSWindowController {
    init(environment: AppEnvironment) {
        let rootView = MainWindowView(environment: environment)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = Bundle.main.localizedInfoDictionary?[kCFBundleNameKey as String] as? String ?? "Latest"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

Feature flag:

```swift
enum LaunchMode {
    static var useSwiftUIMainWindow: Bool {
        UserDefaults.standard.bool(forKey: "UseSwiftUIMainWindow")
    }
}
```

Then retain the SwiftUI window controller from `AppDelegate`:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var swiftUIWindowController: SwiftUIMainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if LaunchMode.useSwiftUIMainWindow {
            storyboardWindowController?.close()
            swiftUIWindowController = SwiftUIMainWindowController(environment: .live)
            swiftUIWindowController?.showWindow(nil)
        }
    }
}
```

This is temporary. Remove it after parity.

### Option B — final path

Convert to SwiftUI lifecycle.

Steps:

1. Remove `@main` from `AppDelegate`.
2. Rename it to `LegacyAppDelegate` or keep `AppDelegate` without `@main`.
3. Remove `NSMainStoryboardFile` from `Latest/Resources/Info.plist`.
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

Because the existing `AppDelegate` only terminates the app when the last window closes, this conversion should be low-risk after the SwiftUI window is proven.

Removing `NSMainStoryboardFile` stops storyboard auto-launch. It does not mean the `Main.storyboard` resource can be deleted yet if settings or support-state popovers are still loaded from it.

---

## 11. Main window remake

### 11.1 Target structure

```swift
struct MainWindowView: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        MainSplitView(
            updatesViewModel: environment.updatesListViewModel,
            releaseNotesViewModel: environment.releaseNotesViewModel
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
    @ObservedObject var releaseNotesViewModel: ReleaseNotesViewModel

    var body: some View {
        HSplitView {
            UpdatesSidebarView(viewModel: updatesViewModel)
                .frame(
                    minWidth: VisualMetrics.sidebarMinWidth,
                    idealWidth: VisualMetrics.sidebarIdealWidth
                )

            ReleaseNotesDetailView(viewModel: releaseNotesViewModel)
                .frame(minWidth: VisualMetrics.detailMinWidth)
        }
    }
}
```

If `HSplitView` cannot reproduce the old divider behavior, use an `NSSplitViewController` bridge with SwiftUI views embedded as `NSHostingController`s. Pixel parity beats architectural purity.

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

### 15.1 State model

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

This keeps the old behavior where the loading indicator is delayed slightly to avoid flicker.

### 15.3 Header

The old header uses `NSVisualEffectView`. SwiftUI `Material` may be close, but not always pixel-identical. Start with a small AppKit bridge:

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

Start with an `NSTextView` wrapper because the old visible body is an attributed-text view. Preserve `ReleaseNotesTextViewController.format(_:)` behavior: strip custom colors/backgrounds/shadows, reset the base font, keep bold/italic/link attributes, and apply the same scroll/content insets.

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

Do settings after the main window.

Reason: current settings use an `NSTabViewController` and custom window resizing animation. Rewriting this before the main window adds risk without helping the core migration.

However, settings currently live inside `Main.storyboard`. If settings are kept as AppKit during main-window cutover, either keep `Main.storyboard` as a resource and instantiate only the settings scene explicitly, or move settings into a separate storyboard/nib before deleting the main storyboard resource.

Recommended sequence:

```text
Phase 1: keep existing settings controllers
Phase 2: expose settings model/state cleanly
Phase 3: rebuild General tab in SwiftUI
Phase 4: rebuild Locations tab in SwiftUI
Phase 5: recreate window resizing animation if still wanted
Phase 6: remove SettingsTabViewController and related storyboard scenes
```

Settings parity requirements:

```text
same tab labels
same window title behavior
same content size per tab
same animated resize behavior or deliberate approved replacement
same UserDefaults keys
same localization keys
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

Remove from `Latest/Resources/Info.plist`:

```xml
<key>NSMainStoryboardFile</key>
<string>Main</string>
```

### 21.2 Remove storyboard resource

Remove `Main.storyboard in Resources` from the app target.

Do this only after settings and the support-state popover no longer depend on `Main.storyboard`. Removing `NSMainStoryboardFile` for launch is safe earlier; removing the storyboard resource is not.

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

Delete these only after settings and popover equivalents exist or are moved:

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
| Settings window resize behavior changes | Current settings has custom animated resizing | Keep settings AppKit until main window is done |
| Removing `Main.storyboard` breaks settings/popovers | Settings and support-state popover currently live in the same storyboard | Keep the resource, port those scenes, or move them before deletion |
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
ReleaseNotesHeaderView
ReleaseNotesContentView
ReleaseNotesDetailView
```

Use fixture data first. Do not connect to live update scanning yet.

### Phase 4 — Add SwiftUI main window behind flag

Keep old storyboard launch path.

Add either:

```text
UserDefaults flag: UseSwiftUIMainWindow
```

or a compile flag:

```text
SWIFTUI_MAIN_WINDOW
```

Launch SwiftUI window only when enabled.

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
capture old screenshot
capture SwiftUI screenshot
compare geometry
compare whole image
adjust metrics/styles
repeat
```

Do this before deleting any old UI code.

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

Before deleting `Main.storyboard`, handle every non-main-window scene still living there:

```text
settings window
general settings tab
locations settings tab
support-state popover
menu/storyboard-owned localized strings
```

Either port them to SwiftUI or move them to separate AppKit resources that are explicitly loaded.

### Phase 9 — Delete legacy UI

Delete storyboard and old controllers only after the SwiftUI launch path is proven.

### Phase 10 — Settings follow-up

If settings were isolated but not yet ported during the main migration, port them after the main window is stable.

---

## 24. Definition of done

The migration is done only when:

```text
[ ] App launches without Main.storyboard.
[ ] No main window UI depends on IBOutlet/IBAction controller wiring.
[ ] Main window is SwiftUI-first.
[ ] Update list is SwiftUI-first or intentionally AppKit-bridged for parity.
[ ] Release notes detail is SwiftUI-first with necessary attributed-text/AppKit bridge.
[ ] Menus and toolbar actions are routed through command objects/services.
[ ] Settings and support-state popover no longer depend on deleted storyboard resources.
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
  NSSearchField for ESC/focus parity
  NSVisualEffectView for exact header material
  NSTextView for attributed release notes display
  existing WebKit loader only inside ReleaseNotesProvider fallback
  existing settings window during first pass
```

This is the fastest route to a modern app that still looks like the original. A forced pure-SwiftUI rewrite would likely be slower and visually worse.
