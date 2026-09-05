# Latest architecture

Latest targets macOS 26+ and Swift 6 with complete concurrency checking. CI uses Xcode 26.6. The application remains one Xcode target; directories express ownership, and `script/check_structure.sh` independently type-checks Domain so its dependency boundary is enforced by Swift.

## Ownership and dependencies

- **App** assembles live dependencies in `AppEnvironment`, owns lifecycle, and routes commands.
- **Features** owns main-actor presentation state and view composition. Update actions and progress go through `AppUpdating`, not `UpdateQueue` or `UpdateOperation`.
- **Domain** contains app/update metadata, source-provided actions, and version rules. It has no dependency on Services, Features, or presentation frameworks. Services decide when to execute an action.
- **Services** owns discovery, repositories, caches, update orchestration, and release-note parsing. `AppUpdateService` adapts the operation queue to the feature-facing contract. Its queue can be isolated in tests; source actions are supplied by the app metadata under test.
- **Platform** contains Sparkle, App Store, install-helper, workspace, and AppKit integrations.
- **Support** contains shared presentation helpers, settings, telemetry, and operation infrastructure.

Inject the same `AppUpdating` instance through `AppEnvironment` into list and bulk-update models. Detail controls and both sidebar renderers receive it from the list model. Default live instances exist for standalone views and previews; their behavior must use the stored dependency. `UpdateProgressState` and `AppUpdateStateChange` are service contract values, independent of the queue implementation.

The current NSTableView sidebar and the existing AppKit drawing bridges are intentional. Refactoring service ownership must not change view hierarchy, geometry, fonts, colors, selection, or drawing code.

## Concurrency contracts

- App/feature presentation owners use `@MainActor`. Async stream tasks weakly capture owners and acquire a strong reference only while processing an event, not across the next suspension.
- `AppDataStore` protects its collection, identifier index, and ignored preferences with one `Mutex`. It returns immutable snapshots and runs caller predicates outside the lock. A separately protected work item preserves the 150 ms coalescing interval.
- `UpdateRepository` protects pending requests, matching indexes, and completion state with `Mutex`. Its serial queue preserves load/finalization ordering. Completion callbacks execute outside the mutex and can reenter the repository.
- Update progress and its callback share a mutex. Callbacks execute outside the lock; the queue installs observation before scheduling an operation. The base operation error is also protected.
- Operation subclasses still inherit Foundation's unchecked sendability contract. Operation state/index locks and main-actor observer registries remain necessary. The narrow UserDefaults wrapper documents Foundation's thread-safe API boundary. Filesystem observers and attributed-string transfer retain their existing manual synchronization contracts; this refactor does not claim all unchecked conformances have been removed.

## Release-note parsing

`ReleaseNotesSourceExtractors.swift` is the stable routing facade. Zed, Zoom, Chrome, and Navicat each have a dedicated extractor type. Shared HTML extraction, text normalization, and version selection live in separate files. Keep source-specific parsing inside its extractor and reuse shared helpers where the semantics are actually the same. The refactor preserves existing parsing rules and public entry points.

## Verification

- `./script/test.sh`: standalone Domain compilation, dependency checks, behavior, geometry, interaction, and visual regressions.
- `./script/benchmark_complexity.sh`: store, repository, parsing, and other algorithmic performance budgets.
- `./script/benchmark_migration.sh <label>`: shipping sidebar and UI performance budgets.
- `./script/audit_release_artifact.sh`: audit a built Release bundle.

`ProductionVisualParityTest` captures the real `LatestRootView`, including its shipping sidebar, in eight states: initial selection, changed selection, search, and fixed download progress in light and dark appearances. It writes `build/production-visuals`. Each state produces a root-view image and a direct NSTableView image (16 captures total): macOS omits material-composited sidebar contents from the root view's offscreen cache, so the populated table must be captured separately. The fixture asserts that rows and real icons are present. If `build/production-visual-reference` exists, every full-frame RGBA pixel must match it. Missing reference images fail the test.

For a structural refactor, capture references from the **original implementation** with the same harness, macOS/Xcode, screen scale, and machine. Copy those images into `build/production-visual-reference` before testing the changed implementation. Never replace references with changed output to make a test pass. These local references are intentionally not portable across OS rasterizer or system-icon changes. The checked-in gallery baselines and their existing tolerances remain unchanged and continue to run in CI.

`script/report_visual_parity.swift BEFORE AFTER --require-exact` reports full-image differences and fails on any changed pixel or missing image. Without `--require-exact`, it reports pixel differences without treating them as failures.

CI installs ripgrep, resolves the checked-in Sparkle lockfile without updating versions, runs the test gate, and uploads xcresult bundles and renderings. A local passing test run does not prove that a GitHub-hosted run has passed; remote verification follows publication of the change.
