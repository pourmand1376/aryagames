#!/usr/bin/env bash
# Publish the Android APKs of release TAG of this repo to Cafe Bazaar through its Pishkhan API.
# Used by .github/workflows/bazaar.yml (run by hand for now); needs `gh`, `curl`, `jq`.
#
#   BAZAAR_API_SECRET=… tools/bazaar.sh TAG
#
# - Takes the APKs (IranianCards-X.Y.Z-android-*.apk) from the GitHub release, not from a local build.
# - Reuses Bazaar's open draft release if there is one, otherwise creates one; uploads every APK to it; then commits
#   it with the Persian notes of that version from changelog.md.
# - AUTO_PUBLISH (default true): Bazaar publishes on its own once review passes. ROLLOUT (default 100): the staged
#   rollout percentage. DRY_RUN=1 prints what it would send and only makes a read-only call to check the secret.
# The API secret is per app: pishkhan.cafebazaar.ir -> the app -> API (Pishkhan API) -> the secret.
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

TAG="${1:?usage: tools/bazaar.sh TAG}"
[[ "$TAG" == v* ]] || TAG="v$TAG"
version="${TAG#v}"
API=https://api.pishkhan.cafebazaar.ir/v1
AUTO_PUBLISH="${AUTO_PUBLISH:-true}"
ROLLOUT="${ROLLOUT:-100}"
root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${BAZAAR_API_SECRET:-}" && -z "${DRY_RUN:-}" ]]; then
  echo "::error::BAZAAR_API_SECRET is not set"
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The "- " lines of version $version in changelog.md, without the "- "; a generic note when it has none.
notes="$(awk -v v="$version" '
  /^## / { on = ($2 == v); next }
  on && /^- / { sub(/^- /, ""); print }' "$root/changelog.md")"
if [[ -z "$notes" ]]; then
  notes="بهبودها و رفع اشکال‌ها."
  echo "::warning::changelog.md has no entry for $version; sending the generic note: $notes"
fi

gh release download "$TAG" -p "IranianCards-$version-android-*.apk" -D "$work/apks"
shopt -s nullglob
apks=("$work"/apks/*.apk)
if (( ${#apks[@]} == 0 )); then
  echo "::error::Release $TAG has no Android APK"
  exit 1
fi

# Bazaar's name for the ABI of APK $1, e.g. IranianCards-0.11.0-android-arm64.apk -> arm64-v8a.
abi() {
  case "$1" in
    *-android-arm64.apk) echo arm64-v8a ;;
    *-android-armv7.apk) echo armeabi-v7a ;;
    *)                   echo all ;;
  esac
}

# A Pishkhan call; prints the JSON reply and fails unless its "type" is "success" (or $expect, when given).
bazaar() {
  local expect="${expect:-success}" reply
  reply="$(curl -sS --retry 3 --max-time 1800 -H "CAFEBAZAAR-PISHKHAN-API-SECRET: $BAZAAR_API_SECRET" \
    -H 'Accept: application/json' "$@")"
  echo "$reply"
  jq -e --arg t "$expect" '.type == $t' <<<"$reply" >/dev/null
}

commit_body="$(jq -n --arg fa "$notes" --arg note "Release $TAG, https://github.com/pourmand1376/aryagames/releases/tag/$TAG" \
  --argjson auto "$AUTO_PUBLISH" --argjson rollout "$ROLLOUT" \
  '{changelog_fa: $fa, changelog_en: "", developer_note: $note, auto_publish: $auto, staged_rollout_percentage: $rollout}')"

if [[ -n "${DRY_RUN:-}" ]]; then
  echo "Dry run for $TAG; would upload:"
  for apk in "${apks[@]}"; do echo "  $(basename "$apk") as $(abi "$(basename "$apk")")"; done
  echo "and commit with:"; echo "$commit_body"
  if [[ -n "${BAZAAR_API_SECRET:-}" ]]; then
    echo "Checking the secret with a read-only call (is there an open draft release?):"
    reply="$(curl -sS --retry 3 -H "CAFEBAZAAR-PISHKHAN-API-SECRET: $BAZAAR_API_SECRET" -H 'Accept: application/json' \
      "$API/apps/releases/last-uncommitted/")"
    echo "$reply"
    jq -e '.type == "success" or .type == "not-exists"' <<<"$reply" >/dev/null \
      || { echo "::error::Bazaar refused the secret or the call"; exit 1; }
  fi
  exit 0
fi

if expect=not-exists bazaar "$API/apps/releases/last-uncommitted/" >/dev/null; then
  echo "Creating a release on Bazaar"
  bazaar -X POST -H 'Content-Type: application/json' -d '{}' "$API/apps/releases/"
else
  echo "Reusing Bazaar's open draft release"
fi

for apk in "${apks[@]}"; do
  echo "Uploading $(basename "$apk")"
  bazaar -X POST -F "apk=@$apk" -F "architecture=$(abi "$(basename "$apk")")" "$API/apps/releases/upload/" \
    | jq -c '.package // .' || { echo "::error::Upload of $(basename "$apk") failed"; exit 1; }
done

echo "Committing the release (auto_publish=$AUTO_PUBLISH, rollout=$ROLLOUT%)"
bazaar -X POST -H 'Content-Type: application/json' -d "$commit_body" "$API/apps/releases/commit/" \
  || { echo "::error::Commit failed"; exit 1; }
echo "$TAG is with Bazaar for review."
