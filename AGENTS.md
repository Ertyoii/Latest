# Latest

- Complete the requested work, preserve unrelated changes, and keep explanations concise. Explicit user instructions take precedence over skill guidance.
- Read or use release and app-replacement skills only when the user explicitly requests a release or replacement. A request to fix, build, test, or launch the app does not authorize release or replacement.
- When replacement is requested, check for unshipped features or fixes. If present, bump the version, update release notes, run required checks, commit the relevant changes, and push successfully before rebuilding and replacing the installed app. The replacement request authorizes this sequence. If the changes are already shipped, avoid an unnecessary version bump or commit.
- Verify the installed version and running app path after replacement.
- Run checks appropriate to the change; use `./script/test.sh` for app changes. Repeat or broaden checks only for new changes, failures, or unresolved concerns.
