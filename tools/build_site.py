#!/usr/bin/env python3
"""Build the website into _site/ from site/, releases.json and changelog.md (standard library only).

    python3 tools/build_site.py            # writes _site/
    python3 -m http.server -d _site 8000   # preview at http://localhost:8000

Like obsidian.md/download, every download link names its exact version
(…/releases/download/v0.11.0/IranianCards-0.11.0-windows.zip), taken from releases.json, which the app repo's
tools/publish_public.sh rewrites on each release. The page never asks GitHub's API for "latest" at load time.
"""
from __future__ import annotations

import html
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
OUT = ROOT / "_site"
REPO_URL = "https://github.com/pourmand1376/aryagames"

FA_DIGITS = str.maketrans("0123456789.", "۰۱۲۳۴۵۶۷۸۹٫")
JALALI_MONTHS = ["فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور",
                 "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند"]

# Download cards in page order: (platform id, title, suit mark, [(file key, button text, note)]).
# The first file present in a group is its main button; the rest are smaller links under it.
PLATFORMS = [
    ("android", "اندروید", "♥", [
        ("android-arm64", "دانلود APK", "برای بیشتر گوشی‌ها (arm64)"),
        ("android-armv7", "نسخهٔ گوشی‌های قدیمی‌تر", "armv7"),
    ]),
    ("windows", "ویندوز", "♠", [
        ("windows", "دانلود برای ویندوز", "۶۴ بیتی"),
    ]),
    ("macos", "مک", "♦", [
        ("macos-arm64", "دانلود برای مک", "Apple Silicon (M1 و بعد از آن)"),
        ("macos-x86_64", "نسخهٔ مک‌های اینتل", "Intel"),
    ]),
    ("linux", "لینوکس", "♣", [
        ("linux-x86_64", "دانلود برای لینوکس", "x86_64"),
    ]),
    ("ios", "آیفون", "♥", []),
]


def fa(text: object) -> str:
    """Persian digits (and ٫ for the dot), e.g. 0.11.0 -> ۰٫۱۱٫۰."""
    return str(text).translate(FA_DIGITS)


def jalali(iso_date: str) -> str:
    """2026-09-29 -> ۷ مهر ۱۴۰۵ (Gregorian to Jalali, the usual arithmetic conversion)."""
    gy, gm, gd = (int(p) for p in iso_date.split("-"))
    days_before_month = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    gy2 = gy + 1 if gm > 2 else gy
    days = (355666 + 365 * gy + (gy2 + 3) // 4 - (gy2 + 99) // 100 + (gy2 + 399) // 400
            + gd + days_before_month[gm - 1])
    jy = -1595 + 33 * (days // 12053)
    days %= 12053
    jy += 4 * (days // 1461)
    days %= 1461
    if days > 365:
        jy += (days - 1) // 365
        days = (days - 1) % 365
    if days < 186:
        jm, jd = 1 + days // 31, 1 + days % 31
    else:
        jm, jd = 7 + (days - 186) // 30, 1 + (days - 186) % 30
    return f"{fa(jd)} {JALALI_MONTHS[jm - 1]} {fa(jy)}"


def megabytes(size: int) -> str:
    return f"{fa(round(size / 1024 / 1024))} مگابایت"


def parse_changelog(text: str) -> list[dict]:
    """"## X.Y.Z | YYYY-MM-DD" headings with "- " items under them, newest first."""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    entries: list[dict] = []
    for line in text.splitlines():
        line = line.strip()
        if m := re.match(r"^##\s+([\w.\-]+)\s*\|\s*(\d{4}-\d{2}-\d{2})$", line):
            entries.append({"version": m[1], "date": m[2], "items": []})
        elif line.startswith("- ") and entries:
            entries[-1]["items"].append(line[2:].strip())
    return entries


def render_items(items: list[str]) -> str:
    return "".join(f"<li>{html.escape(i)}</li>" for i in items)


def render_scan(f: dict) -> str:
    """VirusTotal badge for one file: its result when known, else a link to the page while it is analyzed."""
    url, scan = f.get("virustotal"), f.get("scan")
    if not url:
        return ""
    href = f'href="{html.escape(url)}" rel="noopener"'
    if not scan:
        return f'<a class="vt pending" {href}>ویروس‌توتال: در حال بررسی</a>'
    if scan["flagged"] == 0:
        return (f'<a class="vt ok" {href}>ویروس‌توتال: سالم '
                f'<bdi>({fa(scan["flagged"])} از {fa(scan["engines"])})</bdi></a>')
    return (f'<a class="vt warn" {href}>ویروس‌توتال: {fa(scan["flagged"])} هشدار '
            f'از {fa(scan["engines"])} آنتی‌ویروس</a>')


def render_scan_summary(release: dict) -> str:
    """One line over the download cards for the whole release."""
    files = list(release.get("files", {}).values())
    scans = [f.get("scan") for f in files]
    if not files or not all(scans):
        return ""
    if all(s["flagged"] == 0 for s in scans):
        return (f'<p class="vt-summary ok">همهٔ فایل‌های نسخهٔ {fa(release["version"])} در ویروس‌توتال '
                f"بررسی شده‌اند و هیچ آنتی‌ویروسی هشدار نداده است.</p>")
    return (f'<p class="vt-summary warn">بعضی آنتی‌ویروس‌ها برای فایل‌های این نسخه هشدار داده‌اند؛ '
            f"جزئیات کنار هر فایل آمده است.</p>")


def render_downloads(release: dict) -> str:
    files = release.get("files", {})
    cards = []
    for pid, title, suit, options in PLATFORMS:
        present = [(key, label, note) for key, label, note in options if key in files]
        red = " red" if suit in "♥♦" else ""
        head = (f'<div class="dl-head"><span class="suit{red}" aria-hidden="true">{suit}</span>'
                f"<h3>{title}</h3></div>")
        if not present:
            cards.append(f'<article class="dl-card soon" data-platform="{pid}">{head}'
                         f'<p class="dl-note">به‌زودی</p></article>')
            continue
        key, label, note = present[0]
        f = files[key]
        body = [f'<a class="btn primary" href="{html.escape(f["url"])}" download>{label}</a>',
                f'<p class="dl-note"><bdi>{note}</bdi> · <bdi>{megabytes(f["size"])}</bdi></p>',
                render_scan(f)]
        for key, label, note in present[1:]:
            f = files[key]
            body.append(f'<div class="dl-alt"><p><a href="{html.escape(f["url"])}" download>{label}</a>'
                        f' <span><bdi>{note}</bdi> · <bdi>{megabytes(f["size"])}</bdi></span></p>'
                        f"{render_scan(f)}</div>")
        cards.append(f'<article class="dl-card" data-platform="{pid}">{head}{"".join(body)}</article>')
    return "\n".join(cards)


def render_changelog(entries: list[dict]) -> str:
    return "\n".join(
        f'<section class="release" id="v{e["version"]}">'
        f'<h2><a href="#v{e["version"]}">نسخهٔ {fa(e["version"])}</a></h2>'
        f'<time datetime="{e["date"]}">{jalali(e["date"])}</time>'
        f'<ul>{render_items(e["items"])}</ul></section>'
        for e in entries)


def fill(template: str, values: dict[str, str]) -> str:
    return re.sub(r"\{\{(\w+)\}\}", lambda m: values[m[1]], template)


def main() -> None:
    release = json.loads((ROOT / "releases.json").read_text(encoding="utf-8"))
    entries = parse_changelog((ROOT / "changelog.md").read_text(encoding="utf-8"))
    latest = next((e for e in entries if e["version"] == release["version"]), None)

    values = {
        "version": release["version"],
        "version_fa": fa(release["version"]),
        "date_fa": jalali(release["date"]),
        "downloads": render_downloads(release),
        "scan_summary": render_scan_summary(release),
        "latest_notes": render_items(latest["items"]) if latest else "",
        "changelog": render_changelog(entries),
        "repo_url": REPO_URL,
        "releases_url": f"{REPO_URL}/releases",
    }

    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(SITE, OUT, ignore=shutil.ignore_patterns("*.html", ".DS_Store"))
    for page in SITE.glob("*.html"):
        (OUT / page.name).write_text(fill(page.read_text(encoding="utf-8"), values), encoding="utf-8")
    shutil.copy(ROOT / "releases.json", OUT / "releases.json")  # for a future in-app update check
    (OUT / ".nojekyll").touch()
    print(f"Built {OUT.relative_to(ROOT)}/ for v{release['version']} "
          f"({len(release.get('files', {}))} files, {len(entries)} changelog entries)")


if __name__ == "__main__":
    main()
