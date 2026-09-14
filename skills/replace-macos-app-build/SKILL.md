---
name: replace-macos-app-build
description: Build and replace a local macOS app in /Applications, remove duplicate build copies, and repair LaunchServices or Spotlight resolution. Use for installing the newest local app build or fixing duplicate app entries.
---

# Replace macOS App Build

Deliver one installed app at `/Applications/<install-name>.app`, with the requested version and macOS resolving to that path. Build products are temporary installation inputs. Remove them after verifying the installed copy; retaining the fresh build requires an explicit user request.

Follow the user's current instructions and existing authorization. Infer routine project, scheme, and app names from the repository and installed bundle. Ask only when identity or scope remains ambiguous. This skill does not authorize a version bump, commit, push, Dock restart, or changes to other apps by itself.

## Execute

Use [the installer](scripts/replace_macos_app_build.sh) relative to **this loaded skill's folder**. Do not silently substitute a different repository copy.

From the repository root, for Latest:

```sh
<skill-folder>/scripts/replace_macos_app_build.sh \
  --project Latest.xcodeproj --scheme Latest \
  --configuration Release --derived-data build/DerivedData \
  --app-name 'Latest Dev' --install-name 'Latest Dev' \
  --bundle-id com.max-langer.Latest.dev --artifact-name Latest --open
```

- Default to **Release** for normal use. The product name may still contain `Dev`; that is separate from the build configuration. Honor an explicit Debug request, but still remove its build copy after installation unless the user asks to keep it (`--keep-build`).
- Inspect installed and built bundle identity before replacement. Never overwrite a different bundle identifier. The script verifies an expected identifier, stops the matching app, copies it, and checks complete bundle content before cleanup.
- Enumerate duplicate products under repository `build/` and user Xcode DerivedData. Cleanup matches both exact product names and bundle identifier, unregisters each duplicate, then removes it—including the fresh installation source. Do not delete unrelated apps, source, caches, logs, or result bundles.
- Register and index `/Applications` after cleanup. Open that installed path when requested or when completing the normal replacement workflow. Restart Dock only when explicitly requested or a persistent Dock item still points at the removed copy.
- `--dry-run` prints the plan without building or changing state; `--clean-artifacts` remains accepted for older callers, but cleanup is now the default.

## Verify and report

Verify marketing/build version and bundle identifier from the installed plist. Verify the full copy **before** removing the source: Debug executables can be launcher stubs whose hashes remain unchanged; the `.debug.dylib` contains the implementation.

After cleanup, enumerate matching products again, verify LaunchServices resolves to `/Applications`, and check the running process path after launch. Only the installed app should remain unless retention was explicitly requested. Spotlight can lag; distinguish stale indexed entries from files that still exist, and do not claim the UI is fixed without observing it.

On build, identity, or copy-verification failure, stop before deleting build products. Keep enough evidence to recover and report the actual blocker. Run focused script checks and an installation verification for installer changes; do not rerun the application's entire test suite for a documentation-only skill edit.

Report the installed version/path, cleanup result, and any unresolved resolution issue concisely. If permission review blocks a required operation, identify the operation and reason rather than reporting completion.
