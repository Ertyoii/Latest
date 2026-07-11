#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
	echo "error: jq is required" >&2
	exit 1
fi

CATALOG_PATH="${1:-}"
if [[ -z "$CATALOG_PATH" || ! -f "$CATALOG_PATH" ]]; then
	echo "usage: $0 /path/to/homebrew-cask.json" >&2
	echo "The input must be the public Homebrew cask API response; this script never scans installed apps." >&2
	exit 2
fi

CATALOG_TOKENS='[
  "1password",
  "betterdisplay",
  "bruno",
  "docker-desktop",
  "firefox",
  "ghostty",
  "google-chrome",
  "obsidian",
  "telegram-desktop",
  "visual-studio-code",
  "zoom",
  "cursor",
  "zed",
  "zed@preview",
  "aqua-app",
  "clion",
  "datagrip",
  "dataspell",
  "goland",
  "intellij-idea",
  "intellij-idea-ce",
  "mps",
  "phpstorm",
  "pycharm",
  "pycharm-ce",
  "pycharm-edu",
  "rider",
  "rubymine",
  "rustrover",
  "webstorm",
  "writerside",
  "airfoil",
  "audio-hijack",
  "farrago",
  "fission",
  "loopback",
  "piezo",
  "soundsource"
]'

jq --argjson catalogTokens "$CATALOG_TOKENS" '
  [ .[] | select(any(.artifacts[]?; type == "object" and has("app"))) ] as $apps |

  def direct_tagged_github_release:
    (.url // "") | test("^https://github\\.com/[^/]+/[^/]+/releases/download/[^/]+/");

  def latest_github_download:
    (.url // "") | test("^https://github\\.com/[^/]+/[^/]+/releases/latest/download/");

  def exact_github_homepage:
    (.homepage // "") | test("^https://github\\.com/[^/]+/[^/]+(?:\\.git)?/?$");

  def catalog_source:
    (.token as $token | $catalogTokens | index($token)) != null;

  def high_confidence_source:
    direct_tagged_github_release or latest_github_download or catalog_source;

  def routed_candidate_source:
    high_confidence_source or exact_github_homepage;

  def homepage_host:
    (try ((.homepage // "") | capture("^https?://(?<host>[^/]+)").host) catch "unknown");

  ($apps | map(select(high_confidence_source))) as $covered |
  ($apps | map(select(routed_candidate_source))) as $candidateCovered |
  {
    app_casks: ($apps | length),
    direct_tagged_github_release: ($apps | map(select(direct_tagged_github_release)) | length),
    latest_github_download: ($apps | map(select(latest_github_download)) | length),
    exact_github_homepage: ($apps | map(select(exact_github_homepage)) | length),
    catalog_source: ($apps | map(select(catalog_source)) | length),
    catalog_unique_high_confidence: (
      $apps
      | map(select(catalog_source and ((direct_tagged_github_release or latest_github_download) | not)))
      | length
    ),
    high_confidence_union: ($covered | length),
    high_confidence_coverage_percent: (
      if ($apps | length) == 0 then 0
      else ((($covered | length) * 10000 / ($apps | length)) | round) / 100
      end
    ),
    routed_candidate_union: ($candidateCovered | length),
    routed_candidate_coverage_percent: (
      if ($apps | length) == 0 then 0
      else ((($candidateCovered | length) * 10000 / ($apps | length)) | round) / 100
      end
    ),
    github_homepage_unique_candidates: (
      $apps
      | map(select(exact_github_homepage and (high_confidence_source | not)))
      | length
    ),
    largest_uncovered_homepage_hosts: (
      $apps
      | map(select(routed_candidate_source | not) | homepage_host)
      | group_by(.)
      | map({ host: .[0], app_casks: length })
      | sort_by(-.app_casks, .host)
      | .[:25]
    )
  }
' "$CATALOG_PATH"
