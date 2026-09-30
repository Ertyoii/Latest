# SwiftUI pixel parity investigation

Investigation on 2026-09-29, starting from `4326fdc` on macOS 27.0.1 with
Xcode 27.0. The checkout was clean. The initial investigation did not change
the shipping UI. The user subsequently accepted the measured section-header
difference and authorized migrating that part.

## Original capture

The unchanged app passed `./script/test.sh`: 257 tests, six skipped, zero
failures. A second run produced byte-identical results for all 32 PNGs from
`ProductionVisualParityTest`. That apparent stability is insufficient: its
`NSHostingView.cacheDisplay` image omits the selected sidebar row's text and
material, while its separate `NSTableView.cacheDisplay` image omits the row
text. Neither bitmap represents the complete on-screen UI.

I captured the same production fixture with ScreenCaptureKit's desktop
independent window filter. This included the real row text, selection,
material, search field, detail, and titlebar. Repeated runs of the unchanged
source did not match exactly in six of twelve window states. The first light
state differed at two pixels; selection and search differed at 99 pixels
each; downloading differed at five pixels in light and dark; the dark pinned
state differed at 3,500 pixels. Most changes were one or two 8-bit channel
values. A subsequent attempt to wait for identical full-window frames did
not finish the production-state test after more than three minutes, so that
capture method is not currently a usable zero-difference gate. The capture
prototype was removed from the test suite.

Because the unchanged full-window capture could not self-match, the proposed
mandatory exact gate and its one-pixel-displacement and blank-surface negative
controls were not installed. The larger state matrix, interaction adaptation,
and performance cutover were not used to approve any replacement.

The 14 checked-in gallery references target macOS 26 with Xcode 26.6, so the
gallery raster test skips on this macOS 27 host. CI was not run or changed.
No reference images or tolerances were changed.

## Smallest drawing prototype

I rendered `AppKitUpdateSectionHeaderContentView` and a SwiftUI `Text` header
in separate laid-out windows, then cached both into fixed 616×54 RGBA
bitmaps. The SwiftUI view received the original `NSTextField`'s exact
`NSAttributedString`. A 1.5-point offset aligned both glyph bounding boxes
at pixel coordinates `(44, 19)` through `(316, 44)`. The images still
differed at 2,953 of 33,264 pixels. AppKit produced 2,920 nontransparent
glyph pixels; SwiftUI produced 2,866. The remaining difference is text
rasterization, not a simple position or font-attribute mismatch.

- [AppKit reference](visual-evidence/section-header-appkit-macos27.png)
- [SwiftUI prototype](visual-evidence/section-header-swiftui-macos27.png)

The initial prototype was removed at that point. The row, capsule control,
and table remained unchanged because there was no trustworthy complete-window
exact gate to approve them. The search field's native editing geometry and
Escape focus restoration, toolbar title alignment, and helper alert's
suppression checkbox also retained their existing AppKit boundaries at that
stage.

## Accepted section-header migration

After reviewing the prototype screenshot, the user accepted its raster
difference for the section header. `UpdateSectionHeaderView` now draws that
content with SwiftUI `Text`, reusing the prior localized HTML count formatting
and font attributes. `UpdatesTableBridge` hosts the SwiftUI view in its
existing pinned group row. The AppKit header view was removed. Other sidebar
components and AppKit boundaries were not changed.

`./script/test.sh` passed 257 tests with six skips and no failures. The
Release migration benchmark passed all absolute load, scroll, selection,
render, memory, and runtime-warning gates. This exception applies to the
section header only; it does not establish exact parity for the remaining UI.
No version bump, release, installed-app replacement, or push was performed.

## Toolbar title follow-up

The installed app's `Updates` title was present in the accessibility tree but
missing from the actual window. A hosted full-window capture reproduced it:
the old AppKit title field had the expected frame in the toolbar region, yet
was composited behind the toolbar. Geometry-only coverage had missed this.

The title now uses a SwiftUI toolbar item with its shared background hidden.
The window accessor remains only for window configuration. A rendered-window
regression test checks that the title is painted near the detail panel's left
edge. The full test suite passed: 257 tests, six skipped, zero failures.
The installed app was not replaced.

## Accepted search field migration

Before changing search, the full test suite passed 257 tests (six skipped), and
the unmodified hosted window was captured in twelve light/dark fixture states
with ScreenCaptureKit. The search field now uses a SwiftUI `TextField`, symbol,
and clear button inside the existing glass capsule. A narrow window reader
retains the previous responder so Command-F and Escape keep their behavior.
The old `NSSearchField` bridge was removed.

- [Before, empty dark](visual-evidence/search-before-empty-dark.png) and
  [after, empty dark](visual-evidence/search-after-empty-dark.png)
- [Before, filtered dark](visual-evidence/search-before-filtered-dark.png) and
  [after, filtered dark](visual-evidence/search-after-filtered-dark.png)

The 580×66-pixel search region is visually close but not byte-identical.
With a greater-than-12/255 per-channel threshold, 411 pixels differ in the
empty light capture and 741 in empty dark; the populated captures differ at
1,368 light and 2,739 dark pixels, mainly in text selection and control glyphs.
This does not meet the original exact-pixel requirement. After reviewing the
before/after captures, the user approved proceeding with the search migration
on 2026-09-30. This accepted visual difference applies to search only.

The new real-input test checks typing, Escape returning focus to the table,
and clicking Clear. `./script/test.sh` passed 258 tests with six skips and no
failures. The Release benchmark passed its absolute gates, and comparison with
the pre-search `swiftui_header` run passed all relative startup, scroll, and
selection gates. No release, installed-app replacement, or push was performed.
