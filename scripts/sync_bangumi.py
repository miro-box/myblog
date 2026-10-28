#!/usr/bin/env python3
"""把 Bangumi 公开动画收藏同步为 Hugo data 文件。"""
import argparse
import json
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_USER = "1205737"
DEFAULT_OUTPUT = Path("data/bangumi/anime.json")
API_ROOT = "https://api.bgm.tv/v0"
UA = "HugoBlog/1.0 (https://example.com)"
PAGE = 100


def fetch(url):
    req = urllib.request.Request(
        url, headers={"Accept": "application/json", "User-Agent": UA}
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def slim(item):
    s = item.get("subject") or {}
    imgs = s.get("images") or {}
    return {
        "subject_id": item.get("subject_id"),
        "type": item.get("type"),
        "rate": item.get("rate", 0),
        "ep_status": item.get("ep_status", 0),
        "comment": item.get("comment") or "",
        "subject": {
            "name": s.get("name", ""),
            "name_cn": s.get("name_cn", ""),
            "date": s.get("date", ""),
            "score": s.get("score", 0),
            "rank": (s.get("rank") or 0),
            "eps": s.get("eps", 0),
            "images": {
                "common": imgs.get("common", ""),
                "medium": imgs.get("medium", ""),
                "large": imgs.get("large", ""),
            },
        },
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--user", default=DEFAULT_USER)
    ap.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = ap.parse_args()

    items, offset = [], 0
    while True:
        url = (f"{API_ROOT}/users/{args.user}/collections"
               f"?subject_type=2&limit={PAGE}&offset={offset}")
        page = fetch(url)
        data = page.get("data", [])
        items += [slim(i) for i in data]
        offset += PAGE
        if not data or offset >= page.get("total", 0):
            break
        time.sleep(0.5)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(
            {"fetched_at": datetime.now(timezone.utc).isoformat(), "data": items},
            ensure_ascii=False, indent=2,
        ),
        encoding="utf-8",
    )
    print(f"已写入 {len(items)} 条收藏 -> {args.output}")


if __name__ == "__main__":
    main()