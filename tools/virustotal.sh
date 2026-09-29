#!/usr/bin/env bash
# Scan the game builds of a release in this repo on VirusTotal, wait for each verdict, and put one result line per file
# in the release notes, e.g. "- [Android arm64: 0/68 engines flagged](https://www.virustotal.com/gui/file/…)".
# Used by .github/workflows/on-release.yml after every release; needs `gh`, `curl`, `jq`.
#
#   VIRUSTOTAL_API_KEY=… tools/virustotal.sh TAG
#
# - A file VirusTotal already knows (same SHA-256) is not uploaded again; its last analysis is reused.
# - A new file is uploaded, then checked every POLL_SECONDS until VirusTotal finishes, for up to VT_WAIT_MINUTES.
#   If it takes longer, its line says "scan results" and links to the page, which fills in once VirusTotal is done.
# - The lines sit between <!-- virustotal:start --> and <!-- virustotal:end -->; a new run replaces that block.
# Without VIRUSTOTAL_API_KEY, or with no file on the release, it warns and exits 0 so a release never fails on it.
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true  # a failed API call inside $(…) stops the script

TAG="${1:?usage: tools/virustotal.sh TAG}"
API=https://www.virustotal.com/api/v3
GAP_SECONDS=15                        # the free API allows 4 requests a minute
POLL_SECONDS=30
VT_WAIT_MINUTES="${VT_WAIT_MINUTES:-20}"

if [[ -z "${VIRUSTOTAL_API_KEY:-}" ]]; then
  echo "::warning::VIRUSTOTAL_API_KEY is not set; skipping the VirusTotal scan of $TAG"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

gh release download "$TAG" -p '*.apk' -p '*.zip' -D "$work/files" 2>/dev/null || true
shopt -s nullglob
files=("$work"/files/*)
if (( ${#files[@]} == 0 )); then
  echo "Release $TAG has no APK or zip; nothing to scan."
  exit 0
fi

# A reader's name for release file $1, e.g. IranianCards-0.11.0-android-arm64.apk -> "Android arm64".
label() {
  local rest="${1#IranianCards-*-}"
  case "$1" in
    IranianCards-*-android-*) echo "Android ${rest#android-}" | sed 's/\.apk$//' ;;
    IranianCards-*-windows*)  echo "Windows" ;;
    IranianCards-*-linux-*)   echo "Linux ${rest#linux-}" | sed 's/\.zip$//' ;;
    IranianCards-*-macos-*)   echo "macOS ${rest#macos-}" | sed 's/\.zip$//' ;;
    *)                        echo "$1" ;;
  esac
}

# A VirusTotal API call, at least GAP_SECONDS after the previous one (kept in a file, since calls run in subshells).
vt() {
  local now last
  now="$(date +%s)"; last="$(cat "$work/last-call" 2>/dev/null || echo 0)"
  (( now - last < GAP_SECONDS )) && sleep $((GAP_SECONDS - (now - last)))
  date +%s >"$work/last-call"
  curl -sS --retry 3 -H "x-apikey: $VIRUSTOTAL_API_KEY" "$@"
}

# "flagged/engines" from a stats object on stdin, e.g. "0/67".
score() { jq -r '"\((.malicious // 0) + (.suspicious // 0))/\((.malicious // 0) + (.suspicious // 0) + (.undetected // 0) + (.harmless // 0))"'; }

# Prints the stats of VirusTotal's finished analysis of sha256 $1 and succeeds, or fails when there is none yet.
finished() {
  local code
  code="$(vt -o "$work/file.json" -w '%{http_code}' "$API/files/$1")" || return 1
  [[ "$code" == 200 ]] && jq -e '.data.attributes.last_analysis_date' "$work/file.json" >/dev/null || return 1
  jq '.data.attributes.last_analysis_stats' "$work/file.json"
}

# Stats of VirusTotal's analysis of file $1 (sha256 $2): the last one if it knows the file, otherwise upload it and wait.
# Prints nothing when there is no verdict in time.
analyze() {
  local file="$1" sha="$2" code upload deadline
  if finished "$sha"; then
    echo "  known to VirusTotal; reusing its last analysis" >&2
    return
  fi
  echo "  uploading" >&2
  # Never abort the whole scan over one file: 409 means VirusTotal is already analyzing it (e.g. two runs at once
  # uploading the same file); anything else is a warning, and the file still gets its link.
  if ! upload="$(vt --fail "$API/files/upload_url" | jq -r .data)"; then
    echo "::warning::VirusTotal gave no upload URL for $(basename "$file")" >&2
    return
  fi
  code="$(vt -o "$work/upload.json" -w '%{http_code}' -F "file=@$file" "$upload")" || true
  case "$code" in
    200) ;;
    409) echo "  VirusTotal is already analyzing it" >&2 ;;
    *)   echo "::warning::VirusTotal upload of $(basename "$file") failed (HTTP $code)" >&2; return ;;
  esac
  deadline=$(( $(date +%s) + VT_WAIT_MINUTES * 60 ))
  while (( $(date +%s) < deadline )); do
    sleep "$POLL_SECONDS"
    if finished "$sha"; then return; fi
    echo "  still analyzing…" >&2
  done
  echo "::warning::VirusTotal had no verdict for $(basename "$file") after $VT_WAIT_MINUTES minutes" >&2
}

lines=()
flagged=0
for file in "${files[@]}"; do
  name="$(basename "$file")"
  sha="$(sha256sum "$file" 2>/dev/null || shasum -a 256 "$file")"
  sha="${sha%% *}"
  echo "$name ($sha)"
  stats="$(analyze "$file" "$sha")"
  if [[ -n "$stats" ]]; then
    count="$(score <<<"$stats")"
    result="$count engines flagged"
    (( ${count%%/*} > 0 )) && flagged=1
  else
    result="scan results"
  fi
  echo "  $result"
  lines+=("- [$(label "$name"): $result](https://www.virustotal.com/gui/file/$sha)")
done

# The notes without an earlier VirusTotal block and trailing blank lines, then the new block.
gh release view "$TAG" --json body -q .body >"$work/body.md"
{
  awk '/<!-- virustotal:start -->/ {skip = 1} !skip {print} /<!-- virustotal:end -->/ {skip = 0}' "$work/body.md" \
    | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
  echo
  echo "<!-- virustotal:start -->"
  echo "### VirusTotal"
  printf '%s\n' "${lines[@]}"
  echo "<!-- virustotal:end -->"
} >"$work/notes.md"
gh release edit "$TAG" --notes-file "$work/notes.md" >/dev/null
echo "Updated the notes of $TAG."
if (( flagged )); then
  echo "::warning::Some engines flagged a file of $TAG; check the links in its release notes."
fi
