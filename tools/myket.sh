#!/usr/bin/env bash
# Publish the Android APKs of release TAG of this repo to Myket through its developer API.
# Used by .github/workflows/myket.yml (run by hand for now); needs `gh`, `curl`, `jq`.
#
#   MYKET_ACCESS_TOKEN=… tools/myket.sh TAG
#
# - Takes the APKs (IranianCards-X.Y.Z-android-*.apk) from the GitHub release, not from a local build.
# - Sets Myket's release bundle to this version with the Persian notes from changelog.md, uploads every APK to it (one
#   request each; Myket tells the ABIs apart itself), then sends it for review.
# - AUTO_PUBLISH (default true): Myket publishes on its own once review passes. ROLLOUT (default 100): the staged
#   rollout percentage. DRY_RUN=1 prints what it would send and only makes a read-only call to check the secret.
# The token is the app's "verification token" (توکن صحت‌سنجی): Myket developer panel -> the app -> in-app products.
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

TAG="${1:?usage: tools/myket.sh TAG}"
[[ "$TAG" == v* ]] || TAG="v$TAG"
version="${TAG#v}"
PACKAGE="${MYKET_PACKAGE:-com.iraniancards.hokm}"
API="https://developer.myket.ir/api/partners/applications/$PACKAGE/release-bundle"
AUTO_PUBLISH="${AUTO_PUBLISH:-true}"
ROLLOUT="${ROLLOUT:-100}"
root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${MYKET_ACCESS_TOKEN:-}" && -z "${DRY_RUN:-}" ]]; then
  echo "::error::MYKET_ACCESS_TOKEN is not set"
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The "- " lines of version $version in changelog.md, without the "- ".
notes="$(awk -v v="$version" '
  /^## / { on = ($2 == v); next }
  on && /^- / { sub(/^- /, ""); print }' "$root/changelog.md")"
if [[ -z "$notes" ]]; then
  echo "::error::changelog.md has no entry for $version"
  exit 1
fi

gh release download "$TAG" -p "IranianCards-$version-android-*.apk" -D "$work/apks"
shopt -s nullglob
apks=("$work"/apks/*.apk)
if (( ${#apks[@]} == 0 )); then
  echo "::error::Release $TAG has no Android APK"
  exit 1
fi

bundle_body="$(jq -n --arg title "$version" --arg fa "$notes" --argjson rollout "$ROLLOUT" \
  '{title: $title, stagedRolloutPercent: $rollout, translationInfos: [{language: "fa", description: $fa}]}')"
commit_body="$(jq -n --argjson auto "$AUTO_PUBLISH" --arg msg "Release $TAG, https://github.com/pourmand1376/aryagames/releases/tag/$TAG" \
  '{isManualPublish: ($auto | not), message: $msg}')"

if [[ -n "${DRY_RUN:-}" ]]; then
  echo "Dry run for $TAG on $PACKAGE; would set the bundle to:"; echo "$bundle_body"
  echo "upload:"; for apk in "${apks[@]}"; do echo "  $(basename "$apk")"; done
  echo "and send it for review with:"; echo "$commit_body"
  if [[ -n "${MYKET_ACCESS_TOKEN:-}" ]]; then
    echo "Checking the token with a read-only call (the latest release bundle):"
    curl -sS --fail-with-body -H "X-Access-Token: $MYKET_ACCESS_TOKEN" "$API?offset=0&limit=1" \
      || { echo; echo "::error::Myket refused the token or the call"; exit 1; }
    echo
  fi
  exit 0
fi

# A Myket call; prints the reply and fails on an HTTP error, after printing the error body.
myket() {
  curl -sS --fail-with-body --retry 3 --max-time 1800 -H "X-Access-Token: $MYKET_ACCESS_TOKEN" "$@"
  echo
}

echo "Setting Myket's release bundle to $version"
myket -X PUT -H 'Content-Type: application/json' -d "$bundle_body" "$API" \
  || { echo "::error::Setting the release bundle failed"; exit 1; }

for apk in "${apks[@]}"; do
  echo "Uploading $(basename "$apk")"
  myket -X PUT -F "file=@$apk" "$API/upload" || { echo "::error::Upload of $(basename "$apk") failed"; exit 1; }
done

echo "Sending it for review (auto publish: $AUTO_PUBLISH, rollout: $ROLLOUT%)"
myket -X POST -H 'Content-Type: application/json' -d "$commit_body" "$API/commit" \
  || { echo "::error::Sending for review failed"; exit 1; }
echo "$TAG is with Myket for review."
