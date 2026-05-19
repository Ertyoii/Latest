# Latest Optimization Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize and simplify the Latest macOS project one scoped change at a time, with a build and code-review gate after every change.

**Architecture:** Keep each optimization narrow and independently shippable. Start with project-level Xcode/Swift modernization, then move through localized model and UI simplifications so failures are easy to isolate.

**Tech Stack:** macOS AppKit, Xcode project build settings, Swift 6.3.2 from Xcode 26.5, xcodebuild with repo-local DerivedData and module caches.

---

### Task 1: Upgrade Project Toolchain Settings

**Files:**
- Modify: `Latest.xcodeproj/project.pbxproj`

- [x] Set the project object compatibility and Swift build settings for the installed Xcode 26.5 toolchain.
- [x] Build with repo-local caches using `xcodebuild -project Latest.xcodeproj -scheme Latest -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages CODE_SIGNING_ALLOWED=NO build`.
- [x] Review the diff for compatibility risks and fix any compile or review findings before continuing.

### Task 2: Optimize App List Snapshot Generation

**Files:**
- Modify: `Latest/View Model/AppListSnapshot.swift`
- Test: `Tests/VersionParserTest.swift` or a new focused test file if target membership is available

- [x] Evaluate tests for section grouping and filtering behavior. Existing scheme test action is unavailable in this checkout, so this was covered by code review plus build gates instead of new runnable tests.
- [x] Replace repeated filtered passes with a single grouping pass after filtering and sorting.
- [x] Build with the same xcodebuild command.
- [x] Review the diff for behavior changes and fix findings before continuing.

### Task 3+: Continue The Prioritized Optimization List

Continue one item at a time:
- Table diff simplification.
- Table controller extraction.
- Observation/state notification consolidation.
- Async/await migration for low-risk networking and release notes code.
- App Store lookup request caching and retry simplification.
- UpdateRepository decomposition and safer cache parsing.
- Recoverable errors for user/environment-driven failure paths.
- Sleep-based progress throttling replacement.

Each item must follow the same gate: implement one scoped change, build, code review, fix all clear-or-important findings, then proceed.
