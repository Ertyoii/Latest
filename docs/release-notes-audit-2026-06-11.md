# Release Notes Audit - 2026-06-11

> Historical snapshot. Versions, coverage, paths, and source availability below describe the original audit, not the current installation. Run `./script/audit_release_notes.sh` for a new report; do not overwrite this historical evidence.


Generated from `./script/audit_release_notes.sh` against:

- `/Applications`
- `/Users/ertyoii/Applications`

Raw report: `build/release-notes-audit.txt`

## Summary

- Accepted release notes: 31
- Update source returned no release notes: 2
- Update check failed: 7

## Regression Notes

- Zed release notes were available, but Zed's release page now stores the description behind a React Server Components reference such as `$106`. Latest now resolves that reference before falling back to visible page text, so it shows the real 1.6.3 changelog instead of download-card text or an empty state.
- Cursor release notes were available, but its dated changelog sections needed a stricter end boundary. Latest now stops the selected section at the next dated release entry.
- BetterDisplay and Surge currently return no release-note text from their Sparkle update sources.
- Keynote, LogiPluginService, Numbers, Pages, SendToKindleUninstaller, Spotify, and USB File Manager did not produce update info in this audit run.

## App Coverage

| App | Installed version / build | Update kind | Status | Source / detail | Evidence excerpt |
| --- | --- | --- | --- | --- | --- |
| 1Password | 8.12.22 / 8.12.22 | none | accepted | homebrew | 1Password 8.12.22 is available from Homebrew. Password manager that keeps all passwords secure behind one password. |
| Amazon Kindle | 7.60 / 1.444412.10 | appStore | accepted | appStore | Several experience improvements and bug fixes. |
| AppCleaner | 3.6.8 / 4332 | sparkle | accepted | sparkle | AppCleaner 3.6.8 - 4 July, 2023. New app icon. Allow searching for related files of system apps. |
| BetterDisplay | 4.3.4 / 50021 | sparkle | unavailable | no release notes | Update source returned no release notes. |
| Bruno | 3.4.2 / 3.4.2 | none | accepted | homebrew | Bruno 3.4.2 is available from Homebrew. Open source IDE for exploring and testing APIs. |
| Chrome | 149.0.7827.103 / 7827.103 | none | accepted | homebrew | Google Chrome 149.0.7827.103 is available from Homebrew. Web browser. |
| Codex | 26.608.12217 / 3722 | none | accepted | homebrew | Codex 26.608.12217 is available from Homebrew. OpenAI's Codex desktop app for managing coding agents. |
| CodexBar | 0.32.5 / 80 | sparkle | accepted | sparkle | CodexBar 0.33.0. Added Terminal.app or iTerm settings, Japanese localization, and several fixes. |
| Cursor | 3.7.21 / 3.7.21 | none | accepted | homebrew | 3.7 Jun 5, 2026 changelog. Design Mode improvements, multi-select elements, and voice input. |
| Discord | 0.0.394 / 0.0.394 | none | accepted | homebrew | Discord 0.0.394 is available from Homebrew. Voice and text chat software. |
| Docker | 4.77.0 / 228796 | none | accepted | homebrew | Docker 4.77.0 is available from Homebrew. App to build and share containerised applications and microservices. |
| eqMac | 1.8.15 / 1.8.15 | sparkle | accepted | sparkle | v1.8.15 - AirPods loop fix. Fixed AirPods causing eqMac to go into a device swap loop and freezing. |
| ExpressVPN | 14.0.0 / 14.0.0 | none | accepted | homebrew | ExpressVPN 14.1.1.13156 is available from Homebrew. VPN client for secure and private internet access. |
| Final Cut Pro | 12.2 / 447037 | appStore | accepted | appStore | This update includes stability improvements and bug fixes. Also recently added intelligence features. |
| Garmin Express | 7.28.0.0 / 7280000 | none | accepted | homebrew | Garmin Express 7.28.0 is available from Homebrew. Update maps and software, sync with Garmin Connect and register your device. |
| Ghostty | 1.3.1 / 15212 | none | accepted | homebrew | Ghostty 1.3.1 is available from Homebrew. Terminal emulator that uses platform-native UI and GPU acceleration. |
| IINA | 1.4.3 / 167 | sparkle | accepted | sparkle | IINA 1.4.3. Fixes important security issues and regressions. |
| Keynote | 14.5 / 7045.0.17 | appStore | update-check-failed | updateInfoUnavailable | No update info was available during this audit run. |
| Latest Dev | 0.33 / 1391 | sparkle | accepted | sparkle | New features include custom app locations and clearer full-support versus limited-support labels. |
| logioptionsplus | 2.3.879545 / 2.3.879545 | none | accepted | homebrew | logioptionsplus 2.1.854976 is available from Homebrew. Software for Logitech devices. |
| LogiPluginService | 6.3.0.2406 / 6.3.0.2406 | none | update-check-failed | updateInfoUnavailable | No update info was available during this audit run. |
| Notion | 7.21.0 / 7.21.0 | none | accepted | homebrew | Notion 7.21.0 is available from Homebrew. App to write, plan, collaborate, and get organised. |
| Numbers | 14.5 / 7045.0.17 | appStore | update-check-failed | updateInfoUnavailable | No update info was available during this audit run. |
| Obsidian | 1.12.7 / 0.14.8 | none | accepted | homebrew | Obsidian 1.12.7 is available from Homebrew. Knowledge base using local Markdown files. |
| Pages | 14.5 / 7045.0.17 | appStore | update-check-failed | updateInfoUnavailable | No update info was available during this audit run. |
| PDF Expert | 3.11.2 / 1150 | sparkle | accepted | sparkle | Action required because the current developer signature certificate expires on Jul 29. |
| Rectangle | 0.96 / 102 | sparkle | accepted | sparkle | Adds display behavior options, shortcut cycling, menu icons, localization updates, and bug fixes. |
| Send to Kindle | 1.1 / 1.1.1.259 | none | accepted | homebrew | Send to Kindle 1.1.1.259 is available from Homebrew. Tool for sending personal documents to Kindles from Macs. |
| SendToKindleUninstaller | 1.1 / 1.1.1.259 | none | update-check-failed | updateInfoUnavailable | No update info was available during this audit run. |
| Spotify | 1.2.90.451 / 1.2.90.451 | none | update-check-failed | updateInfoUnavailable | No update info was available during this audit run. |
| Surge | 6.6.0 / 11270 | sparkle | unavailable | no release notes | Update source returned no release notes. |
| Telegram | 6.9.1 / 6.9.1 | none | accepted | homebrew | Telegram Desktop 6.9.0 is available from Homebrew. Desktop client for Telegram messenger. |
| The Unarchiver | 4.3.9 / 147 | appStore | accepted | appStore | Fixed minor bugs and known crashes. |
| Thunder | 5.80.6 / 66655 | none | accepted | homebrew | Thunder 5.80.6.66655 is available from Homebrew. VPN and WiFi proxy. |
| USB File Manager | 1.1.1.258 / 1 | none | update-check-failed | updateInfoUnavailable | No update info was available during this audit run. |
| WeChat | 4.1.9 / 268624 | appStore | accepted | appStore | Send voice messages. Fixed some known issues. |
| WhatsApp | 26.22.77 / 990963363 | appStore | accepted | appStore | Regular update to fix bugs, optimize performance, and improve the experience. |
| Xcode | 26.5 / 24943 | appStore | accepted | appStore | Xcode 26.5 includes Swift 6.3.2 and SDKs for iOS 26.5, iPadOS 26.5, tvOS 26.5, watchOS 26.5, visionOS 26.5, and macOS 26.5. |
| Zed | 1.5.4 / 20260606.040657 | none | accepted | homebrew | This week's release includes dedicated Git diff tabs, fast mode for Anthropic and OpenAI models, shareable agent skill links, split diff mode, Git panel line counts, and file finder improvements. |
| zoom.us | 7.0.5 (81138) / 7.0.5.81138 | none | accepted | homebrew | zoom.us 7.0.5.81138 is available from Homebrew. Video communication and virtual meeting platform. |
