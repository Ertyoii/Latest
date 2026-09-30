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

## Accepted sidebar app row migration

The completed heading, title, and search work was committed as `fa12730` on
2026-09-30 before starting this step. The unchanged rows passed the full suite:
258 tests, six skipped, zero failures. Twelve complete light/dark window
captures were saved before editing the row renderer.

`UpdateRowView` now uses SwiftUI for the app icon, title, installed and new
versions, date, support image, and separator. A small `NSTableCellView` hosts
the content, forwards native selection emphasis, and retains the existing
progress button. The table still owns selection, scrolling, context menus,
and swipe actions. Row height, icon size, metadata positions, inactive icon
dimming, and selected-row separator behavior are preserved.

- Dark: [before](visual-evidence/rows-before-dark.png) and
  [after](visual-evidence/rows-after-dark.png)
- Light: [before](visual-evidence/rows-before-light.png) and
  [after](visual-evidence/rows-after-light.png)

In sampled row regions, the name, version lines, support dot, and separator
have identical pixels. The 100×100 icon region differs only by small channel
rounding (RMS 0.375/255 light and 0.594/255 dark; no differences greater than
12/255). The 120×34 date region differs at 274 light and 272 dark pixels.
The complete UI is therefore visually close, not pixel-identical. Twelve
after captures also cover selection, filtering, progress, and pinned headers.

The final `./script/test.sh` run passed 258 tests with six skips and no failures.
Renderer-coupled text/image checks were replaced by painted-output checks for
first-frame app icons, support preference changes, selection text color, and
the complete long version string. A temporary 100pt version-width negative
control correctly failed with 665 missing glyph pixels; it was restored.
The native keyboard-selection and search typing/clear/Escape tests still pass.
An initial synthetic mouse-selection test could not deliver selection even
against unchanged AppKit rows in the settings-only test host, so it was not
retained as evidence of mouse parity. The subsequent keyboard-focus regression
and real running-app checks below cover the reported interaction failure.
Formatting, structure, and diff checks passed.

A fresh isolated AppKit control from `fa12730` and the final SwiftUI Release
benchmark produced:

| Metric | AppKit control | SwiftUI row |
| --- | ---: | ---: |
| Populated sidebar, p50 | 47.580 ms | 36.577 ms |
| Scroll step, p95 | 1.629 ms | 2.344 ms |
| Selection to detail, p95 | 3.486 ms | 3.066 ms |

All absolute performance, memory, and runtime-warning gates passed. Scrolling
increased by 0.715 ms (43.9%), exceeding the plan's 15% relative limit. The
relative cutover script reports **blocked** for scrolling. On 2026-09-30 the
user accepted the measured visual and performance differences. This is an
accepted exception to the row cutover criteria, not a passing relative gate.
No version bump, push, release, or installed-app replacement was performed.

### Keyboard focus repair

The user reported that Up/Down no longer navigated the sidebar. In the running
checkout build, clicking hosted row content selected the app but did not give
the native table keyboard focus. Both arrow keys left the selection unchanged.
The existing keyboard test had bypassed this failure by explicitly focusing
the table and calling `table.keyDown` directly.

A narrow row hosting subclass now gives keyboard focus to its enclosing table
after handling a mouse-down event. The regression test clicks the hit-tested
row content and delivers Up/Down through the window's current responder. It
failed before the repair (Down remained on Discord instead of selecting Cursor)
and passed after it. Real running-app input also verified ChatGPT → Final Cut
Pro → ChatGPT, skipping the section header to Discord, and repeated Down presses
scrolling an offscreen selection into view (vertical scroller value 0.530).

The final `./script/test.sh` run passed 258 tests, six skipped, zero failures.
Formatting, structure, and diff checks passed. This repair changes input focus
only; the accepted row layout and drawing remain the same.

### Selection flicker and rapid keyboard navigation

The user's 2026-09-30 recording showed dark text briefly appearing on the blue
native highlight before the hosted text became white. Native selection now
updates an observable row presentation directly, including selection emphasis
and separator visibility. It resolves text colors during the native selection
turn and reuses the existing icon, attributed name, version strings, and date.
The coordinator refreshes row content for snapshot or support-preference changes,
without rebuilding it for each selection or unchanged representable update.

The painted-color test selects and emphasizes a real native parent row while
leaving the hosted content's initial selection unchanged. It checks white text
without another model-content update. Restoring the old cached-selection rule
as a temporary negative control produced zero white glyph pixels and failed;
the repair was restored. The inactive-text and long-version checks also pass.

A new rapid-key case in the existing Release benchmark sends 120 repeated Down
events through the native table's current responder and includes model delivery,
layout, and drawing. Before the repair it reached row 87 instead of row 121:
34 selection steps were undone. A deferred table update had captured an earlier
selection and could restore it after another key event. Deferred updates now
read the current model when applied. The benchmark checks that all 120 steps
reach the expected row and selected app, and starts from an already visible row
so its frame measurements exclude an unrelated initial long-distance jump.

The final `row_selection_observed` Release run preserved all 120 steps:

| Metric | Final result |
| --- | ---: |
| Keyboard selection and sidebar render, p95 | 7.857 ms |
| Keyboard selection and sidebar render, maximum | 9.235 ms |
| Continuous scroll step, p95 | 2.281 ms |
| Selection to detail, p95 | 3.174 ms |

The keyboard case now has a 16 ms p95 budget. Its timing covers the sidebar;
asynchronous release-note retrieval is measured by the separate render cases.
The benchmark's existing absolute gates and runtime-warning checks passed.
The final full suite passed 258 tests, six skipped, zero failures; formatting,
structure, shell syntax, and diff checks also passed. In the restarted checkout
app, twelve rapid Down presses selected Delta from Discord, twelve Up presses
returned to Discord, and the final selected row painted white text on blue.

### Keyboard navigation optimization for a 120 Hz work budget

The user requested optimization toward 120 FPS on a display currently limited
to 60 Hz. Selection now uses property observation separately from the list's
Combine publications. Selecting a row invalidates the selected-app detail,
table selection input, and selected-app command buttons instead of rebuilding
the root sidebar, search, and unrelated menus. The table skips deferred work
when its native selection already matches the model. A fresh app object with
the same identifier still invalidates detail metadata after a provider refresh.

Row foreground colors and separator visibility now observe selection in small
leaf views. The immutable icon, attributed name, versions, date, and geometry
remain stable. Native selection still resolves foreground colors synchronously
to preserve white text on the first highlighted frame.

During keyboard Up/Down navigation, the detail header updates immediately and
the notes request waits for a 60 ms pause. A subsequent selection cancels that
pending request, so passing an app does not start unnecessary note retrieval or
web-page rendering. Mouse and programmatic selections request notes immediately.
The existing 200 ms loading indication and stale-result guards remain in place.
This is a focused change across six production files, with no layout redesign.

The new settled-selection test failed with the original immediate-request
behavior, then passed after coalescing was implemented. The refreshed-object
test also verifies observation of a replacement object with the same identifier.
The final full suite, `build/Latest-Tests-20260930-122557.xcresult`, contains 259
tests: 253 passed, six skipped, zero failures. Painted active/inactive selection,
long versions, search/keyboard focus, menus, and web interaction checks passed.
The test bundle records one priority-inversion runtime warning; the
Release migration benchmark's warning gate passed. Formatting and structure
checks passed.

Final Release benchmark: `build/migration-benchmark-keyboard_settled_notes.txt`.
The scroll and keyboard p95 work gates are now both **8.333 ms**, replacing the
earlier 28 ms scroll and 16 ms keyboard thresholds.

| Work metric | Final result |
| --- | ---: |
| Keyboard selection and sidebar rendering, p95 | 7.979 ms |
| Keyboard selection and sidebar rendering, maximum | 9.107 ms |
| Continuous scroll step, p95 | 3.034 ms |
| Selection to detail, p95 | 3.973 ms |
| Repeated selection memory growth | 13.56 MiB |

All 120 native keyboard selection steps were preserved, and all absolute work,
memory, and warning gates passed. These are main-thread workload timings, not
presented FPS. The p95 work target passes, but the keyboard maximum still
exceeds an 8.333 ms frame budget.

Actual window captures used ScreenCaptureKit alongside Instruments' SwiftUI
template. Both Release builds received the same paced 112-key workload:
28 Down, 28 Up, repeated twice. Native tool calls can take longer than the
requested 16.667 ms spacing; actual input rates are reported below. The window
was 768×516 points in light appearance. The final app catalog changed after the
interruption (Chrome updated and SamsungMagician appeared); this is a live-app
comparison, not a frozen-fixture percentage gate.

| Visible timing during input | Release before | Release final |
| --- | ---: | ---: |
| Actual inputs per second | 28.33 | 32.94 |
| Visible sidebar changes per second | 17.87 | 36.37 |
| Median gap between visible changes | 50.35 ms | 17.39 ms |
| p95 gap between visible changes | 96.05 ms | 66.81 ms |
| Maximum gap between visible changes | 183.69 ms | 100.28 ms |
| App-attributed hitches during input | 69 | 22 |

A final capture without Instruments measured 39.61 visible changes per second
at 31.13 inputs per second, a 16.84 ms median gap, a 50.41 ms p95 gap, and a
150.07 ms maximum. Visible changes include intermediate native scrolling frames,
so their count can exceed the input count. Unchanged capture samples are not
counted as app frames. Sampling itself remained near 16.67 ms throughout.

The optimization improves visible pacing and reduces measured hitches. It does
**not** establish a locked 60 FPS or certify 120 FPS; longer gaps remain and this
display can present only 60 frames per second. The remaining profile includes
SwiftUI layout/Core Animation transaction work in addition to synchronous row
color updates. Evidence and reproduction commands are recorded in
`build/keyboard-optimization-20260930.md` and its JSON report. The optimized
Release checkout build was launched; no installed-app replacement was made.

## Sidebar progress control migration and unpushed-change cleanup

The previous row migration and keyboard optimizations were committed first as
`6664262`. The sidebar control now uses a SwiftUI button and Canvas, with the
original paths, 24-point frame, pause bars, line widths, and backing alignment.
AppKit colors and path geometry remain data inputs; the sidebar no longer hosts
an `NSButton` or an `NSButtonCell`. The detail action capsule is a separate bridge
and was not included in this migration.

`SidebarUpdateStatus` owns one update-state stream for both the support dot and
progress control. Its state changes invalidate the status/control leaf, rather
than the row's icon, name, date, or version layout. Reusing a cell for another app
or update service resets observation by app/service identity. Repeated equivalent
presentations do not publish another view change. Waiting animation is owned by
SwiftUI's timeline; progress interpolation is owned by SwiftUI animation. Reduced
motion pauses the spinner and disables progress interpolation.

The row's previous second observer, custom button/cell, animation clock, native
control layout, and obsolete build references were removed. The two tests for
that deleted clock were removed with their production owner. No remaining
production or test caller references the three deleted files. This focused
change removes approximately 570 net production Swift lines.

The original sidebar hides its progress control on error and restores the support
dot. The migrated control preserves that behavior. Cancel is available while
downloading or extracting; waiting states remain non-actionable. A real window
mouse click verified that Cancel reaches only the displayed app's injected queue.
Temporarily disconnecting the button action caused that test to fail at the
cancellation assertion; restoring the action passed.

Before editing production code, the native renderer was captured and tested in
light/dark, selected/unselected, idle, waiting, downloading, extracting, and error
states. Both renderers produced 616×120-pixel row captures on this 2× display.
Across all 20 comparisons, **no pixels outside the control region changed**.
All eight idle/error comparisons match exactly. The determinate indicators have
414–807 changed stroke pixels in dark appearance and 538–790 in light appearance;
the largest per-channel difference is 49/255. The visible center, diameter, pause
bars, colors, and arc direction remain the same, but this is **not an exact RGBA
match** for the animated control. Spinner captures also differ in animation
phase, so a strict instantaneous spinner comparison is not a static parity proof.
No visual baseline was replaced with candidate output and no tolerance was
relaxed. Selected download captures and the comparison JSON are saved under
`docs/visual-evidence/sidebar-control-*` for review.

The cleanup review covered all unpushed changes relative to refreshed
`origin/develop`: search and focus restoration, title/header drawing, row/state
observation, table scheduling and selection, command invalidation, settled note
requests, their tests, Xcode paths, and benchmark/artifact scripts. The complexity
scanner's callback-loop flags were inspected as leads, not treated as defects.
The identity-aware selection wrapper, native table/responder boundary, search
window reader, and detail rasterization bridge still have concrete callers and
behavior contracts, so they were retained. No speculative algorithm rewrite or
test-only production seam was added.

Final validation:

| Check | Result |
| --- | --- |
| `./script/test.sh` | 259 tests, six skipped, zero failures |
| Keyboard selection/render work | p95 6.983 ms; maximum 7.489 ms; 120/120 steps preserved |
| Continuous scroll work | p95 2.428 ms |
| Selection to detail | p95 3.288 ms |
| Repeated selection memory growth | 13.92 MiB; below 24 MiB |
| Absolute Release benchmark gates | All pass, including the 8.333 ms keyboard/scroll work budgets |
| Runtime warning gate | Zero matching warnings |
| Formatting, structure, shell syntax, diff checks | Pass |

Full test bundle: `build/Latest-Tests-20260930-142640.xcresult`. Benchmark report:
`build/migration-benchmark-sidebar_control.txt`. The original control capture
passed before migration; the new rendered-state and real mouse-action checks
passed after migration. These timings measure work, not presented FPS. No version
bump, push, release, or installed-app replacement is part of this change.
