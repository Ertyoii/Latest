# UI migration decision record

Status: the application uses SwiftUI composition with a shipping NSTableView sidebar. The alternate SwiftUI List experiment was retired during the September 2026 cleanup.

## Retained decisions

- SwiftUI owns application scenes, settings, commands, and feature state.
- The AppKit sidebar remains responsible for row geometry, keyboard selection, context menus, and scrolling. Its measured behavior takes precedence over eliminating framework boundaries.
- Narrow AppKit text, search, window, and update-button bridges remain where they supply required macOS behavior.
- Update actions flow through the injected `AppUpdating` service boundary.
- The previous native sidebar, renderer environment switch, unused global progress feed, and experimental screenshots have been removed. Git history preserves the experiment.

## Current verification

Use [ARCHITECTURE.md](ARCHITECTURE.md) for maintained ownership and concurrency contracts, and [the README](../README.md#build-from-source) for build instructions.

- `./script/test.sh` covers behavior and the active visual baselines.
- Keyboard and menu tests exercise the shipping table rather than unused policy calculations. Row-width tests inspect the laid-out text field.
- `./script/benchmark_migration.sh <label>` measures the shipping UI. The historical script and telemetry names remain to preserve benchmark continuity; there is no renderer-selection argument.
- `./script/prepare_ci_visual_reference.sh` renders an immutable original with the current test harness on the CI runner. References must not be regenerated from changed application code.
- `./script/audit_release_artifact.sh <release-app-path>` checks the release bundle.

## Future changes

Any replacement of the sidebar or drawing bridges must preserve real population, interaction, accessibility, geometry, and performance. A second renderer should be introduced only as part of a concrete replacement effort with an exit criterion.

The former implementation blueprint and embedded code listings are available in Git history; they are not current implementation instructions.
