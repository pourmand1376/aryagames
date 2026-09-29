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

Secrets here: `VIRUSTOTAL_API_KEY` (without it the scan is skipped with a warning).

## What you edit by hand
- `changelog.md`: public release notes in Persian, newest first (`## X.Y.Z | YYYY-MM-DD`, then `- ` lines). Add the entry when you release; the release notes link to its anchor.
- `site/`: the pages (`index.html`, `changelog.html`) and `assets/`. `{{placeholders}}` are filled by the build.

## Build and preview
```sh
python3 tools/build_site.py
python3 -m http.server -d _site 8000   # http://localhost:8000
```

## Custom domain
The site is served at https://aryagames.ir: `site/CNAME` holds the domain, and it is set in Settings → Pages. The DNS is on Cloudflare: A records to GitHub's Pages IPs and `www` as a CNAME to `pourmand1376.github.io`, all DNS only (grey cloud).
