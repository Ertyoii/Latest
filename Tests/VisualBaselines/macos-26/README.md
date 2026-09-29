# macOS 26 visual references

These 14 PNGs are reviewed snapshots of the current migration gallery, captured
on the `macos-26` GitHub runner with Xcode 26.6. CI compares fresh renders with
these checked-in files; it does not build an older app to generate expectations.

The current set came from the candidate captures in [CI run 36529255081](https://github.com/Ertyoii/Latest/actions/runs/36529255081)
for commit `a0fb2c5`. The four release-notes views reflect the WebKit renderer
introduced before that run. The other ten views matched the previous renderer
pixel for pixel on that runner.

For an intentional visual change, run
`LATEST_RECORD_VISUAL_BASELINES=1 ./script/test.sh` on macOS 26, review the
images in `/tmp/latest-visual-candidates`, then copy the approved images here.
The test still compares candidates with the checked-in references, so a failed
run is expected until those files are updated.
