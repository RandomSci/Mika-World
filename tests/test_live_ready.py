"""Live chat intake: our own channel's posts and banned names are never read."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
sys.path.insert(0, str(ROOT))


def test_our_own_channel_and_banned_names_are_never_read(monkeypatch):
    from datetime import datetime, timezone

    from open_llm_vtuber.live.youtube_live import YouTubeChatMessage, blocked_author_reason

    def msg(author, text, author_type=""):
        return YouTubeChatMessage(
            message_id="x",
            author_channel_id="name:" + author.lower(),
            author_display_name=author,
            text=text,
            timestamp=datetime.now(timezone.utc),
            author_type=author_type,
        )

    monkeypatch.delenv("VR_IGNORE_OWNER", raising=False)
    monkeypatch.setenv("VR_BANNED_AUTHORS", "@SelwynBuilds-j1s, spam bot")
    assert blocked_author_reason(msg("@SelwynBuilds-j1s", "make a game")) == "banned"
    assert blocked_author_reason(msg("@spambot", "hi")) == "banned"
    # the channel owner can talk to the girls too (only what the system posted itself is skipped)
    assert blocked_author_reason(msg("@owner", "hi", "owner")) == ""
    echo = "@ana your game is up 🎮 https://x.github.io/g/ (give it about 5 minutes)"
    assert blocked_author_reason(msg("@someone", echo)) == "our own announcement"
    assert blocked_author_reason(msg("@MathUnlockedYT", "build a snake game")) == ""
    monkeypatch.setenv("VR_IGNORE_OWNER", "1")
    assert blocked_author_reason(msg("@owner", "hi", "owner")) == "channel owner"
