"""Canonical viewer identity records for live chat."""

from __future__ import annotations

import json
import os
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from loguru import logger


@dataclass(frozen=True)
class ViewerIdentity:
    platform: str
    channel_id: str
    handle: str
    display_name: str
    fallback: bool = False


def _clean(value: Any, limit: int = 120) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


def normalize_handle(value: Any) -> str:
    handle = _clean(value, 100)
    if not handle:
        return ""
    if handle.startswith("@"):  # YouTube handles are case-preserving for display.
        return handle
    if re.fullmatch(r"[A-Za-z0-9._-]{3,100}", handle):
        return f"@{handle}"
    return ""


def fallback_channel_id(handle: str, display_name: str = "") -> str:
    handle = normalize_handle(handle)
    if handle:
        return f"fallback:handle:{handle.lower()}"
    display = re.sub(r"[^a-z0-9._-]+", "", _clean(display_name, 100).lower())
    return f"fallback:display:{display or 'viewer'}"


class ViewerIdentityStore:
    def __init__(self, path: str | Path | None = None) -> None:
        self.path = Path(path or os.environ.get("VIEWER_IDENTITY_FILE", "data/viewers.json"))
        self.records: dict[str, dict[str, Any]] = {}
        self._load()

    def _load(self) -> None:
        try:
            if not self.path.exists():
                self.records = {}
                return
            data = json.loads(self.path.read_text(encoding="utf-8"))
            raw_records = data.get("viewers", {}) if isinstance(data, dict) else {}
            self.records = {str(k): dict(v) for k, v in raw_records.items() if isinstance(v, dict)}
        except Exception as exc:
            logger.warning(f"Viewer identity store unreadable ({self.path}): {exc}; starting empty")
            self.records = {}

    def _save(self) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(self.path.suffix + ".tmp")
            tmp.write_text(json.dumps({"viewers": self.records}, indent=2, sort_keys=True), encoding="utf-8")
            tmp.replace(self.path)
        except Exception as exc:
            logger.warning(f"Viewer identity store write failed ({self.path}): {exc}")

    @staticmethod
    def _record_key(identity: ViewerIdentity) -> str:
        return f"{identity.platform}:{identity.channel_id}"

    def identify_youtube(self, message: Any) -> ViewerIdentity:
        raw_channel_id = _clean(getattr(message, "author_channel_id", ""), 160)
        stable_channel_id = raw_channel_id if raw_channel_id and not raw_channel_id.startswith(("name:", "fallback:")) else ""
        display_name = _clean(getattr(message, "author_display_name", ""), 100) or "Viewer"
        handle = normalize_handle(getattr(message, "author_handle", "")) or normalize_handle(display_name)
        channel_id = stable_channel_id or fallback_channel_id(handle, display_name)
        return ViewerIdentity(
            platform="youtube",
            channel_id=channel_id,
            handle=handle,
            display_name=display_name,
            fallback=not bool(stable_channel_id),
        )

    def note(self, identity: ViewerIdentity) -> None:
        key = self._record_key(identity)
        now = time.time()
        existing = self.records.get(key, {})
        self.records[key] = {
            "platform": identity.platform,
            "channel_id": identity.channel_id,
            "handle": identity.handle,
            "display_name": identity.display_name,
            "last_seen": now,
            "message_count": int(existing.get("message_count", 0) or 0) + 1,
        }
        self._save()
