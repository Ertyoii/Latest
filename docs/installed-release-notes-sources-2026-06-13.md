# Installed Release Note Source Inventory

> Historical snapshot. Versions, coverage, paths, and source availability below describe the original audit, not the current installation. Run `./script/audit_release_notes.sh` for a new report; do not overwrite this historical evidence.


Generated: 2026-06-14

Scope: apps currently discovered from `/Applications` plus helper bundles surfaced by Latest's installed-app audit. "Yes" means there is a release-note source that can show app-version-specific notes. "No" means no reliable public app-version-specific release-note source was confirmed; Latest should show the normal updater metadata fallback instead of scraping unrelated product news.

## Main Apps

| App | Installed version | Release notes? | Source | Source URL | Latest parser/action |
| --- | --- | --- | --- | --- | --- |
| 1Password | 8.12.22 | Yes | Homebrew + vendor changelog | `https://releases.1password.com/mac/stable/` | Catalog changelog mapping extracts the matching 8.12.22 article. |
| Amazon Kindle | 7.60 | Yes | Apple Store | Apple lookup API releaseNotes | App Store releaseNotes HTML path. |
| AppCleaner | 3.6.8 | Yes | Sparkle | `https://freemacsoft.net/appcleaner/updates.xml` -> release notes page | Sparkle releaseNotesURL, trimmed to current version. |
| BetterDisplay | 4.3.4 | Yes | Sparkle + GitHub | `https://waydabber.github.io/BetterDisplay/changelog.html?tag=v4.3.4`, `https://github.com/waydabber/BetterDisplay/releases/tag/v4.3.4` | BetterDisplay Sparkle URL is normalized to the GitHub release API with a source-derived fallback for 4.3.4. |
| Bruno | 3.4.2 | Yes | Homebrew + GitHub | `https://github.com/usebruno/bruno/releases/tag/v3.4.2` | Catalog GitHub release mapping. |
| Chrome | 149.0.7827.115 | Yes | Homebrew + Chrome Releases blog | `https://chromereleases.googleblog.com/` | Chrome-specific parser selects the Desktop stable post and skips Android cross-links. |
| Codex | 26.609.41114 | No | Homebrew fallback | `https://openai.com/codex` | No app-version-specific public release-note page found; keep Homebrew metadata fallback. |
| CodexBar | 0.33.0 | Yes | Sparkle | `https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml` | Sparkle inline release notes for the available 0.34.0 update. |
| Cursor | 3.7.27 | Yes | Homebrew + vendor changelog | `https://cursor.com/changelog` | Cursor changelog mapping extracts the current 3.7 section instead of the newest unrelated post. |
| Discord | 0.0.394 | No | Homebrew fallback | `https://discord.com/` | No reliable app-version-specific public release-note page found. |
| Docker | 4.77.0 | Yes | Homebrew + vendor docs | `https://docs.docker.com/desktop/release-notes.md` | Catalog markdown changelog mapping extracts 4.77.0. |
| eqMac | 1.8.15 | Yes | Sparkle | `https://update.eqmac.app/update.xml` | Sparkle inline changelog. |
| ExpressVPN | 14.0.0 | No | Homebrew fallback | `https://www.expressvpn.works/` | No reliable app-version-specific public release-note page found. |
| Final Cut Pro | 12.2 | Yes | Apple Store | Apple lookup API releaseNotes | App Store releaseNotes HTML path. |
| Garmin Express | 7.29.0.0 | No | Homebrew fallback | `https://www.garmin.com/en-US/software/express` | No reliable app-version-specific public release-note page found. |
| Ghostty | 1.3.1 | Yes | Homebrew + vendor source markdown | `https://raw.githubusercontent.com/ghostty-org/website/main/docs/install/release-notes/1-3-1.mdx` | Versioned raw MDX mapping with Markdown cleanup. |
| IINA | 1.4.3 | Yes | Sparkle | `https://www.iina.io/appcast.xml`, `https://www.iina.io/release-note/1.4.3.html` | Sparkle releaseNotesURL, duplicate title cleanup. |
| Latest Dev | 0.38 | Yes | Sparkle | `https://max.codes/latest/update.xml` | Sparkle inline release notes. |
| logioptionsplus | 2.3.879545 | No | Homebrew fallback | `https://www.logitech.com/en-us/software/logi-options-plus.html` | No reliable app-version-specific public release-note page found; audit also shows Homebrew metadata can lag installed version. |
| Notion | 7.21.0 | No | Homebrew fallback | `https://www.notion.com/` | Do not use Notion product/news release pages; they are not desktop app-version release notes and previously produced wrong notes. |
| Obsidian | 1.12.7 | Yes | Homebrew + vendor changelog | `https://obsidian.md/changelog/` | Catalog mapping prefers the Desktop changelog entry and rejects mobile/product-page noise. |
| PDF Expert | 3.11.2 | Yes | Sparkle | `https://downloads.pdfexpert.com/release/appcast.xml` | Sparkle releaseNotesURL. |
| Rectangle | 0.96 | Yes | Sparkle | `https://rectangleapp.com/downloads/updates.xml` | Sparkle inline release notes. |
| Safari | 26.5 | No | Apple system app | macOS/Safari system update notes only | No stand-alone app-version release-note feed used by Latest. |
| Send to Kindle | 1.1.1.259 | No | Homebrew fallback | `https://www.amazon.com/gp/sendtokindle/mac` | Generic Homebrew metadata only; no reliable app-version-specific public release-note page found. |
| Spotify | 1.2.92.147 | No | Update unavailable | `https://www.spotify.com/` | Latest audit reports updateInfoUnavailable; no reliable app-version-specific public release-note page found. |
| Surge | 6.6.0 | No | Sparkle source, no notes returned | `https://nssurge.com/mac/latest/appcast-signed.xml` | Sparkle update source returned no release notes for the audited item. |
| Telegram | 6.9.1 -> 6.9.3 | Yes | Homebrew + GitHub | `https://github.com/telegramdesktop/tdesktop/releases/tag/v6.9.3` | Catalog GitHub release mapping for the available update. |
| The Unarchiver | 4.3.9 | Yes | Apple Store | Apple lookup API releaseNotes | App Store releaseNotes HTML path. |
| Thunder | 5.80.6 | No | Homebrew fallback | `https://www.xunlei.com/` | Candidate whats-new page is not reliable for app-version release notes; keep fallback. |
| WeChat | 4.1.9 | Yes | Apple Store | Apple lookup API releaseNotes | App Store releaseNotes HTML path. |
| WhatsApp | 26.22.77 | Yes | Apple Store | Apple lookup API releaseNotes | App Store releaseNotes HTML path. |
| Xcode | 26.5 | Yes | Apple Store | Apple lookup API releaseNotes | App Store releaseNotes HTML path. |
| Zed | 1.6.3 | Yes | Homebrew + vendor release page | `https://zed.dev/releases/stable/1.6.3` | Zed-specific parser starts at the bare version/date release body and strips navigation/loading chrome. |
| zoom.us | 7.0.5 (81138) | Yes | Homebrew + vendor release notes | `https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222` | Zoom-specific parser selects the dated release section and drops the platform version matrix. |

## Helper Bundles Surfaced By Audit

| App | Installed version | Release notes? | Source | Notes |
| --- | --- | --- | --- | --- |
| LogiPluginService | 6.3.0.2406 | No | Helper bundle | Latest audit reports updateInfoUnavailable. |
| SendToKindleUninstaller | 1.1 | No | Helper/uninstaller bundle | Latest audit reports updateInfoUnavailable. |
| USB File Manager | 1.1.1.258 | No | Helper bundle | Latest audit reports updateInfoUnavailable. |

## Parser Verification Notes

- The last completed installed-app audit passed on 2026-06-14 with 32 accepted apps, 1 unavailable app, 4 update-check-failed helper/app rows, and 0 malformed release-note renderings.
- The audit accepted real or source-specific release notes for 1Password, Amazon Kindle, AppCleaner, BetterDisplay, Bruno, Chrome, CodexBar, Cursor, Docker, eqMac, Final Cut Pro, Ghostty, IINA, Latest Dev, Obsidian, PDF Expert, Rectangle, Telegram, The Unarchiver, WeChat, WhatsApp, Xcode, Zed, and zoom.us.
- The audit intentionally allows generic metadata for apps marked "No" above, because no reliable app-version-specific release-note source was confirmed.
- Notion is explicitly mapped to no source so Latest does not show the wrong Notion product-release page.
- Zed and Zoom have source-specific parser guardrails because their pages include enough navigation/table chrome to pass a naive non-empty text check.
- Zoom is verified to show the May 18, 2026 release body with "Show or hide icon labels" and to omit the platform version matrix.
- Surge remains intentionally unavailable because the Sparkle source returned no notes for the audited item; LogiPluginService, SendToKindleUninstaller, Spotify, and USB File Manager remain update-check-failed rows in the installed-app audit.
