"""Two-stage viewer replies (Day 3). Stage 1 is the normal reply, kept short so it is heard within about 2 s.
Stage 2 is an understanding pass: a small model reads the viewer's message and that first reply and decides whether a
fuller follow-up is really needed (a real question with substance that the short reply only touched). Greetings,
compliments, simple yes/no and anything already answered get no follow-up. Returns what the follow-up should add."""

from __future__ import annotations

import json
import os
from typing import Optional

import httpx
from loguru import logger

PROMPT = """A livestream character just replied to a viewer. Decide if a short follow-up is NEEDED.
Viewer message: {viewer}
Her first reply (already spoken): {reply}
Needed only when the viewer asked a real question with substance (how / why / what does / tell me about / opinion on
something specific / a request for an explanation) and the first reply only touched it. NOT needed for greetings,
thanks, compliments, jokes, simple yes/no questions, action requests, or when the reply already answered it.
Answer JSON only: {{"needed": true|false, "add": "what the follow-up should add, in a few words (empty if not needed)"}}"""


async def decide(viewer_text: str, first_reply: str, timeout: float = 4.0,
                 client: Optional[httpx.AsyncClient] = None) -> Optional[str]:
    """What a follow-up should add, or None (not needed / model unavailable)."""
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key or os.environ.get("VR_TWO_STAGE_REPLIES", "1") == "0":
        return None
    model = os.environ.get("VR_FOLLOWUP_MODEL", "gpt-4.1-mini").strip() or "gpt-4.1-mini"
    try:
        own = client is None
        http = client or httpx.AsyncClient(timeout=timeout)
        try:
            r = await http.post("https://api.openai.com/v1/chat/completions", headers={"Authorization": f"Bearer {key}"},
                                json={"model": model, "temperature": 0, "response_format": {"type": "json_object"},
                                      "messages": [{"role": "user", "content": PROMPT.format(viewer=json.dumps(viewer_text[:500]),
                                                                                             reply=json.dumps(first_reply[:500]))}]},
                                timeout=timeout)
        finally:
            if own:
                await http.aclose()
        if r.status_code >= 400:
            return None
        data = json.loads(r.json()["choices"][0]["message"]["content"])
        if data.get("needed") and str(data.get("add") or "").strip():
            return str(data["add"]).strip()[:200]
        return None
    except Exception as exc:
        logger.debug(f"Two-stage reply: follow-up decision skipped ({type(exc).__name__})")
        return None
