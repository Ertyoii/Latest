---
name: replace-macos-app-build
description: Build and replace a local macOS app in /Applications, remove duplicate build copies, and repair LaunchServices or Spotlight resolution. Use for installing the newest local app build or fixing duplicate app entries.
---

# Replace macOS App Build

Deliver one installed app at `/Applications/<install-name>.app`, with the requested version and macOS resolving to that path. Build products are temporary installation inputs. Remove them after verifying the installed copy; retaining the fresh build requires an explicit user request.

Follow the user's current instructions and existing authorization. Infer routine project, scheme, and app names from the repository and installed bundle. Ask only when identity or scope remains ambiguous. For Latest, a replacement request includes preparing and pushing relevant unshipped changes as described below. For other repositories, follow their release authorization. Changes to other apps and restarting Dock require separate authorization.

## Decide the version, then ship the source

1. Read the working-tree status, configured remote/upstream, current marketing version, and release notes. Query the latest published release for this repository and channel (for GitHub, use `gh release list` / `gh release view`; exclude drafts and unrelated prereleases). Do not use the installed app's version as the published version.
2. If there are no published releases, check the project's actual distribution convention. Latest Dev currently ships through commits pushed to `origin/develop`: fetch that branch and read its marketing version, release notes, and commit as the published-source fallback. Old upstream tags are not Latest Dev releases. Report which source was used. A failed remote lookup is unknown, not proof that no release exists.
3. Compare versions numerically and compare relevant source changes with that published revision. If the current version is already newer, retain it. If it equals the published version and relevant changes remain unshipped, bump once using the repository's version convention and update release notes. If the version is behind, reconcile the remote state before choosing a version; never downgrade or reset unrelated work. If the requested source is already shipped, reuse its version without an empty release commit. Let the project's build-number mechanism own the build number.
4. Commit only relevant changes and push to the intended branch successfully before building and replacing. Reuse an existing unpushed commit when appropriate. Stop if the push fails; do not install an unpublished candidate while reporting it as shipped.

Replacement is a version-and-install workflow. Do not run the app's test suite, visual snapshots, benchmarks, evaluations, baseline comparisons, or test audits as part of it. Use validation evidence from the implementation task when available; do not rerun it. A build and installed-bundle verification are required. Run a test or evaluation only if the user separately requests it in the current task.

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
