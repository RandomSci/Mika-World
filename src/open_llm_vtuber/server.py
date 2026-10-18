"""
Open-LLM-VTuber Server
========================
This module contains the WebSocket server for Open-LLM-VTuber, which handles
the WebSocket connections, serves static files, and manages the web tool.
It uses FastAPI for the server and Starlette for static file serving.
"""

import asyncio
import os
import shutil

from fastapi import FastAPI
from loguru import logger
from starlette.middleware.cors import CORSMiddleware
from starlette.responses import Response
from starlette.staticfiles import StaticFiles as StarletteStaticFiles

from .routes import init_client_ws_route, init_webtool_routes, init_proxy_route
from .service_context import ServiceContext
from .config_manager.utils import Config
from .websocket_handler import WebSocketHandler
from .live.youtube_live import YouTubeLiveChatService


# Create a custom StaticFiles class that adds CORS headers
class CORSStaticFiles(StarletteStaticFiles):
    """
    Static files handler that adds CORS headers to all responses.
    Needed because Starlette StaticFiles might bypass standard middleware.
    """

    async def get_response(self, path: str, scope):
        response = await super().get_response(path, scope)

        # Add CORS headers to all responses
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "*"

        if path.endswith(".js"):
            response.headers["Content-Type"] = "application/javascript"

        return response


class AvatarStaticFiles(CORSStaticFiles):
    """
    Avatar files handler with security restrictions and CORS headers
    """

    async def get_response(self, path: str, scope):
        allowed_extensions = (".jpg", ".jpeg", ".png", ".gif", ".svg")
        if not any(path.lower().endswith(ext) for ext in allowed_extensions):
            return Response("Forbidden file type", status_code=403)
        response = await super().get_response(path, scope)
        return response


class WebSocketServer:
    """
    API server for Open-LLM-VTuber. This contains the websocket endpoint for the client, hosts the web tool, and serves static files.

    Creates and configures a FastAPI app, registers all routes
    (WebSocket, web tools, proxy) and mounts static assets with CORS.

    Args:
        config (Config): Application configuration containing system settings.
        default_context_cache (ServiceContext, optional):
            Pre‑initialized service context for sessions' service context to reference to.
            **If omitted, `initialize()` method needs to be called to load service context.**

    Notes:
        - If default_context_cache is omitted, call `await initialize()` to load service context cache.
        - Use `clean_cache()` to clear and recreate the local cache directory.
    """

    def __init__(self, config: Config, default_context_cache: ServiceContext = None):
        self.app = FastAPI(title="Open-LLM-VTuber Server")  # Added title for clarity
        self.config = config
        self.default_context_cache = (
            default_context_cache or ServiceContext()
        )  # Use provided context or initialize a new empty one waiting to be loaded
        # It will be populated during the initialize method call
        self.ws_handler = WebSocketHandler(self.default_context_cache)
        self.youtube_live_service = None

        # Add global CORS middleware
        self.app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

        # The stage pages change with every update: never serve a stale copy.
        @self.app.middleware("http")
        async def no_stale_stage_pages(request, call_next):  # pragma: no cover - thin glue
            response = await call_next(request)
            if request.url.path.startswith("/vr-agent/"):
                response.headers["Cache-Control"] = "no-cache"
            return response

        # Pre-live barrier of the world show (local only, see prelive.py).
        from .publishing.prelive_routes import init_prelive_routes

        self.app.include_router(init_prelive_routes(self.ws_handler))

        # Include routes, passing the context instance
        # The context will be populated during the initialize step
        self.app.include_router(
            init_client_ws_route(ws_handler=self.ws_handler),
        )
        self.app.include_router(
            init_webtool_routes(
                default_context_cache=self.default_context_cache,
                youtube_live_service_getter=lambda: self.youtube_live_service,
                ws_handler=self.ws_handler,
            ),
        )

        # Initialize and include proxy routes if proxy is enabled
        system_config = config.system_config
        if hasattr(system_config, "enable_proxy") and system_config.enable_proxy:
            # Construct the server URL for the proxy
            host = system_config.host
            port = system_config.port
            server_url = f"ws://{host}:{port}/client-ws"
            self.app.include_router(
                init_proxy_route(server_url=server_url),
            )

        # Mount cache directory first (to ensure audio file access)
        if not os.path.exists("cache"):
            os.makedirs("cache")
        self.app.mount(
            "/cache",
            CORSStaticFiles(directory="cache"),
            name="cache",
        )

        # Mount static files with CORS-enabled handlers
        self.app.mount(
            "/live2d-models",
            CORSStaticFiles(directory="live2d-models"),
            name="live2d-models",
        )
        self.app.mount(
            "/bg",
            CORSStaticFiles(directory="backgrounds"),
            name="backgrounds",
        )
        self.app.mount(
            "/avatars",
            AvatarStaticFiles(directory="avatars"),
            name="avatars",
        )

        # Mount web tool directory separately from frontend
        self.app.mount(
            "/web-tool",
            CORSStaticFiles(directory="web_tool", html=True),
            name="web_tool",
        )

        # Mount main frontend last (as catch-all)
        self.app.mount(
            "/",
            CORSStaticFiles(directory="frontend", html=True),
            name="frontend",
        )

    async def initialize(self):
        """Asynchronously load the service context from config.
        Calling this function is needed if default_context_cache was not provided to the constructor."""
        await self.default_context_cache.load_from_config(self.config)
        self.youtube_live_service = YouTubeLiveChatService(
            config=self.config.live_config.youtube_live,
            default_context=self.default_context_cache,
            connection_provider=self.ws_handler,
        )

        @self.app.on_event("startup")
        async def start_youtube_live_service():
            from .vr_agent import VRAgentState, runtime

            if self.youtube_live_service and self.youtube_live_service.enabled():
                await self.youtube_live_service.start()
            else:
                runtime.set(VRAgentState.IDLE, "youtube live disabled")
            try:
                from .publishing.clip_automation import install_clip_automation

                install_clip_automation()
            except Exception as exc:
                logger.warning(f"OBS clip automation unavailable: {exc}")
            # VR_START_OBS=1: OBS gets the Stage ready, then starts streaming.
            from .publishing.obs_control import go_live

            session = self.ws_handler.room_session
            from .publishing.obs_control import keep_task

            from .publishing.prelive import PRELIVE

            if PRELIVE.active:
                # Title, description and opening message are written while
                # OBS and the Stage start; the thumbnail needs a Stage frame.
                import os as _os

                PRELIVE.open_session(force_new=_os.environ.get("VR_PRELIVE_NEW_SESSION") == "1")
                keep_task(asyncio.create_task(PRELIVE.prepare_text(), name="prelive-text"))
            self._go_live_task = asyncio.create_task(go_live(lambda since: session.stage_loaded(since)))
            keep_task(self._go_live_task)  # Ctrl+C during the start cancels it

        @self.app.on_event("shutdown")
        async def stop_youtube_live_service():
            if self.youtube_live_service:
                await self.youtube_live_service.stop()

        @self.app.on_event("shutdown")
        async def close_lifestyle_show():
            # The lifestyle loop treats a cancellation as an interrupted line and
            # keeps going while a Stage is connected (OBS keeps one open), so the
            # server never finished exiting. Close it first, like the DEV server.
            try:
                await self.ws_handler.room_session.lifestyle.close()
            except Exception as exc:
                logger.debug(f"Lifestyle close failed: {exc}")

    @staticmethod
    def clean_cache():
        """Clean the cache directory by removing and recreating it."""
        cache_dir = "cache"
        if os.path.exists(cache_dir):
            shutil.rmtree(cache_dir)
            os.makedirs(cache_dir)

