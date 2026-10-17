"""Local control of the pre-live barrier (mika-live.sh uses these).

    GET  /prelive/status   readiness, prepared metadata, what is missing
    POST /prelive/go       the deliberate go-live confirmation (only when ready)
    POST /prelive/retry    run the failed preparation steps again

Only requests from this machine are accepted.
"""

from __future__ import annotations

import asyncio
import json
import time
import urllib.request

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from .prelive import PRELIVE

_kokoro = {"at": 0.0, "ok": False}


def _local(request: Request) -> bool:
    return (request.client.host if request.client else "") in ("127.0.0.1", "::1", "localhost")


def kokoro_ready() -> bool:
    """Mika's Kokoro service answers (checked at most every 5 s)."""
    if time.time() - _kokoro["at"] < 5:
        return _kokoro["ok"]
    try:
        with urllib.request.urlopen("http://127.0.0.1:12460/health", timeout=0.8) as r:
            _kokoro["ok"] = bool(json.loads(r.read()).get("ready"))
    except Exception:
        _kokoro["ok"] = False
    _kokoro["at"] = time.time()
    return _kokoro["ok"]


def stage_checks(session) -> dict[str, bool]:
    return {
        "stage_loaded_in_obs": bool(session.stage_loaded()),
        "mika_world_ready": session.lifestyle.leader() is not None,
        "llm_ready": bool(session.director.ready),
        "kokoro_voice_ready": kokoro_ready(),
    }


def init_prelive_routes(ws_handler) -> APIRouter:
    router = APIRouter()
    PRELIVE.stage_check = lambda: stage_checks(ws_handler.room_session)

    @router.get("/prelive/status")
    async def status(request: Request):
        if not _local(request):
            return JSONResponse({"error": "local only"}, status_code=403)
        return JSONResponse({"active": PRELIVE.active, **(PRELIVE.status() if PRELIVE.session else {})})

    @router.post("/prelive/go")
    async def go(request: Request):
        if not _local(request):
            return JSONResponse({"error": "local only"}, status_code=403)
        return JSONResponse(PRELIVE.confirm())

    @router.post("/prelive/retry")
    async def retry(request: Request):
        if not _local(request):
            return JSONResponse({"error": "local only"}, status_code=403)
        from . import obs_control

        asyncio.create_task(PRELIVE.prepare(obs_control.stage_frame))
        return JSONResponse({"ok": True, "retrying": True})

    return router
