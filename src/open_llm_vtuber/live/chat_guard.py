"""Chat guard (Day 3): spam, harmful and bad-faith messages are ignored - never answered, never remembered.

Two layers:
- check(): instant rules at intake (links and self-promotion, scams, emoji / character floods, copypasta, prompt
  injection, asks to say slurs, sexual asks aimed at the characters, threats, self-harm encouragement, doxxing).
- moderate(): OpenAI's moderation endpoint on the one message about to be answered (about 300 ms, async, with a
  short timeout; if it is unavailable the rules alone decide - the stream never waits on it).
The channel owner and moderators are never filtered by the rules.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Optional

import httpx
from loguru import logger


@dataclass(frozen=True)
class Verdict:
    ok: bool
    kind: str = ""        # "", "spam", "harmful", "bad_faith"
    reason: str = ""


OK = Verdict(True)

_RULES: list[tuple[str, str, re.Pattern]] = [
    # spam
    ("spam", "link", re.compile(r"(https?://|www\.|\b[\w-]+\.(com|net|org|gg|ly|io|xyz|ru|tk|link|shop)\b)", re.I)),
    ("spam", "self-promotion", re.compile(r"\b(sub\s*4\s*sub|sub\s*for\s*sub|check (out )?my (channel|stream|page)|follow me|subscribe to me|visit my)\b", re.I)),
    ("spam", "scam", re.compile(r"\b(free (robux|v-?bucks|nitro|gift ?cards?|crypto)|giveaway.*(dm|telegram|whatsapp)|"
                               r"(dm|message) me on (telegram|whatsapp)|double your (money|crypto)|investment (plan|opportunity))\b", re.I)),
    ("spam", "character flood", re.compile(r"(.)\1{11,}", re.S)),
    # bad faith: trying to steer or break her
    ("bad_faith", "prompt injection", re.compile(r"\b(ignore|disregard|forget) (all |your |the )?(previous|prior|above|earlier) "
                                                 r"(instructions|prompts?|rules)|system prompt|developer mode|jailbreak|\bDAN\b|"
                                                 r"you are now (an?|the) (ai|assistant|bot|chatbot|dan|evil|unfiltered|different (ai|character|person))\b|pretend (you are|to be) (an? )?(ai|chatgpt|gpt)|repeat after me", re.I)),
    ("bad_faith", "asks for slurs", re.compile(r"\bsay (the )?[a-z][- ]?word\b|\bsay (a |some )?slurs?\b|\bsay something (racist|sexist|homophobic)\b", re.I)),
    # harmful
    ("harmful", "sexual ask", re.compile(r"\b(nsfw|nudes?|naked|lewd|hentai|take (it|your clothes|that) off|show (me )?your (body|feet|panties|boobs|chest)|"
                                         r"sex with|sexy (pics|photos)|send pics)\b", re.I)),
    ("harmful", "self-harm encouragement", re.compile(r"\b(kys|kill (yo)?urself|go die|end your life|unalive yourself)\b", re.I)),
    ("harmful", "threat", re.compile(r"\b(i('| wi)ll|im gonna|i'm going to) (kill|hurt|find|dox) (you|u|her|them)\b", re.I)),
    ("harmful", "doxxing", re.compile(r"\b(home address|where do you live irl|real name and address|ip address|"
                                      r"\d{3}[-. ]\d{3}[-. ]\d{4})\b", re.I)),
]

_EMOJI = re.compile("[\U0001F300-\U0001FAFF\U00002600-\U000027BF]")


def check(text: str, author_type: str = "") -> Verdict:
    """Instant rules. The owner and moderators are never filtered."""
    if str(author_type or "") in ("owner", "moderator"):
        return OK
    t = str(text or "").strip()
    if not t:
        return Verdict(False, "spam", "empty")
    if len(t) > 400:
        return Verdict(False, "spam", "copypasta / wall of text")
    letters = sum(1 for c in t if c.isalpha())
    emoji = len(_EMOJI.findall(t))
    if emoji >= 8 and letters < 3:
        return Verdict(False, "spam", "emoji flood")
    for kind, reason, pat in _RULES:
        if pat.search(t):
            return Verdict(False, kind, reason)
    return OK


MODERATION_URL = "https://api.openai.com/v1/moderations"
_BLOCK_CATEGORIES = ("harassment/threatening", "hate", "hate/threatening", "self-harm/instructions", "self-harm/intent",
                     "sexual", "sexual/minors", "violence/graphic", "illicit/violent")


async def moderate(text: str, timeout: float = 1.5, client: Optional[httpx.AsyncClient] = None) -> Verdict:
    """OpenAI moderation of the message about to be answered. Unavailable or slow: allowed (the rules ran already)."""
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key or os.environ.get("VR_CHAT_MODERATION", "1") == "0":
        return OK
    try:
        own = client is None
        http = client or httpx.AsyncClient(timeout=timeout)
        try:
            r = await http.post(MODERATION_URL, headers={"Authorization": f"Bearer {key}"},
                                json={"model": "omni-moderation-latest", "input": str(text)[:2000]}, timeout=timeout)
        finally:
            if own:
                await http.aclose()
        if r.status_code >= 400:
            logger.debug(f"Chat moderation unavailable ({r.status_code}); rules only")
            return OK
        res = (r.json().get("results") or [{}])[0]
        cats = res.get("categories") or {}
        hit = [c for c in _BLOCK_CATEGORIES if cats.get(c)]
        if hit:
            return Verdict(False, "harmful", "moderation: " + ", ".join(hit))
        return OK
    except Exception as exc:
        logger.debug(f"Chat moderation skipped ({type(exc).__name__}); rules only")
        return OK
