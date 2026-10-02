# Prepared release-note compatibility fixtures

The HTML and v2 RTF payloads were recorded from the original AppKit preparation at commit `3da9579` on macOS 27, before replacing its semantic preparation with SwiftUI `AttributedString`.

`ReleaseNotesMarkupTest.testPreparedRichTextMatchesOriginalHTMLAndLegacyCache` requires identical HTML for headings, combined inline styles, links, nested lists, code blocks, Unicode, HTML and plain text. It also requires existing RTF payloads and newly written payloads to render the same HTML. The original payload timestamps are fixture metadata; these tests decode the payload directly without renewing or checking its cache lifetime.

Regenerate only from a reviewed original implementation when intentionally changing the rendering contract.
