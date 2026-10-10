# Maintaining this repo

The public home of **Hokm Shelem Ghafoon**. It hosts the website (GitHub Pages) and every release of the app (GitHub Releases). The app's code lives in a private repo. It follows the same model as Obsidian's `obsidian-releases`.

## How a release gets here
1. The app repo releases as usual (`just release-all patch`, etc.).
2. Its `tools/publish_public.sh` copies the APKs and zips (not the play models) to a release with the same tag here. The release notes link to `changelog.html#vX.Y.Z`.
3. `.github/workflows/on-release.yml` runs when that release is published, or when the app repo adds files to it (a `rescan` repository dispatch):
   - `tools/virustotal.sh` scans every file on VirusTotal, **waits for the verdicts**, and writes them into the release notes;
   - `tools/update_releases_json.sh` points `releases.json` at the release (newest stable version only) and commits it;
   - the site is rebuilt and deployed, so the download buttons show the new version with its scan results.
4. To redo a scan: Actions → On release → Run workflow, or `just virustotal vX.Y.Z` from the app repo.

5. A newly published release goes to Cafe Bazaar and Myket on its own once its VirusTotal scan is done (on-release.yml starts both workflows; a rescan or a run by hand does not). To send one by hand: Actions → Cafe Bazaar → Run workflow with the tag, or `gh workflow run bazaar.yml -f tag=vX.Y.Z`. `tools/bazaar.sh` takes the release's Android APKs, uploads them through the Pishkhan API, and commits the release with that version's `changelog.md` notes; Bazaar publishes it once its review passes. Tick "dry run" to check the secret and see what it would send, without changing anything. "abis" (e.g. `arm64`) sends only those APKs; a rerun skips APKs already in Bazaar's open draft.
6. Myket works the same way: Actions → Myket → Run workflow, or `gh workflow run myket.yml -f tag=vX.Y.Z` (`tools/myket.sh`).

Secrets here: `VIRUSTOTAL_API_KEY` (without it the scan is skipped with a warning), `BAZAAR_API_SECRET` (Pishkhan → the app → API), `MYKET_ACCESS_TOKEN` (Myket developer panel → the app → in-app products → verification token).

## What you edit by hand
- `changelog.md`: public release notes in Persian, newest first (`## X.Y.Z | YYYY-MM-DD`, then `- ` lines). Add the entry when you release; the release notes link to its anchor. Without one, the Myket and Bazaar scripts send a generic «بهبودها و رفع اشکال‌ها.» and warn.
- `site/`: the pages (`index.html`, `changelog.html`) and `assets/`. `{{placeholders}}` are filled by the build.

## In-app update check
The build also writes `https://aryagames.ir/latest_version.json` (and the same text at `/latest_version`, for a browser), from `releases.json`: `{"version": "0.13.0", "date": "2026-10-01", "url": "https://aryagames.ir"}`. The app asks for it at most once a day; when the player's build is older and that release is at least a week old, it tells them a new version is out and offers a button to `url`. It never downloads anything itself (Bazaar and Myket will have their own update path). Keep the keys stable.

## Build and preview
```sh
python3 tools/build_site.py
python3 -m http.server -d _site 8000   # http://localhost:8000
```

## Custom domain
The site is served at https://aryagames.ir: `site/CNAME` holds the domain, and it is set in Settings → Pages. The DNS is on Cloudflare: A records to GitHub's Pages IPs and `www` as a CNAME to `pourmand1376.github.io`, all DNS only (grey cloud).
