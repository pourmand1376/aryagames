# بازی حکم شلم قفون: website and downloads

The public home of **Hokm Shelem Ghafoon**. It hosts the website (GitHub Pages) and every release of the app (GitHub Releases). The app's code lives in a private repo. It follows the same model as Obsidian's `obsidian-releases`.

## How a release gets here
1. The app repo releases as usual (`just release-all patch`, etc.).
2. After its VirusTotal scan, its `publish-public.yml` runs `tools/publish_public.sh`, which:
   - creates the same release here with the APKs and zips (no play models),
   - writes release notes that link to `changelog.html#vX.Y.Z` plus the VirusTotal results,
   - rewrites `releases.json` here, which triggers the Pages deploy.
3. The download buttons now point at the new version, with the version in each URL (like obsidian.md/download).

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
