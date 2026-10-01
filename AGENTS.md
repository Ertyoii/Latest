# Latest

- Complete the requested work, preserve unrelated changes, and keep explanations concise. Explicit user instructions take precedence over skill guidance.
- For analysis or review requests, inspect and report; implement only when requested. For fixes, make reasonable implementation choices and complete in-scope local work without unnecessary confirmation.
- Use `README.md` for current commands and architecture when relevant. Search production code under `Latest/` and tests under `Tests/`; exclude generated build trees from source discovery.
- For UI changes, verify the affected production interaction as well as appearance. Scrolling checks should cover normal key repeat, reversal, list edges, multiline rows, pinned headers, and mouse targeting. Compare original and candidate on the same system before updating visual references.
- Compare performance using the same hardware and representative workload. Report unmet targets explicitly; a passing benchmark alone does not establish that the interaction feels correct.
- For substantial tasks with independent investigations, use up to two read-only subagents when this would improve speed or confidence. Give each a bounded question and request concise findings with file references. Keep implementation and final validation with the main agent; do not run concurrent Xcode jobs against shared build products.
- Use skills only for their relevant workflow. Follow this repository's commands when a reusable skill assumes another project's tooling; do not expand an ordinary test edit into a broad audit or publication workflow.
- Keep documentation focused on current behavior. Store experimental logs and captures under `build/` unless needed as reviewed test baselines. At major phase changes, provide a compact handoff with current decisions, unresolved requirements, and relevant evidence paths.
- Read or use release and app-replacement skills only when the user explicitly requests a release or replacement. A request to fix, build, test, or launch the app does not authorize release or replacement.
- When replacement is requested, check for unshipped features or fixes. If present, bump the version, update release notes, run required checks, commit the relevant changes, and push successfully before rebuilding and replacing the installed app. The replacement request authorizes this sequence. If the changes are already shipped, avoid an unnecessary version bump or commit.
- Verify the installed version and running app path after replacement.
- Run checks appropriate to the change; use `./script/test.sh` for app changes. Repeat or broaden checks only for new changes, failures, or unresolved concerns.
