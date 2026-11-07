#!/usr/bin/env python3
"""Build a site-only subset of LXGW WenKai (woff2) and the matching CSS.

Run from the repo root:   python scripts/build_font.py
Needs:                    pip install fonttools brotli

What it does
  1. scans the site for every character it can show
     (content, data, i18n, config, layouts, theme i18n, scripts/font-extra.txt)
  2. cuts those characters out of the full font
  3. writes static/fonts/wenkai-sub.<hash>.woff2 and static/fonts/wenkai-sub.css
     (the hash changes only when the character set changes, so browsers and
      Cloudflare never serve a stale font)

Options
  --font PATH        source font (default: fonts-src/LXGWWenKai-Regular.ttf, downloaded if missing)
  --common           also include the 3755 most common hanzi (GB2312 level 1), about +350 KB
  --gallery          also scan data/waifus.json (gallery tags, lots of rare characters)
  --flavor woff      write plain woff instead of woff2 (only for testing without brotli)
"""
import argparse
import hashlib
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONT_FAMILY = "LXGW WenKai Sub"
OUT_DIR = ROOT / "static" / "fonts"
DEFAULT_SRC = ROOT / "fonts-src" / "LXGWWenKai-Regular.ttf"
DOWNLOAD_URL = "https://github.com/lxgw/LxgwWenKai/releases/download/v1.521/LXGWWenKai-Regular.ttf"

SCAN = [
    ("content", {".md", ".html", ".txt", ".yml", ".yaml", ".json", ".toml"}),
    ("data", {".yml", ".yaml", ".json", ".toml", ".csv"}),
    ("i18n", {".yml", ".yaml", ".toml", ".json"}),
    ("config", {".yml", ".yaml", ".toml", ".json"}),
    ("layouts", {".html", ".xml"}),
    ("themes", {".yml", ".yaml"}),  # only i18n files below themes (filtered in code)
]


def read_text(path: Path) -> str:
    for enc in ("utf-8", "utf-8-sig", "gb18030"):
        try:
            return path.read_text(encoding=enc)
        except (UnicodeDecodeError, OSError):
            continue
    return ""


def collect_chars(include_gallery: bool) -> set:
    chars = set()
    for folder, exts in SCAN:
        base = ROOT / folder
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if not p.is_file() or p.suffix.lower() not in exts:
                continue
            parts = {x.lower() for x in p.parts}
            if folder == "themes" and "i18n" not in parts:
                continue
            if p.name == "waifus.json" and not include_gallery:
                continue
            chars.update(read_text(p))
    extra = ROOT / "scripts" / "font-extra.txt"
    if extra.exists():
        chars.update(read_text(extra))
    return {c for c in chars if not c.isspace() and c.isprintable()}


def gb2312_level1() -> str:
    out = []
    for hi in range(0xB0, 0xD8):
        for lo in range(0xA1, 0xFF):
            try:
                out.append(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return "".join(out)


def baseline() -> set:
    s = {chr(c) for c in range(0x20, 0x7F)}
    s.update("，。、；：？！“”‘’（）《》〈〉【】「」『』…—－·～＋＝％＄＠＃＆＊／＼｜")
    s.update("0123456789")
    return s


def find_font(arg):
    if arg:
        return Path(arg)
    if DEFAULT_SRC.exists():
        return DEFAULT_SRC
    src_dir = ROOT / "fonts-src"
    if src_dir.exists():
        for p in sorted(src_dir.iterdir()):
            n = p.name.lower()
            if "wenkai" in n and "mono" not in n and n.endswith((".ttf", ".otf")):
                return p
    print("Source font not found, downloading LXGW WenKai (about 25 MB) ...")
    DEFAULT_SRC.parent.mkdir(parents=True, exist_ok=True)
    ok = False
    try:
        urllib.request.urlretrieve(DOWNLOAD_URL, DEFAULT_SRC)
        ok = True
    except Exception as e:  # noqa: BLE001
        print(f"Python download failed: {e}")
        print("Trying curl.exe (uses the system certificates) ...")
        try:
            r = subprocess.run(["curl", "-L", "--fail", "-o", str(DEFAULT_SRC), DOWNLOAD_URL])
            ok = r.returncode == 0 and DEFAULT_SRC.exists() and DEFAULT_SRC.stat().st_size > 1_000_000
        except OSError:
            ok = False
    if not ok:
        if DEFAULT_SRC.exists():
            DEFAULT_SRC.unlink()
        print("Download failed.")
        print("Please download LXGWWenKai-Regular.ttf by hand from")
        print("  https://github.com/lxgw/LxgwWenKai/releases")
        print(f"and put it into: {DEFAULT_SRC.parent}")
        sys.exit(1)
    return DEFAULT_SRC


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font")
    ap.add_argument("--common", action="store_true")
    ap.add_argument("--gallery", action="store_true")
    ap.add_argument("--flavor", default="woff2", choices=["woff2", "woff"])
    args = ap.parse_args()

    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
    except ImportError:
        print("Missing fonttools. Run:  pip install fonttools brotli")
        sys.exit(1)
    if args.flavor == "woff2":
        try:
            import brotli  # noqa: F401
        except ImportError:
            print("Missing brotli. Run:  pip install brotli")
            sys.exit(1)

    font_path = find_font(args.font)
    chars = collect_chars(args.gallery) | baseline()
    if args.common:
        chars.update(gb2312_level1())
    text = "".join(sorted(chars))
    print(f"Source font : {font_path}")
    print(f"Characters  : {len(chars)} unique")

    opts = subset.Options()
    opts.flavor = args.flavor
    opts.layout_features = ["*"]
    opts.hinting = False
    opts.name_IDs = [1, 2, 3, 4, 6]
    opts.notdef_outline = True
    opts.drop_tables += ["DSIG"]
    font = TTFont(str(font_path), recalcTimestamp=False)
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    font.flavor = args.flavor

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tmp = OUT_DIR / "_tmp_subset"
    font.save(str(tmp))
    data = tmp.read_bytes()
    tmp.unlink()

    digest = hashlib.sha1(data).hexdigest()[:8]
    ext = "woff2" if args.flavor == "woff2" else "woff"
    name = f"wenkai-sub.{digest}.{ext}"
    target = OUT_DIR / name
    target.write_bytes(data)
    # Keep the previous build next to the new one: a browser or CDN that still
    # holds the old CSS keeps working instead of falling back to the system font.
    olds = sorted(
        (f for f in OUT_DIR.glob("wenkai-sub.*.woff*") if f != target),
        key=lambda f: f.stat().st_mtime,
        reverse=True,
    )
    for stale in olds[1:]:
        stale.unlink()

    fmt = "woff2" if args.flavor == "woff2" else "woff"
    css = (
        "@font-face{"
        f"font-family:'{FONT_FAMILY}';font-style:normal;font-weight:400;font-display:swap;"
        f"src:url('/fonts/{name}') format('{fmt}');"
        "}\n"
    )
    (OUT_DIR / "wenkai-sub.css").write_text(css, encoding="utf-8")

    print(f"Output      : static/fonts/{name}  ({len(data) / 1024:.0f} KB)")
    print("CSS         : static/fonts/wenkai-sub.css")
    print()
    print("params.yml  : custom_font -> enable: true, css: /fonts/wenkai-sub.css, name: " + FONT_FAMILY)


if __name__ == "__main__":
    main()
