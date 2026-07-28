#!/usr/bin/env python3
"""Export Helmhost product brand PNGs, ICO, and favicons from SVGs.

Org (BackBenchDevs) brand kit lives outside this repo:
  /Users/am042433/Documents/DEV/bbdevs/brand/

Requires: rsvg-convert (librsvg), Pillow.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "apps/client/assets/brand"
SOURCE = BRAND / "source"
HH_MARK = SOURCE / "helmhost-icon-mark.svg"
HH_FULL = SOURCE / "helmhost-icon.svg"
HH_LOCK = SOURCE / "helmhost-lockup.svg"

RSVG = shutil.which("rsvg-convert")
if not RSVG:
    for candidate in (
        "/Users/am042433/radioconda/bin/rsvg-convert",
        "/opt/homebrew/bin/rsvg-convert",
        "/usr/local/bin/rsvg-convert",
    ):
        if Path(candidate).is_file():
            RSVG = candidate
            break

if not RSVG:
    sys.exit("rsvg-convert not found")


def svg_to_png(svg: Path, out: Path, size: int | None = None, width: int | None = None) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [RSVG, "-f", "png", "-o", str(out), str(svg)]
    if size is not None:
        cmd[1:1] = ["-w", str(size), "-h", str(size)]
    elif width is not None:
        cmd[1:1] = ["-w", str(width)]
    subprocess.check_call(cmd)


def write_ico(pngs: list[Path], ico: Path) -> None:
    """Write a multi-resolution ICO from pre-sized PNGs (largest first for Pillow)."""
    images = [Image.open(p).convert("RGBA") for p in pngs]
    images.sort(key=lambda im: im.width * im.height, reverse=True)
    ico.parent.mkdir(parents=True, exist_ok=True)
    images[0].save(
        ico,
        format="ICO",
        sizes=[(im.width, im.height) for im in images],
        append_images=images[1:],
    )


def main() -> None:
    for size in (16, 32, 48, 64, 128, 256, 512, 1024):
        svg_to_png(HH_MARK, BRAND / f"helmhost-icon-{size}.png", size=size)
    svg_to_png(HH_FULL, BRAND / "helmhost-icon-full-1024.png", size=1024)
    svg_to_png(HH_LOCK, BRAND / "helmhost-lockup.png", width=720)

    mac = ROOT / "apps/client/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        shutil.copyfile(BRAND / f"helmhost-icon-{size}.png", mac / f"app_icon_{size}.png")

    write_ico(
        [BRAND / f"helmhost-icon-{s}.png" for s in (16, 32, 48, 64, 128, 256)],
        ROOT / "apps/client/windows/runner/resources/app_icon.ico",
    )

    fav = BRAND / "favicons"
    for size in (16, 32, 48, 180, 192, 512):
        svg_to_png(HH_MARK, fav / f"favicon-{size}.png", size=size)
    write_ico(
        [fav / "favicon-16.png", fav / "favicon-32.png", fav / "favicon-48.png"],
        fav / "favicon.ico",
    )
    shutil.copyfile(fav / "favicon-180.png", fav / "apple-touch-icon.png")
    shutil.copyfile(fav / "favicon-192.png", fav / "android-chrome-192x192.png")
    shutil.copyfile(fav / "favicon-512.png", fav / "android-chrome-512x512.png")
    (fav / "site.webmanifest").write_text(
        """{
  "name": "Helmhost",
  "short_name": "Helmhost",
  "icons": [
    {"src": "android-chrome-192x192.png", "sizes": "192x192", "type": "image/png"},
    {"src": "android-chrome-512x512.png", "sizes": "512x512", "type": "image/png"}
  ],
  "theme_color": "#11192D",
  "background_color": "#11192D",
  "display": "standalone"
}
""",
        encoding="utf-8",
    )

    docs_theme = ROOT / "docs/theme"
    docs_theme.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(fav / "favicon.ico", docs_theme / "favicon.ico")
    shutil.copyfile(fav / "favicon-32.png", docs_theme / "favicon.png")
    shutil.copyfile(HH_MARK, docs_theme / "favicon.svg")

    print("OK: Helmhost product brand assets exported")
    print(f"  Org brand kit → /Users/am042433/Documents/DEV/bbdevs/brand/ (separate)")


if __name__ == "__main__":
    main()
