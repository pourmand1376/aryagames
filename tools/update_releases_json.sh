#!/usr/bin/env bash
# Rewrite releases.json from release TAG of this repo: one entry per build, keyed like "android-arm64"
# (IranianCards-0.11.0-android-arm64.apk), with its size, download URL and VirusTotal link from the release notes.
# Used by .github/workflows/on-release.yml after the scan; needs `gh` and `jq`.
#
#   tools/update_releases_json.sh TAG
#
# The file follows the newest stable version only, so a rescan of an old release or a pre-release never rolls the site
# back. It prints whether releases.json changed.
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

TAG="${1:?usage: tools/update_releases_json.sh TAG}"
version="${TAG#v}"
file="$(cd "$(dirname "$0")/.." && pwd)/releases.json"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

gh release view "$TAG" --json assets,publishedAt,body,isDraft,isPrerelease >"$work/release.json"
if jq -e '.isDraft or .isPrerelease' "$work/release.json" >/dev/null; then
  echo "$TAG is a draft or pre-release; releases.json stays as it is."
  exit 0
fi

current="$(jq -r '.version // empty' "$file" 2>/dev/null || true)"
newest="$(printf '%s\n%s\n' "${current:-0.0.0}" "$version" | sort -V | tail -n1)"
if [[ -n "$current" && "$newest" != "$version" ]]; then
  echo "releases.json stays on $current (newer than $version)."
  exit 0
fi

jq --arg version "$version" --arg tag "$TAG" '
  def buildkey: ltrimstr("IranianCards-\($version)-") | sub("\\.(apk|zip)$"; "");
  def vtname: if startswith("android-") then "Android " + ltrimstr("android-")
              elif . == "windows" then "Windows"
              elif startswith("linux-") then "Linux " + ltrimstr("linux-")
              elif startswith("macos-") then "macOS " + ltrimstr("macos-")
              else . end;
  .body as $body
  | def vtlink($l): ($body | split("\n") | map(select(startswith("- [\($l):")))[0] // "")
                    | (capture("\\((?<u>https://www\\.virustotal\\.com/[^)]+)\\)").u? // null);
  { version: $version, tag: $tag, date: (.publishedAt[:10]),
    files: (.assets
            | map(select(.name | test("\\.(apk|zip)$")))
            | map((.name | buildkey) as $k
                  | { key: $k,
                      value: ({ name: .name, url: .url, size: .size, virustotal: vtlink($k | vtname) }
                              | with_entries(select(.value != null))) })
            | from_entries) }' "$work/release.json" >"$work/releases.json"

if cmp -s "$work/releases.json" "$file"; then
  echo "releases.json is already up to date for $TAG."
else
  cp "$work/releases.json" "$file"
  echo "releases.json now points at $TAG."
fi
