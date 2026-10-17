"""VR_MODE=world: Mika's autonomous 3D world, the default production show.

The same presentation profile the DEV server used for the world:
  - Mika is the only character on stage (her reusable cast entry and voice)
  - no 2D ambient walking moves, no automatic camera focus (the world camera
    and her phone decide what viewers see)
  - her session (goals, story, greeted) persists across restarts of a stream
  - no teaching / coding tools (that is class mode)

    VR_MODE=world          turn it on (mika-live.sh does)
    VR_WORLD_HOLD_SPEECH=1 her first words wait until YouTube says "live"
                           (mika-live.sh sets it when OBS is managed)

Minecraft and class mode are separate (VR_MODE=minecraft / VR_CLASS_MODE=1)
and are not affected by anything here.
"""

from __future__ import annotations

import asyncio
import os
import time
from dataclasses import replace
from pathlib import Path

from loguru import logger

SESSION_FILE = Path("data") / "mika-session.json"
# Set when YouTube confirms the broadcast is live (or immediately when there
# is no managed stream). Mika greets viewers only after this.
WORLD_LIVE = asyncio.Event()
HOLD_TIMEOUT_SECONDS = 240.0
_hold_started = 0.0


def world_mode_enabled() -> bool:
    return os.environ.get("VR_MODE", "").strip().lower() == "world"


def apply_world_profile(room):
    """The room as the world show presents it (the room file is unchanged)."""
    mika = [c for c in room.characters if c.id == "mika"]
    if not mika:
        logger.error("World mode: no 'mika' character in the room; the cast is unchanged")
        return room
    room.characters = mika
    room.title = "MIKA'S WORLD"
    room.ambient = replace(room.ambient, moves_enabled=False)
    room.camera = replace(room.camera, auto_focus=False)
    logger.info("World mode: Mika's 3D world (cast: mika)")
    return room


def enable_session(session) -> None:
    """Persistence of her goals and story across restarts of the same stream."""
    try:
        session.lifestyle.enable_persistence(SESSION_FILE)
    except Exception as exc:
        logger.warning(f"World mode: session persistence unavailable: {exc}")


def _flag(name: str) -> bool:
    return os.environ.get(name, "0").strip().lower() in ("1", "true", "yes", "on")


def hold_speech() -> bool:
    # A rehearsal never goes live, so holding would freeze her whole life loop
    # (no greeting, no goals, no movement) for the entire rehearsal. Nothing is
    # published in a rehearsal, so she lives normally there.
    return _flag("VR_WORLD_HOLD_SPEECH") and not _flag("VR_REHEARSAL")


def stream_is_live() -> bool:
    """False while a managed stream is still being prepared (Mika stays quiet).

    A safety timeout releases her after HOLD_TIMEOUT_SECONDS once the stream
    has started, so she is never mute on air if YouTube's confirmation is slow.
    """
    if not world_mode_enabled() or not hold_speech() or WORLD_LIVE.is_set():
        return True
    from ..publishing.obs_control import STREAM_LIVE

    global _hold_started
    if STREAM_LIVE.is_set():
        _hold_started = _hold_started or time.time()
        if time.time() - _hold_started > HOLD_TIMEOUT_SECONDS:
            logger.warning("World mode: YouTube did not confirm 'live' in time; Mika starts anyway")
            WORLD_LIVE.set()
            return True
    return False


def mark_live() -> None:
    WORLD_LIVE.set()
