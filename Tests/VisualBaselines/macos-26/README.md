# macOS 26 visual references

The opt-in UI suite compares these 14 reviewed PNGs on macOS 26. The seven
`main-*` images are historical references whose compared regions contain only
production detail-header/body content (including RTL, empty and error states).
Their mock sidebar pixels are excluded. The current detail fixture leaves that
area blank; sidebar tests open LatestMainWindowScene and inspect its real rows.
The other seven references cover production locations, update-action and toolbar
controls. Original pixels have not been regenerated or relaxed.
Provenance: commit `a0fb2c5`, [CI run 36529255081](https://github.com/Ertyoii/Latest/actions/runs/36529255081).

For an intentional visual change, compare the original and candidate on the
same system, then run `LATEST_RECORD_VISUAL_BASELINES=1 ./script/test.sh --ui` on
macOS 26. Review `/tmp/latest-visual-candidates` before copying approved images
here. Tests keep comparing against existing references until they are updated.
