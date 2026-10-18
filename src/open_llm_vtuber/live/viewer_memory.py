"""Per-viewer memory for live chat (Day 3).

What a viewer said, how they write (tone, emoji, language), which streams they came to - so Mika can greet a returning
viewer by name and naturally pick up something they said before. Entries older than RETENTION_DAYS (default 20) are
deleted automatically; a viewer not seen for that long is forgotten entirely. Spam and harmful messages are never
stored (the chat guard runs first).

Privacy: one small JSON file, data/viewer_memory.json by default (VR_VIEWER_MEMORY_FILE). It is gitignored and must
never be committed or pushed: this repository is public.
"""

from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path
from typing import Any, Callable, Optional

from loguru import logger

RETENTION_DAYS = float(os.environ.get("VR_VIEWER_MEMORY_DAYS", "20"))
MAX_SAID = 8            # remembered messages per viewer
MAX_VIEWERS = 5000      # most recent viewers kept
SAVE_EVERY_S = 30.0

_EMOJI_RE = re.compile("[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F1E6-\U0001F1FF]")
_LAUGH_RE = re.compile(r"\b(lol|lmao|haha+|hehe+|xd|rofl|kek)\b", re.IGNORECASE)


def _clean(text: Any, limit: int = 160) -> str:
    return re.sub(r"\s+", " ", str(text or "")).strip()[:limit]


def writing_style(texts: list[str]) -> dict[str, Any]:
    """How someone writes, from their recent messages: language guess, emoji, laughter, energy, length."""
    joined = " ".join(texts)
    if not joined:
        return {}
    letters = [c for c in joined if c.isalpha()]
    latin = sum(1 for c in letters if c.isascii())
    lang = "en" if not letters or latin / len(letters) > 0.8 else "other"
    if lang == "other":
        if re.search(r"[぀-ヿ]", joined):
            lang = "ja"
        elif re.search(r"[一-鿿]", joined):
            lang = "zh"
        elif re.search(r"[가-힯]", joined):
            lang = "ko"
        elif re.search(r"[Ѐ-ӿ]", joined):
            lang = "ru"
    emoji = len(_EMOJI_RE.findall(joined))
    caps = sum(1 for c in letters if c.isupper()) / max(1, len(letters))
    tone = []
    if _LAUGH_RE.search(joined):
        tone.append("jokey")
    if joined.count("!") >= max(2, len(texts)) or caps > 0.5:
        tone.append("excited")
    if joined.count("?") >= max(1, len(texts) // 2):
        tone.append("curious")
    if not tone:
        tone.append("calm")
    avg = sum(len(t) for t in texts) / max(1, len(texts))
    return {"language": lang, "emoji": "lots" if emoji >= len(texts) else ("some" if emoji else "none"),
            "tone": tone, "length": "short" if avg < 25 else ("long" if avg > 120 else "medium")}


class ViewerMemoryStore:
    def __init__(self, path: str | Path | None = None, clock: Callable[[], float] = time.time) -> None:
        self.path = Path(path or os.environ.get("VR_VIEWER_MEMORY_FILE", "data/viewer_memory.json"))
        self.clock = clock
        self.viewers: dict[str, dict[str, Any]] = {}
        self.here: set[str] = set()          # viewers who wrote during THIS stream
        self.stream_id = ""
        self.info_for: dict[str, dict[str, Any]] = {}   # message id -> what she knew at intake (read by the reply)
        self._saved_at = 0.0
        self._load()
        self.expire()

    # ---------------------------------------------------------------- storage
    def _load(self) -> None:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8")) if self.path.exists() else {}
            raw = data.get("viewers", {}) if isinstance(data, dict) else {}
            self.viewers = {str(k): dict(v) for k, v in raw.items() if isinstance(v, dict)}
        except Exception as exc:
            logger.warning(f"Viewer memory unreadable ({self.path}): {exc}; starting empty")
            self.viewers = {}

    def save(self, force: bool = False) -> None:
        now = self.clock()
        if not force and now - self._saved_at < SAVE_EVERY_S:
            return
        self._saved_at = now
        try:
            if len(self.viewers) > MAX_VIEWERS:
                keep = sorted(self.viewers.items(), key=lambda kv: -float(kv[1].get("last_seen", 0)))[:MAX_VIEWERS]
                self.viewers = dict(keep)
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(self.path.suffix + ".tmp")
            tmp.write_text(json.dumps({"viewers": self.viewers}, ensure_ascii=False, indent=1), encoding="utf-8")
            tmp.replace(self.path)
        except Exception as exc:
            logger.warning(f"Viewer memory write failed ({self.path}): {exc}")

    def expire(self) -> int:
        """Delete what is older than the retention window; a viewer with nothing left is forgotten. Returns removed."""
        cutoff = self.clock() - RETENTION_DAYS * 86400.0
        removed = 0
        for key in list(self.viewers):
            v = self.viewers[key]
            if float(v.get("last_seen", 0)) < cutoff:
                del self.viewers[key]
                removed += 1
                continue
            said = [s for s in v.get("said") or [] if float(s.get("t", 0)) >= cutoff]
            removed += len(v.get("said") or []) - len(said)
            v["said"] = said
            v["streams"] = [s for s in v.get("streams") or [] if float(s.get("t", 0)) >= cutoff]
            v["replies"] = [r for r in v.get("replies") or [] if float(r.get("t", 0)) >= cutoff]
        if removed:
            self.save(force=True)
        return removed

    # ---------------------------------------------------------------- use
    def begin_stream(self, stream_id: str) -> None:
        if stream_id and stream_id != self.stream_id:
            self.stream_id = stream_id
            self.here.clear()

    def observe(self, key: str, display_name: str, text: str, handle: str = "") -> dict[str, Any]:
        """Remember a (clean) message. Returns what Mika may know about this viewer right now."""
        now = self.clock()
        known = key in self.viewers
        v = self.viewers.get(key) or {"first_seen": now, "said": [], "streams": [], "replies": [], "messages": 0}
        before = self.describe_entry(v, key, first_this_stream=key not in self.here, known=known)
        before["name"] = before.get("name") or _clean(display_name, 60) or "Viewer"
        first = key not in self.here
        if first:
            self.here.add(key)
            v.setdefault("streams", []).append({"t": now, "id": self.stream_id})
        v["display_name"] = _clean(display_name, 60) or v.get("display_name") or "Viewer"
        if handle:
            v["handle"] = _clean(handle, 60)
        v["last_seen"] = now
        v["messages"] = int(v.get("messages", 0)) + 1
        v["said"] = (list(v.get("said") or []) + [{"t": now, "text": _clean(text), "stream": self.stream_id}])[-MAX_SAID:]
        v["style"] = writing_style([s["text"] for s in v["said"]])
        self.viewers[key] = v
        self.save()
        return before

    def retract(self, key: str, text: str) -> None:
        """A message that moderation flagged after intake is not remembered."""
        v = self.viewers.get(key)
        if v is not None:
            v["said"] = [x for x in v.get("said") or [] if x.get("text") != _clean(text)]
            self.save(force=True)

    def note_reply(self, key: str, text: str) -> None:
        v = self.viewers.get(key)
        if v is not None:
            v["replies"] = (list(v.get("replies") or []) + [{"t": self.clock(), "text": _clean(text, 140)}])[-4:]
            self.save()

    def describe_entry(self, v: dict[str, Any], key: str, first_this_stream: bool, known: bool = True) -> dict[str, Any]:
        now = self.clock()
        streams = [s for s in v.get("streams") or [] if s.get("id") != self.stream_id or not self.stream_id]
        earlier = [s for s in v.get("said") or [] if s.get("stream") != self.stream_id or not self.stream_id]
        last_seen = float(v.get("last_seen", 0) or 0)
        returning = known and bool(earlier) and (now - last_seen) > 1800
        return {"known": known, "returning": returning, "first_this_stream": first_this_stream,
                "name": v.get("display_name", ""), "visits": len(streams),
                "days_since": round((now - last_seen) / 86400.0, 1) if last_seen else None,
                "earlier": [s["text"] for s in earlier[-3:]], "style": v.get("style", {}),
                "last_reply": (v.get("replies") or [{}])[-1].get("text", "")}

    def prompt_note(self, info: dict[str, Any]) -> str:
        """One short note for the reply prompt (empty when there is nothing worth saying)."""
        if not info or not info.get("name"):
            return ""
        name = info["name"]
        style = info.get("style") or {}
        how = ""
        if style:
            bits = [", ".join(style.get("tone", []))]
            if style.get("emoji") == "lots":
                bits.append("lots of emoji")
            if style.get("language") not in (None, "en"):
                bits.append(f"usually writes in {style['language']}")
            how = f" They tend to write: {'; '.join(b for b in bits if b)}."
        if info.get("returning") and info.get("first_this_stream"):
            days = info.get("days_since") or 0
            when = "earlier today" if days < 1 else ("yesterday" if days < 2 else f"{int(days)} days ago")
            earlier = info.get("earlier") or []
            ref = f' Last time they said: "{earlier[-1][:90]}".' if earlier else ""
            return (f"{name} is a RETURNING viewer (last here {when}). Greet them back by name warmly and briefly; you may "
                    f"mention what they said before only if it fits naturally, never read it out word for word.{ref}{how}")
        if not info.get("known") and info.get("first_this_stream"):
            return f"{name} is NEW here (first message ever): a short, warm welcome by name."
        return how.strip()


_STORE: Optional[ViewerMemoryStore] = None


def store() -> ViewerMemoryStore:
    """The process-wide store (chat intake and the reply share it)."""
    global _STORE
    if _STORE is None:
        _STORE = ViewerMemoryStore()
    return _STORE
