"""The stream runs itself: the 12 hour limit, the goodbye and ending the broadcast.

    VR_MAX_LIVE_MINUTES=715              say goodbye and end the stream at 11h55m
                                         (YouTube keeps no archive past 12 hours); 0 = off
    OBS_WEBSOCKET_URL / OBS_WEBSOCKET_PASSWORD
                                         when set, OBS is told to stop streaming too

Everything here needs the YouTube sign-in (scripts/youtube_authorize.py) and
YOUTUBE_PUBLISHING_ENABLED=true. With PUBLISHING_DRY_RUN=true it only logs what
it would do. Nothing here ever raises into the stream.
"""

from __future__ import annotations

import asyncio
import os
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Awaitable, Callable, Optional

from loguru import logger


def _flag(name: str, default: str = "0") -> bool:
    return os.environ.get(name, default).strip().lower() in ("1", "true", "yes", "on")



def _goodbye_delay() -> float:
    try:
        return max(0.0, float(os.environ.get("VR_GOODBYE_DELAY", "10") or 10))
    except ValueError:
        return 10.0


class StreamAutopilot:
    def __init__(self, publisher: Any) -> None:
        self.publisher = publisher
        self.settings = publisher.settings
        self.max_minutes = float(os.environ.get("VR_MAX_LIVE_MINUTES", "715") or 0)
        self.goodbye: Optional[Callable[[str], Awaitable[None]]] = None
        self.shutdown: Optional[Callable[[], None]] = None
        self.task: Optional[asyncio.Task] = None
        self._ended = False
        self.farewell = "That's the end of Mika's stream for today! Thanks for hanging out with her, see you next time 👋"
        self.goodbye_timeout = 15.0

    # ------------------------------------------------------------ helpers
    @property
    def ready(self) -> bool:
        s = self.settings
        return bool(s.youtube_enabled and (s.dry_run or s.youtube_ready))

    async def _client_call(self, fn: Callable[..., Any], *args: Any) -> Any:
        return await asyncio.to_thread(fn, *args)

    def _video_id(self, client: Any, fresh: bool = False) -> str:
        if fresh:
            try:
                return self.publisher._video_id(client, fresh=True)
            except TypeError:  # a publisher without the fresh option
                pass
        return self.publisher._video_id(client)

    # ------------------------------------------------------------ start
    def start(self) -> None:
        if not self.ready or (self.task and not self.task.done()):
            return
        self.task = asyncio.create_task(self._run(), name="stream-autopilot")

    async def _run(self) -> None:
        if self.max_minutes <= 0:
            return
        logger.info(f"Stream autopilot: the stream ends by itself after {self.max_minutes:.0f} minutes live")
        started_at = 0.0
        while not self._ended:
            await asyncio.sleep(60)
            try:
                if not started_at:
                    started_at = await self._started_at()
                if started_at and time.time() - started_at >= self.max_minutes * 60:
                    await self.end_stream("limit")
                    return
            except Exception as exc:
                logger.debug(f"Stream autopilot check failed: {exc}")

    async def _started_at(self) -> float:
        if self.settings.dry_run:
            return 0.0
        client = self.publisher._youtube_factory()
        video_id = await self._client_call(self._video_id, client)
        if not video_id:
            return 0.0
        iso = await self._client_call(client.live_started_at, video_id)
        if not iso:
            return 0.0
        started = datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()
        logger.info(f"Stream autopilot: live since {iso}")
        from ..live.clip_marks import CLIPS

        CLIPS.set_live(started, video_id)
        return started

    # ------------------------------------------------------------ ending
    async def end_stream(self, reason: str = "limit") -> None:
        """Goodbye (chat message at the same time), the broadcast ends through
        the YouTube API, OBS stops and closes, then the server stops."""
        if self._ended:
            return
        self._ended = True
        logger.warning(f"Stream autopilot: ending the stream ({reason})")
        if reason == "limit":
            # mika-live.sh starts the next broadcast by itself after the 11h55m end (VR_RESTART_AFTER_LIMIT)
            try:
                Path("logs").mkdir(exist_ok=True)
                Path("logs/mika-live-limit").write_text(datetime.now().isoformat(timespec="seconds"))
            except OSError:
                pass
        chat = asyncio.create_task(
            self.post_chat(self.farewell)
        )
        if self.goodbye:
            try:
                await asyncio.wait_for(self.goodbye(reason), timeout=self.goodbye_timeout)
            except Exception as exc:
                logger.warning(f"Goodbye failed: {exc}")
        try:
            await asyncio.wait_for(chat, timeout=5)
        except Exception:
            pass
        # The last words reach viewers first: the stream runs a few seconds
        # behind, and ending it 2 s after the goodbye cut the goodbye off.
        await asyncio.sleep(_goodbye_delay())
        if not self.settings.dry_run and self.settings.youtube_ready:
            try:
                client = self.publisher._youtube_factory()
                video_id = await self._client_call(self._video_id, client)
                if video_id:
                    await self._client_call(client.end_broadcast, video_id)
                    logger.info("Stream autopilot: YouTube broadcast ended")
            except Exception as exc:
                logger.warning(f"Could not end the broadcast through YouTube: {exc}")
        from .obs_control import stop_and_close

        await stop_and_close()
        if self.shutdown:
            self.shutdown()

    async def post_chat(self, text: str) -> None:
        s = self.settings
        if not (s.youtube_enabled and s.youtube_chat_enabled):
            return
        if s.dry_run:
            logger.info(f"Dry run: would post in chat: {text}")
            return
        try:
            client = self.publisher._youtube_factory()
            video_id = await self._client_call(self._video_id, client)
            chat_id = await self._client_call(client.active_live_chat_id, video_id) if video_id else ""
            if chat_id:
                await self._client_call(client.post_chat_message, chat_id, text)
        except Exception as exc:
            logger.debug(f"Goodbye chat message failed: {exc}")
