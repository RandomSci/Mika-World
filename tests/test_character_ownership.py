"""Character ownership: the character a viewer names is the one who answers
("Mikaaaa How are you?" is Mika's, never Luna's).

These run the real path (viewer message -> room router -> ConversationDirector
-> speaking character) with the LLM replaced by stubs, because the routing and
ownership logic under test is deterministic and does not need a model.
"""

from __future__ import annotations

import asyncio
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
sys.path.insert(0, str(ROOT))

from open_llm_vtuber.room.live_message import LiveMessage  # noqa: E402
from open_llm_vtuber.room.profiles import load_room  # noqa: E402
from open_llm_vtuber.room.session import RoomSession  # noqa: E402


class Room:
    """A room whose characters answer with a stub instead of an LLM."""

    def __init__(self):
        self.session = RoomSession(load_room(ROOT / "room", ROOT))
        self.spoke: list[tuple[str, str]] = []  # (character, turn kind)

        async def turn_runner(turn, prompt, plan):
            self.spoke.append((turn.speaker, turn.kind))
            return f"{turn.speaker} speaks."

        self.session.director.turn_runner = turn_runner

    def say(self, text: str, user: str = "@selwyn") -> list[tuple[str, str]]:
        """One viewer comment, all the way through. Returns who spoke."""
        before = len(self.spoke)
        message = LiveMessage(
            platform="dev",
            message_id=f"t-{time.time_ns()}",
            username=user,
            text=text,
            timestamp=time.time(),
            author_id=f"dev:{user.lstrip('@')}",
        )

        async def go():
            if self.session.observe_viewer_message(message):
                return
            plan = self.session.director.plan(message)
            if plan.turns:
                await self.session.director.run(plan)

        asyncio.run(go())
        return self.spoke[before:]

    def speakers(self, text: str, user: str = "@selwyn") -> list[str]:
        return [who for who, _ in self.say(text, user)]


# ---------------------------------------------------------------------------
# normal room, no coding session
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text,expected",
    [
        ("mika how are you?", "mika"),
        ("Mika how are you?", "mika"),
        ("Mikaaaa How are you?", "mika"),  # chat stretches names
        ("MIKA!! hello", "mika"),
        ("@mika hi", "mika"),
        ("luna how are you?", "luna"),
        ("Luuuna hi", "luna"),
        ("Why is she answering for you mika", "mika"),
    ],
)
def test_named_character_answers_in_the_normal_room(text, expected):
    room = Room()
    assert room.speakers(text)[0] == expected


def test_unaddressed_chat_still_works():
    room = Room()
    assert room.speakers("hello everyone")


def test_the_card_target_follows_the_real_speaker():
    """TO MIKA / TO LUNA is backend ownership, not decoration."""
    room = Room()
    message = LiveMessage(
        platform="dev",
        message_id="t-card",
        username="@selwyn",
        text="mika how are you?",
        timestamp=time.time(),
        author_id="dev:selwyn",
    )
    plan = room.session.director.plan(message)
    asyncio.run(room.session.director.run(plan))
    assert plan.turns[0].speaker == "mika"
    assert room.spoke[0][0] == "mika"
