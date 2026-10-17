"""The stream's day counter and live totals (data/launch_days.json).

Day 1 is the calendar day of the FIRST PUBLIC broadcast, in Asia/Manila time; every later calendar day counts,
streamed or not ("Day N" = local date - first local date + 1). The file also keeps the total number of public
broadcasts and the total hours live. Test streams (VR_TEST_STREAM=1) and rehearsals never touch it.

    {"timezone": "Asia/Manila", "first_launch": "2026-10-17T03:40:00+08:00",
     "broadcasts": 1, "hours_live": 2.25,
     "current": {"broadcast_id": "...", "started": "...", "counted_until": "...", "day_titled": 1}}
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Optional
from zoneinfo import ZoneInfo

from loguru import logger

FILE = Path(os.environ.get("VR_LAUNCH_DAYS_FILE", "")) if os.environ.get("VR_LAUNCH_DAYS_FILE") else (
    Path(__file__).resolve().parents[3] / "data" / "launch_days.json")
ZONE = ZoneInfo("Asia/Manila")


def _flag(name: str) -> bool:
    return os.environ.get(name, "0").strip().lower() in ("1", "true", "yes", "on")


def counting() -> bool:
    """Only real public streams count (never a test stream or a rehearsal)."""
    return not (_flag("VR_TEST_STREAM") or _flag("VR_REHEARSAL") or _flag("VR_PRELIVE_DRY_RUN"))


def load() -> dict[str, Any]:
    try:
        return json.loads(FILE.read_text())
    except Exception:
        return {}


def _save(d: dict[str, Any]) -> None:
    FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(d, indent=1))
    tmp.replace(FILE)


def now() -> datetime:
    return datetime.now(ZONE)


def day_number(at: Optional[datetime] = None, data: Optional[dict[str, Any]] = None) -> int:
    """Day N (1 on the launch day). Before the first public launch: the day it would be if it launched now (1)."""
    d = data if data is not None else load()
    at = (at or now()).astimezone(ZONE)
    first = d.get("first_launch")
    if not first:
        return 1
    return (at.date() - datetime.fromisoformat(first).astimezone(ZONE).date()).days + 1


def title_with_day(title: str, day: Optional[int] = None) -> str:
    """"Day N | <title>" (an existing "Day M | " prefix is replaced), at most 100 characters."""
    base = title.split(" | ", 1)[1] if title.startswith("Day ") and " | " in title[:12] else title
    return f"Day {day or day_number()} | {base}"[:100]


def went_live(broadcast_id: str) -> dict[str, Any]:
    """A public broadcast is live: the first one ever sets Day 1; each new broadcast counts once."""
    d = load()
    if not counting():
        return d
    t = now()
    if not d.get("first_launch"):
        d.update({"timezone": "Asia/Manila", "first_launch": t.isoformat(timespec="seconds"), "broadcasts": 0, "hours_live": 0.0})
        logger.info(f"Launch day: Day 1 is {t.date()} (Asia/Manila)")
    cur = d.get("current") or {}
    if cur.get("broadcast_id") != broadcast_id:
        _close_current(d, t)
        d["broadcasts"] = int(d.get("broadcasts", 0)) + 1
        d["current"] = {"broadcast_id": broadcast_id, "started": t.isoformat(timespec="seconds"),
                        "counted_until": t.isoformat(timespec="seconds"), "day_titled": day_number(t, d)}
    _save(d)
    return d


def _close_current(d: dict[str, Any], t: datetime) -> None:
    cur = d.get("current") or {}
    if cur.get("counted_until"):
        add = (t - datetime.fromisoformat(cur["counted_until"])).total_seconds() / 3600.0
        if 0 < add < 13:                                 # a crash gap longer than a broadcast is never counted
            d["hours_live"] = round(float(d.get("hours_live", 0.0)) + add, 3)
    d.pop("current", None)


def tick() -> Optional[int]:
    """Called every minute while live: adds the live time, and returns the new day number once when the calendar
    day changed during this broadcast (the caller retitles the live broadcast), else None."""
    d = load()
    cur = d.get("current")
    if not counting() or not cur:
        return None
    t = now()
    add = (t - datetime.fromisoformat(cur["counted_until"])).total_seconds() / 3600.0
    if 0 < add < 0.5:                                    # minutes since the last tick (a long gap is a stop, not live)
        d["hours_live"] = round(float(d.get("hours_live", 0.0)) + add, 3)
    cur["counted_until"] = t.isoformat(timespec="seconds")
    day = day_number(t, d)
    changed = day != int(cur.get("day_titled", day))
    if changed:
        cur["day_titled"] = day
    _save(d)
    return day if changed else None


def ended() -> None:
    d = load()
    if d.get("current"):
        _close_current(d, now())
        _save(d)


def summary() -> dict[str, Any]:
    d = load()
    return {"day": day_number(data=d), "first_launch": d.get("first_launch"), "broadcasts": int(d.get("broadcasts", 0)),
            "hours_live": round(float(d.get("hours_live", 0.0)), 1), "live": bool(d.get("current"))}
