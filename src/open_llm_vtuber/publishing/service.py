"""The YouTube publisher: the signed-in YouTube client and the live video it acts on.

Used by the stream autopilot (ending the broadcast, the farewell chat line) and
the pre-live step. Credentials come from the server's environment only and are
never logged.
"""

from __future__ import annotations

import time
from typing import Callable, Optional

from loguru import logger

from .settings import PublishSettings, save_refresh_token
from .youtube import YouTubeClient, YouTubeError


class PublicationService:
    def __init__(
        self,
        settings: PublishSettings,
        youtube_factory: Optional[Callable[[], YouTubeClient]] = None,
    ):
        self.settings = settings
        self._youtube_factory = youtube_factory or self._default_youtube
        self._found_video_id = ""
        self._found_at = 0.0

    # -- wiring ---------------------------------------------------------------
    def _default_youtube(self) -> YouTubeClient:
        s = self.settings
        token_file = s.youtube_token_file

        def keep(token: str) -> None:
            s.youtube_refresh_token = token
            save_refresh_token(token, token_file)

        return YouTubeClient(
            s.youtube_client_id,
            s.youtube_client_secret,
            s.youtube_refresh_token,
            on_refresh_token=keep,
        )

    VIDEO_ID_TTL = 600.0

    def _video_id(
        self, client: Optional[YouTubeClient] = None, fresh: bool = False
    ) -> str:
        """YOUTUBE_VIDEO_ID if set, else the broadcast that is live right now.

        Found with liveBroadcasts.list (1 unit), cached for ten minutes, and
        searched again when the cached stream has no chat. The channel search
        (100 units) is only a fallback.
        """
        s = self.settings
        if s.youtube_video_id:
            return s.youtube_video_id
        now = time.time()
        if (
            not fresh
            and self._found_video_id
            and now - self._found_at < self.VIDEO_ID_TTL
        ):
            return self._found_video_id
        if not s.youtube_ready:
            return ""
        try:
            client = client or self._youtube_factory()
            found = client.find_active_broadcast_video_id()
            if not found:
                # the broadcast being started right now (still upcoming): its
                # title and thumbnail can be set before it goes live
                from .obs_control import TARGET_BROADCAST

                found = TARGET_BROADCAST
            if not found and s.youtube_channel_id and now - getattr(self, "_searched_at", 0.0) > 1800:
                # 100 quota units a call: it ran out the daily search quota
                self._searched_at = now
                found = client.find_live_video_by_channel(s.youtube_channel_id)
        except YouTubeError as exc:
            logger.warning(f"Could not find the live stream: {exc}")
            found = ""
        self._found_video_id, self._found_at = found, (now if found else 0.0)
        if found:
            logger.info(f"Live stream found automatically: {found}")
        return found
