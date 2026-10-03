# macOS 26 visual references

The opt-in UI suite compares these 14 reviewed PNGs on macOS 26. The seven
`main-*` images are historical references whose compared regions contain only
production detail-header/body content (including RTL, empty and error states).
Their mock sidebar pixels are excluded. The current detail fixture leaves that
area blank; sidebar tests open LatestMainWindowScene and inspect its real rows.
The other seven references cover production locations, update-action and toolbar
controls. The eleven unchanged references retain their original pixels.
Original provenance: commit `a0fb2c5`, [CI run 36529255081](https://github.com/Ertyoii/Latest/actions/runs/36529255081).

The three `locations-*` references use SwiftUI folder symbols, matching the
settings redesign. They were reviewed from macOS 26/Xcode 26.6 captures in
[CI run 37122943394](https://github.com/Ertyoii/Latest/actions/runs/37122943394),
source revision `023ca00`. Original and candidate production settings were
also reviewed on the same local system. Normalized pixel comparison found
changes only in the two reachable-folder icons; all other pixels matched.
Comparison thresholds remain unchanged.

For an intentional visual change, compare the original and candidate on the
same system, then run `LATEST_RECORD_VISUAL_BASELINES=1 ./script/test.sh --ui` on
macOS 26. Review `/tmp/latest-visual-candidates` before copying approved images
here. Tests keep comparing against existing references until they are updated.
