"""Pre-live preparation and the publishing barrier for Mika's world stream.

Order (mika-live.sh, VR_MODE=world, VR_PRELIVE=1):
  1. a stream session is opened or resumed (a restart never regenerates)
  2. title, description and the opening chat message are written from real
     context (New York time of day, what Mika can actually do, debut or not)
     and validated: no em dashes, no invented links, YouTube limits
  3. the Stage loads in OBS (not streaming); a real frame of it is the
     reference for the thumbnail
  4. thumbnail: GPT Image 2 (at most once per session, daily cap, quota
     errors stop paid retries) -> last approved generated thumbnail ->
     the permanent default; the text on it is drawn locally
  5. the channel is verified, and title, description and thumbnail are put
     on THE broadcast bound to our stream key (made if there is none)
  6. READY. OBS starts streaming only after the go-live confirmation
     (POST /prelive/go, which mika-live.sh asks for) unless
     VR_AUTO_GO_LIVE=1. YouTube's Go live is the existing obs_control flow.
  7. once YouTube says the broadcast is live: metadata re-checked on the
     broadcast that is really live, the opening message is posted once.

    VR_PRELIVE=1                 turn this on (world mode)
    VR_PRELIVE_DRY_RUN=1         prepare everything, write nothing to YouTube
    VR_AUTO_GO_LIVE=1            no confirmation (unattended restarts)
    VR_THUMBNAIL_GENERATE=0      never call the paid image API
    VR_THUMBNAIL_MAX_PER_DAY=2   paid image attempts per day
    VR_THUMBNAIL_QUALITY=medium  low | medium | high
    VR_PRELIVE_TEXT_MODEL        default gpt-4.1-mini
    VR_STREAM_THEME              optional theme for this stream
    VR_STREAM_KIND               auto | debut | regular | special

Records (data/prelive/): session.json (prepared, applied, chat, failures),
history.json (finished streams), image_budget.json, thumbnails/ (approved
generated art, cached without text).
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import io
import json
import os
import re
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Awaitable, Callable, Optional

import httpx
from loguru import logger

DATA = Path("data") / "prelive"
SESSION_FILE = DATA / "session.json"
HISTORY_FILE = DATA / "history.json"
BUDGET_FILE = DATA / "image_budget.json"
THUMB_CACHE = DATA / "thumbnails"
DEFAULT_THUMBNAIL = Path("assets") / "thumbnails" / "mika-world-default.jpg"
SESSION_MAX_AGE = 6 * 3600  # a restart within this resumes the same stream session
OPENAI = "https://api.openai.com/v1"
IMAGE_MODEL = "gpt-image-2"
THUMB_SIZE = (1280, 720)
THUMB_MAX_BYTES = 2_000_000  # YouTube's limit is 2 MB

# What Mika can really do in the world (autonomy goals with working
# capabilities). Book reading and flower picking are paused for quality.
ACTIVITIES = {
    "fresh_air": "walking out into her garden",
    "stargaze": "watching the night sky from the garden",
    "lantern_walk": "walking to the lantern pavilion by the koi pond",
    "garden_jog": "jogging around the garden loop",
    "explore": "exploring corners of her garden",
    "atelier": "visiting her glass art studio",
    "relax": "relaxing in her reading chair",
    "dance_practice": "practising dance routines in her dance studio",
    "rhythm_challenge": "playing the NEON PULSE rhythm game in her arcade room",
    "room_tour": "showing viewers around her room",
    "window": "looking out of her window",
}
# The Godot mage world (VR_WORLD_RENDERER=godot): what she and Luna really do there.
ACTIVITIES_GODOT = {
    "study": "studying spellbooks and inscriptions in the Arcane Sanctuary and its library",
    "magic": "practising her spells at the ritual circle",
    "explore": "exploring the forests, ruins and caverns around the sanctuary on foot",
    "expedition": "following old clues on expeditions across the regions with Luna",
    "dance": "dancing with Luna",
    "rest": "resting and meditating between adventures",
    "gather": "gathering herbs and crystals",
}
FIXED_ABOUT_GODOT = (
    "Mika is an autonomous AI VTuber, a young mage living in her own fantasy world with her "
    "friend Luna. Nobody steers them: they pick their own goals, study magic, explore on foot "
    "and grow from Level 1, and talk with chat while they go. Mika's voice is generated locally."
)
FIXED_ABOUT = (
    "Mika is an autonomous AI VTuber living in her own 3D world. Nobody steers her: she "
    "picks her own goals, walks between her room, garden, dance studio and arcade, and "
    "talks with chat while she goes. Her voice is generated locally and her world follows "
    "real New York time, with the real sun, moon and stars."
)
CHAT_HOWTO = (
    "Say hi in live chat! Mika reads along and picks a few messages at a time to answer "
    "while she keeps living her day, so she may not reply to every message."
)
# Links already published by this channel (stream_autopilot.STREAM_BODY).
LINKS = (
    "🔴 Live: https://www.youtube.com/@SelwynBuilds-j1s/live\n"
    "💻 GitHub: https://github.com/RandomSci/VR-Agent\n"
    "📚 Free AI automation course: https://whop.com/selwyn-builds/exp_rc0jGvlp9zbLvh/app/\n"
    "📬 selwyn@selwynbuilds.com"
)
CREDITS = (
    "Credits: voice Kokoro-82M (Apache-2.0). Animations by Quaternius (CC0). "
    "Background music generated with ElevenLabs Music."
)
DASHES = "—–―‒⸺⸻"  # em, en, horizontal bar, figure, two/three-em
TIME_WORDS = re.compile(
    r"\b(today|tonight|tomorrow|morning|afternoon|evening|debut|first|special|premiere|"
    r"monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d)\b",
    re.I,
)


# ---------------------------------------------------------------- helpers
def _flag(name: str, default: str = "0") -> bool:
    return os.environ.get(name, default).strip().lower() in ("1", "true", "yes", "on")


def _now() -> float:
    return time.time()


def _iso(ts: Optional[float] = None) -> str:
    return datetime.fromtimestamp(ts or _now(), timezone.utc).isoformat(timespec="seconds")


def _read(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def _write(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False))
    tmp.replace(path)


def clean_public_text(text: str) -> str:
    """No em/en dashes anywhere in public text; tidy spacing."""
    text = str(text or "")
    text = re.sub(rf"\s*[{DASHES}]\s*", ", ", text)
    text = re.sub(r"\s+--\s+", ", ", text)
    text = re.sub(r",\s*,", ",", text)
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip(" ,")


def has_dash(text: str) -> bool:
    return any(ch in str(text) for ch in DASHES)


def validate_metadata(meta: dict[str, str]) -> list[str]:
    """Problems that block publishing (empty list = valid)."""
    problems = []
    title, desc, chat, thumb = (meta.get(k, "") for k in ("title", "description", "opening_comment", "thumbnail_text"))
    for name, value in (("title", title), ("description", desc), ("opening_comment", chat), ("thumbnail_text", thumb)):
        if has_dash(value):
            problems.append(f"{name} contains an em/en dash")
        if "<" in value or ">" in value:
            problems.append(f"{name} contains < or > (YouTube rejects them)")
    if not 10 <= len(title) <= 100:
        problems.append("title must be 10-100 characters")
    if not 200 <= len(desc.encode()) <= 4900:
        problems.append("description must be 200-4900 bytes")
    if not 10 <= len(chat) <= 200:
        problems.append("opening comment must be 10-200 characters")
    if re.search(r"https?://|www\.|@\w", title + " " + chat + " " + meta.get("intro", "")):
        problems.append("generated text contains a link or @handle")
    if not thumb or len(thumb) > 32 or TIME_WORDS.search(thumb) or not re.fullmatch(r"[A-Za-z' !?]+", thumb):
        problems.append("thumbnail text must be 1-32 letters, timeless (no dates, numbers or event words)")
    return problems


# ---------------------------------------------------------------- context
def _godot_world() -> bool:
    return True          # the stream is the Godot world


def stream_context(history: list[dict]) -> dict[str, Any]:
    from ..room.world_calendar import WorldCalendar

    snap = WorldCalendar().snapshot()
    kind = os.environ.get("VR_STREAM_KIND", "auto").strip().lower() or "auto"
    if kind == "auto":
        kind = "debut" if not history else "regular"
    routine = (snap.get("weeklyRoutine") or {}).get("actionWeights") or {}
    favoured = [a for a, w in sorted(routine.items(), key=lambda kv: -kv[1]) if w > 1]
    # Routine weights name semantic actions; the matching goals (activities):
    action_goal = {"dance": "dance_practice", "dance_challenge": "rhythm_challenge", "visit_gardens": "fresh_air",
                   "go_jogging": "garden_jog", "visit_atelier": "atelier", "visit_lantern_retreat": "lantern_walk",
                   "explore": "explore", "sit_chair": "relax", "tour_room": "room_tour", "show_window": "window"}
    preferred = [action_goal.get(a, a) for a in favoured]
    night = snap.get("sky") in ("NIGHT", "DUSK") or snap.get("dayPart") in ("NIGHT", "LATE_NIGHT", "EVENING")
    available = {k: v for k, v in ACTIVITIES.items() if not (k == "stargaze" and not night)}
    if _godot_world():
        available = dict(ACTIVITIES_GODOT)
        preferred = []
    return {
        "stream_kind": kind,
        "stream_number": len(history) + 1,
        "new_york_time": snap.get("localTime"),
        "weekday": snap.get("weekdayName"),
        "day_part": snap.get("dayPart"),
        "sky": snap.get("sky"),
        "things_mika_can_really_do": list(available.values()),
        "this_weekday_she_prefers": [ACTIVITIES[g] for g in preferred if g in ACTIVITIES],
        "theme": os.environ.get("VR_STREAM_THEME", "").strip(),
        "recent_titles": [h.get("title", "") for h in history[-6:]],
    }


# The channel's opening live chat message, in the creator's voice (not Mika
# promoting herself). Fixed and reviewed, not generated: YouTube live chat
# allows 200 characters and this is exactly 200. Posted once per live
# broadcast, never in a rehearsal or dry run. No dashes.
OPENING_COMMENT = (
    "Welcome! Mika is my experimental AI. She explores, learns magic, builds skills, "
    "remembers and makes her own choices in a persistent 3D world. Still evolving! "
    "Subscribe to Selwyn Builds to follow along"
)

# ---- the Godot world's broadcast (launch 2026-10-17): fixed title, the character invite, a fixed description
# Title: "Day N | " is put in front when it is applied (launch_days.title_with_day). VR_STREAM_TITLE overrides.
WORLD_TITLE = os.environ.get("VR_STREAM_TITLE", "").strip() or "Two AI Mages Living Their Own Lives in a Fantasy World 🌙"
# The creator's invite, word for word (the pinned message). Live chat takes at most 200 characters and the API
# cannot pin, so the full text opens the description and CHARACTER_INVITE_CHAT (<= 200) is posted in chat.
CHARACTER_INVITE = (
    "🌙✨ Want YOUR original character to live in Mika and Luna's world?\n\n"
    "Mika and Luna are autonomous AI mages living their own adventures in a 3D fantasy world. "
    "Soon the community will help shape this world 🎨\n\n"
    "Drop your dream character in the comments. Name, look, personality, magic and backstory.\n\n"
    "Some characters may join the world as wandering mages with their own AI personality, memory and adventures 🪄\n\n"
    "🔔 Subscribe so you don't miss the day the first community character arrives!\n\n"
    "Experimental project, not every character can be added. Original characters only."
)
CHARACTER_INVITE_CHAT = (
    "🌙✨ Want YOUR original character in Mika and Luna's world? Drop name, look, personality, magic and "
    "backstory in chat. Some may join as wandering mages 🪄 Original characters only!"
)
COMMUNITY_LINK = os.environ.get("VR_COMMUNITY_LINK", "").strip() or "[community link coming soon]"
WORLD_DESCRIPTION = (
    "Mika and Luna are two autonomous AI mages living their own adventures in a 3D fantasy world. Nobody "
    "steers them: they choose where to go, study magic, explore, talk with each other and with chat, and "
    "remember what happened.\n\n"
    + CHARACTER_INVITE + "\n\n"
    "How to submit a character:\n"
    "• Original characters only (no copyrighted or existing characters)\n"
    "• By submitting, you allow us to adapt your character and show it on stream\n"
    "• Keep it appropriate for all audiences\n"
    "• No personal information (real names, addresses, contact details)\n"
    "• Not every character can be added\n\n"
    "Community: " + COMMUNITY_LINK + "\n\n"
    "AI generated content: Mika, Luna, their voices, dialogue and decisions are generated by AI in real time. "
    "Nothing they say is scripted.\n\n"
)


TEXT_PROMPT = """You write YouTube livestream metadata for Mika, an autonomous AI VTuber.
Facts (use ONLY these, never invent features, guests, events, links or achievements):
{facts}

Write JSON with keys:
  "title": natural, engaging, 45-90 characters, mentions she is an AI VTuber or autonomous,
           reflects the time of day and 1-2 things from things_mika_can_really_do, may use one emoji,
           different from recent_titles. If stream_kind is "debut", it is the first stream of her NEW 3D WORLD (not her first stream ever; she has streamed before): say "first stream in my new 3D world" or similar, never "first stream" alone.
  "intro": 2-3 warm sentences for the top of the description about this stream (what she might do
           now, the mood of the time of day). Present tense, no promises of specific events.
  "expect": 2-3 short lines (no bullets symbols) of what viewers can expect, only from the facts.
  "opening_comment": one short friendly live chat message (max 150 characters) posted by the
           channel when the stream starts: welcome viewers, mention Mika or what she is up to,
           invite them to say hi. Not salesy, at most one emoji.
  "thumbnail_text": 1-3 timeless words for the thumbnail (no dates, numbers, days, time of day,
           "debut" or "first"), e.g. "MIKA'S WORLD" or "COME SAY HI".
Rules: plain words, no hashtags, no URLs, no @handles, never use dashes like the em dash or en dash."""


async def write_metadata(context: dict[str, Any]) -> tuple[dict[str, str], str]:
    """(metadata, source). Source is the model name, or 'template' if the model failed."""
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    model = os.environ.get("VR_PRELIVE_TEXT_MODEL", "gpt-4.1-mini").strip() or "gpt-4.1-mini"
    error = "no OPENAI_API_KEY"
    if key:
        for attempt in range(2):
            try:
                async with httpx.AsyncClient(timeout=45) as http:
                    r = await http.post(
                        f"{OPENAI}/chat/completions",
                        headers={"Authorization": f"Bearer {key}"},
                        json={
                            "model": model,
                            "temperature": 0.9,
                            "response_format": {"type": "json_object"},
                            "messages": [{"role": "user", "content": TEXT_PROMPT.format(facts=json.dumps(context, indent=1))}],
                        },
                    )
                if r.status_code >= 400:
                    error = f"{model} {r.status_code}: {r.text[:160]}"
                    continue
                raw = json.loads(r.json()["choices"][0]["message"]["content"])
                meta = compose_metadata(raw, context)
                problems = validate_metadata(meta)
                if not problems:
                    return meta, model
                error = "; ".join(problems)
                logger.warning(f"Pre-live: generated metadata rejected ({error}), trying again")
            except Exception as exc:
                error = f"{type(exc).__name__}: {str(exc)[:160]}"
    logger.warning(f"Pre-live: text model unavailable ({error}); using the accurate template")
    meta = compose_metadata(template_text(context), context)
    return meta, "template"


def template_text(ctx: dict[str, Any]) -> dict[str, str]:
    part = str(ctx.get("day_part") or "").replace("_", " ").lower() or "day"
    doing = (ctx.get("this_weekday_she_prefers") or ctx["things_mika_can_really_do"])[:2]
    debut = ctx.get("stream_kind") == "debut"
    title = (
        "Mika's New 3D World Is Live! An Autonomous AI VTuber Moves In"
        if debut
        else f"AI VTuber Mika's {part.title()} in Her 3D World: {doing[0].split(' in ')[0].capitalize()}"
    )
    return {
        "title": title,
        "intro": f"It's {part} in New York and Mika is going about her day. She might be "
        + " or ".join(doing)
        + ", whatever she feels like next.",
        "expect": "Mika choosing what to do on her own\nChat with her while she explores\nA calm world with real day and night",
        "opening_comment": "Welcome in! Mika is just getting started in her world. Say hi in chat, she reads along 💛",
        "thumbnail_text": "MIKA'S WORLD",
    }


def compose_metadata(raw: dict[str, Any], ctx: dict[str, Any]) -> dict[str, str]:
    g = {k: clean_public_text(raw.get(k, "")) for k in ("title", "intro", "expect", "opening_comment", "thumbnail_text")}
    title = " ".join(g["title"].replace("#", "").split())[:100]
    expect = "\n".join("• " + line.strip(" •-*") for line in str(raw.get("expect", "")).splitlines() if line.strip(" •-*"))
    expect = clean_public_text(expect).replace(", •", "\n•")
    description = "\n\n".join(
        part
        for part in (
            g["intro"],
            ("What to expect:\n" + expect) if expect else "",
            CHAT_HOWTO,
            FIXED_ABOUT_GODOT if _godot_world() else FIXED_ABOUT,
            LINKS,
            CREDITS,
        )
        if part
    )
    if _godot_world():
        title = WORLD_TITLE
        description = WORLD_DESCRIPTION + LINKS + "\n\n" + CREDITS
        # a fresh line for every broadcast (never a reused description): what really happened last time, after the
        # opening paragraph (VR_STREAM_RECAP, written from the last broadcast's events)
        recap = os.environ.get("VR_STREAM_RECAP", "").strip()
        if recap:
            head, _, rest = description.partition("\n\n")
            description = head + "\n\n" + recap + "\n\n" + rest
        return {"title": title, "intro": g["intro"], "description": description, "opening_comment": CHARACTER_INVITE_CHAT,
                "thumbnail_text": "AI MAGES LIVING THEIR OWN LIVES"}
    return {
        "title": title,
        "intro": g["intro"],
        "description": clean_public_text(description) if has_dash(description) else description,
        "opening_comment": OPENING_COMMENT,
        "thumbnail_text": " ".join(g["thumbnail_text"].upper().split())[:22],
    }


# ---------------------------------------------------------------- thumbnail

def _current_failure(session: dict[str, Any]) -> Optional[dict[str, Any]]:
    """The newest failure that is still current: one followed by a successful
    run of the same step (an old invalid_grant after re-authorizing) is history,
    kept in "failures" but no longer shown as the problem."""
    steps = session.get("steps") or {}
    for failure in reversed(session.get("failures") or []):
        done = steps.get(failure.get("step")) or {}
        if done.get("ok") and str(done.get("at", "")) > str(failure.get("at", "")):
            continue
        return failure
    return None

class ImageQuotaError(RuntimeError):
    pass


def _font(size: int):
    from PIL import ImageFont

    for path in (
        "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf",
        "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ):
        if Path(path).is_file():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def render_thumbnail(art: bytes, text: str) -> bytes:
    """1280x720 JPEG: the art (cover-cropped to 16:9) with readable text and a
    LIVE badge drawn locally (no model-drawn letters, no spelling mistakes)."""
    from PIL import Image, ImageDraw, ImageFilter

    img = Image.open(io.BytesIO(art)).convert("RGB")
    w, h = img.size
    target = THUMB_SIZE[0] / THUMB_SIZE[1]
    if w / h > target:
        nw = int(h * target)
        img = img.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = int(w / target)
        img = img.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    img = img.resize(THUMB_SIZE, Image.LANCZOS)
    # Soft dark band on the left so the words read at any size.
    shade = Image.new("L", THUMB_SIZE, 0)
    ImageDraw.Draw(shade).rectangle((0, 0, 560, 720), fill=150)
    shade = shade.filter(ImageFilter.GaussianBlur(120))
    img = Image.composite(Image.new("RGB", THUMB_SIZE, (10, 12, 24)), img, shade)
    draw = ImageDraw.Draw(img)
    words = [w for w in clean_public_text(text).upper().split() if w][:6] or ["MIKA'S", "WORLD"]
    lines, current = [], ""
    for word in words:
        if len(current) + len(word) + 1 > 11 and current:
            lines.append(current)
            current = word
        else:
            current = (current + " " + word).strip()
    lines.append(current)
    size = 118 if max(len(line) for line in lines) <= 8 else 96
    font = _font(size)
    y = 360 - (len(lines) * (size + 12)) // 2 + 30
    for line in lines:
        draw.text((64, y), line, font=font, fill=(255, 255, 255), stroke_width=7, stroke_fill=(20, 16, 40))
        y += size + 12
    badge = _font(46)
    draw.rounded_rectangle((64, 56, 236, 128), radius=14, fill=(230, 33, 52))
    draw.text((92, 63), "LIVE", font=badge, fill=(255, 255, 255))
    out = io.BytesIO()
    quality = 90
    while True:
        out.seek(0)
        out.truncate()
        img.save(out, "JPEG", quality=quality, optimize=True, progressive=True)
        if out.tell() <= THUMB_MAX_BYTES or quality <= 60:
            break
        quality -= 8
    return out.getvalue()


def validate_thumbnail(data: bytes) -> list[str]:
    from PIL import Image

    problems = []
    if not data:
        return ["no thumbnail data"]
    if len(data) > THUMB_MAX_BYTES:
        problems.append("thumbnail over 2 MB")
    try:
        img = Image.open(io.BytesIO(data))
        img.verify()
        img = Image.open(io.BytesIO(data))
        if img.format not in ("JPEG", "PNG"):
            problems.append(f"thumbnail format {img.format} (need JPEG or PNG)")
        if img.size[0] < 640 or abs(img.size[0] / img.size[1] - 16 / 9) > 0.02:
            problems.append(f"thumbnail is {img.size}, need 16:9 and at least 640 wide")
    except Exception as exc:
        problems.append(f"thumbnail unreadable: {exc}")
    return problems


def _budget() -> dict[str, Any]:
    return _read(BUDGET_FILE, {"attempts": [], "blocked_until": 0, "reason": ""})


def image_generation_allowed() -> tuple[bool, str]:
    if not _flag("VR_THUMBNAIL_GENERATE", "1"):
        return False, "disabled (VR_THUMBNAIL_GENERATE=0)"
    if not os.environ.get("OPENAI_API_KEY", "").strip():
        return False, "no OPENAI_API_KEY"
    b = _budget()
    if b.get("blocked_until", 0) > _now():
        return False, f"paused after a quota/credit error until {_iso(b['blocked_until'])} ({b.get('reason', '')})"
    cap = int(os.environ.get("VR_THUMBNAIL_MAX_PER_DAY", "2") or 2)
    recent = [t for t in b.get("attempts", []) if _now() - t < 86400]
    if len(recent) >= cap:
        return False, f"daily cap reached ({cap} paid attempts in 24 h)"
    return True, ""


async def generate_art(reference_jpeg: bytes, context: dict[str, Any]) -> bytes:
    """One GPT Image 2 edit of a real Stage frame. Raises ImageQuotaError on
    quota/credit errors (no further paid attempts are made)."""
    b = _budget()
    b.setdefault("attempts", []).append(_now())
    b["attempts"] = [t for t in b["attempts"] if _now() - t < 7 * 86400]
    _write(BUDGET_FILE, b)
    where = ", ".join(context.get("things_mika_can_really_do", [])[:3])
    prompt = (
        "Turn this real screenshot of Mika, an anime-style AI VTuber, into a polished, eye-catching "
        "YouTube livestream thumbnail. Keep Mika's exact look from the screenshot: her face, silver-white "
        "hair, animal ears, eye colour and outfit must stay recognisably the same character. Show her large "
        "on the right half, expressive and friendly, in her own 3D world "
        f"({str(context.get('day_part', '')).lower().replace('_', ' ')} light; she spends her time {where}). "
        "Cinematic lighting, rich but natural colours, crisp detail, depth of field. Keep the left 40% of "
        "the image calmer and slightly darker for a title. Do not draw any text, letters, numbers, logos, "
        "watermarks or user interface. Do not add other characters or game elements that are not in the scene."
    )
    files = {"image[]": ("stage.jpg", reference_jpeg, "image/jpeg")}
    data = {
        "model": IMAGE_MODEL,
        "prompt": prompt,
        "size": "1536x1024",
        "quality": os.environ.get("VR_THUMBNAIL_QUALITY", "medium").strip() or "medium",
        "n": "1",
    }
    async with httpx.AsyncClient(timeout=240) as http:
        r = await http.post(
            f"{OPENAI}/images/edits",
            headers={"Authorization": f"Bearer {os.environ.get('OPENAI_API_KEY', '').strip()}"},
            data=data,
            files=files,
        )
    if r.status_code >= 400:
        text = r.text[:400]
        code = ""
        try:
            code = str((r.json().get("error") or {}).get("code") or "")
        except Exception:
            pass
        if r.status_code in (402, 429) or code in ("insufficient_quota", "billing_hard_limit_reached") or "billing" in text.lower() or "quota" in text.lower():
            b = _budget()
            b["blocked_until"] = _now() + 86400
            b["reason"] = f"{r.status_code} {code or 'quota'}"
            _write(BUDGET_FILE, b)
            raise ImageQuotaError(f"{IMAGE_MODEL} quota/credits: {r.status_code} {code}")
        raise RuntimeError(f"{IMAGE_MODEL} refused ({r.status_code}): {text}")
    item = (r.json().get("data") or [{}])[0]
    if item.get("b64_json"):
        return base64.b64decode(item["b64_json"])
    if item.get("url"):
        async with httpx.AsyncClient(timeout=60) as http:
            return (await http.get(item["url"])).content
    raise RuntimeError(f"{IMAGE_MODEL} returned no image")


def cached_art() -> Optional[tuple[Path, dict]]:
    """The newest approved generated art (no text on it), if any."""
    best = None
    for meta_path in sorted(THUMB_CACHE.glob("*.json")):
        meta = _read(meta_path, {})
        art = meta_path.with_suffix(".png")
        if meta.get("approved") and art.is_file():
            best = (art, meta)
    return best


def cache_art(art: bytes, context: dict[str, Any]) -> Path:
    THUMB_CACHE.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    path = THUMB_CACHE / f"{stamp}.png"
    from PIL import Image

    Image.open(io.BytesIO(art)).save(path, "PNG")
    # Approved for reuse: the art carries no text, dates or event claims.
    _write(path.with_suffix(".json"), {"model": IMAGE_MODEL, "created": _iso(), "approved": True,
                                       "day_part": context.get("day_part"), "has_text": False})
    return path


def stream_channel_id() -> str:
    """The channel this show streams on and reads chat from: VR_STREAM_CHANNEL_ID,
    else conf.yaml live_config.youtube_live.channel_id. Every YouTube write
    is refused unless the signed-in account is exactly this channel."""
    explicit = os.environ.get("VR_STREAM_CHANNEL_ID", "").strip()
    if explicit:
        return explicit
    try:
        import yaml
        conf = yaml.safe_load(Path("conf.yaml").read_text(encoding="utf-8")) or {}
        return str(((conf.get("live_config") or {}).get("youtube_live") or {}).get("channel_id") or "").strip()
    except Exception:
        return ""


# ---------------------------------------------------------------- the coordinator
class PreLive:
    def __init__(self) -> None:
        self.session: dict[str, Any] = {}
        self.go_event = asyncio.Event()
        self.prepared_event = asyncio.Event()
        self.lock = asyncio.Lock()
        self.youtube_factory: Optional[Callable[[], Any]] = None
        self.stage_check: Callable[[], dict[str, bool]] = lambda: {}
        self.task: Optional[asyncio.Task] = None

    # ---- state
    @property
    def active(self) -> bool:
        return _flag("VR_PRELIVE")

    @property
    def dry_run(self) -> bool:
        return _flag("VR_PRELIVE_DRY_RUN") or _flag("PUBLISHING_DRY_RUN") or _flag("VR_REHEARSAL")

    @property
    def session_file(self) -> Path:
        # A rehearsal never shares the real session (its dry-run steps would
        # otherwise count as done for the real stream).
        # a test stream (mika-live.sh --test-stream: unlisted) never touches the show's session either
        if _flag("VR_TEST_STREAM"):
            return DATA / "test-session.json"
        return DATA / "rehearsal-session.json" if self.rehearsal else SESSION_FILE

    def _save(self) -> None:
        _write(self.session_file, self.session)

    def _step(self, name: str, ok: bool, **info: Any) -> None:
        self.session.setdefault("steps", {})[name] = {"ok": ok, "at": _iso(), **info}
        if not ok:
            self.session.setdefault("failures", []).append({"step": name, "at": _iso(), **info})
            self.session["failures"] = self.session["failures"][-30:]
        self._save()

    def open_session(self, force_new: bool = False) -> dict[str, Any]:
        old = _read(self.session_file, {})
        fresh = (
            old
            and not force_new
            and old.get("state") not in ("ended",)
            and _now() - float(old.get("created_ts", 0)) < SESSION_MAX_AGE
            and bool(old.get("dry_run")) == self.dry_run
        )
        if fresh:
            self.session = old
            self.session["resumed_at"] = _iso()
            logger.info(f"Pre-live: resuming stream session {old.get('id')} (nothing is regenerated)")
            chat = self.session.get("chat") or {}
            prepared = self.session.get("prepared")
            opening = CHARACTER_INVITE_CHAT if _godot_world() else OPENING_COMMENT
            if isinstance(prepared, dict) and chat.get("state") != "posted" and prepared.get("opening_comment") != opening:
                # Not posted yet: a session prepared before the fixed comment gets it now (the Godot world's is the
                # character invite; the old welcome line would otherwise replace it on a resumed session).
                prepared["opening_comment"] = opening
        else:
            if old and old.get("state") != "ended":
                old["state"] = "abandoned"
                _write(DATA / f"session-{old.get('id', 'old')}.json", old)
            self.session = {"id": uuid.uuid4().hex[:10], "created_ts": _now(), "created": _iso(), "state": "preparing", "steps": {}}
            logger.info(f"Pre-live: new stream session {self.session['id']}")
        self.session["dry_run"] = self.dry_run
        self._save()
        if self.session.get("confirmed_at") and not self.rehearsal:
            self.go_event.set()  # this session was confirmed before a restart
        self.session["rehearsal"] = self.rehearsal
        return self.session

    def status(self) -> dict[str, Any]:
        s = self.session
        stage = self.stage_check() if self.stage_check else {}
        steps = s.get("steps", {})
        need = ["metadata", "thumbnail", "youtube"]
        missing = [n for n in need if not (steps.get(n) or {}).get("ok")]
        missing += [k for k, ok in stage.items() if not ok]
        return {
            "session": s.get("id"),
            "state": s.get("state"),
            "dry_run": s.get("dry_run"),
            "rehearsal": self.rehearsal,
            "ready": not missing and bool(s.get("prepared")),
            "missing": missing,
            "services": stage,
            "confirmed": bool(s.get("confirmed_at")),
            "prepared": {k: (s.get("prepared") or {}).get(k) for k in ("title", "opening_comment", "thumbnail_text")},
            "metadata_source": (steps.get("metadata") or {}).get("source"),
            "thumbnail": {k: (s.get("thumbnail") or {}).get(k) for k in ("source", "path", "note")},
            "broadcast_id": (s.get("applied") or {}).get("broadcast_id"),
            "applied_at": (s.get("applied") or {}).get("at"),
            "live_broadcast_id": s.get("live_broadcast_id"),
            "opening_comment_posted": (s.get("chat") or {}).get("state"),
            "last_failure": _current_failure(s),
            "channel_warning": s.get("channel_warning"),
        }

    # ---- steps
    async def prepare_text(self) -> bool:
        if (self.session.get("steps", {}).get("metadata") or {}).get("ok") and self.session.get("prepared"):
            return True
        history = _read(HISTORY_FILE, [])
        ctx = stream_context(history)
        meta, source = await write_metadata(ctx)
        problems = validate_metadata(meta)
        self.session["context"] = ctx
        self.session["prepared"] = meta
        self._step("metadata", not problems, source=source, problems=problems)
        return not problems

    async def prepare_thumbnail(self, capture: Optional[Callable[[], Awaitable[bytes]]]) -> bool:
        """generated -> reused -> default. Paid generation only once per session."""
        steps = self.session.get("steps", {})
        if (steps.get("thumbnail") or {}).get("ok") and Path((self.session.get("thumbnail") or {}).get("path", "")).is_file():
            return True
        text = (self.session.get("prepared") or {}).get("thumbnail_text") or "MIKA'S WORLD"
        out = DATA / f"thumbnail-{self.session['id']}.jpg"
        note = ""
        # a finished, creator-approved thumbnail (text and DAY badge already on it): used exactly as it is
        ready = Path(os.environ.get("VR_THUMBNAIL_FILE", "").strip()) if os.environ.get("VR_THUMBNAIL_FILE", "").strip() else None
        if ready and ready.is_file() and ready.stat().st_size < THUMB_MAX_BYTES:
            data = ready.read_bytes()
            out.write_bytes(data)
            self.session["thumbnail"] = {"source": "approved file", "path": str(out), "note": f"creator-approved {ready.name}",
                                         "sha256": hashlib.sha256(data).hexdigest()}
            self._step("thumbnail", True, source="approved file")
            return True
        art: Optional[bytes] = None
        source = ""
        if not self.session.get("image_attempted"):
            allowed, why = image_generation_allowed()
            if allowed and capture is not None:
                self.session["image_attempted"] = _iso()
                self._save()
                try:
                    frame = await capture()
                    art = await generate_art(frame, self.session.get("context") or {})
                    cache_art(art, self.session.get("context") or {})
                    source, note = "generated", f"{IMAGE_MODEL} from a live Stage frame"
                except ImageQuotaError as exc:
                    note = f"GPT Image 2 unavailable: {exc}"
                except Exception as exc:
                    note = f"GPT Image 2 failed: {str(exc)[:200]}"
                if note and source != "generated":
                    logger.warning(f"Pre-live: {note}")
            else:
                note = f"GPT Image 2 not used: {why or 'no Stage frame available'}"
        else:
            note = "generation already attempted in this session (no repeat on restart)"
        if art is None:
            cached = cached_art()
            if cached:
                art, source = cached[0].read_bytes(), "reused"
                note += f"; reused approved art {cached[0].name}"
        thumb = b""
        if art is not None:
            try:
                thumb = render_thumbnail(art, text)
            except Exception as exc:
                note += f"; render failed: {exc}"
                thumb = b""
        if not thumb and DEFAULT_THUMBNAIL.is_file():
            thumb, source = DEFAULT_THUMBNAIL.read_bytes(), "default"
            note += "; permanent default thumbnail"
        problems = validate_thumbnail(thumb)
        if not problems:
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(thumb)
        self.session["thumbnail"] = {
            "source": source or "none",
            "path": str(out) if not problems else "",
            "sha256": hashlib.sha256(thumb).hexdigest() if thumb else "",
            "note": note.strip("; "),
        }
        self._step("thumbnail", not problems, source=source or "none", problems=problems)
        return not problems

    def _client(self):
        if self.youtube_factory is not None:
            return self.youtube_factory()
        from .service import PublicationService
        from .settings import PublishSettings

        return PublicationService(PublishSettings.from_env(read_dotenv=False))._youtube_factory()

    async def apply_youtube(self) -> bool:
        """Title, description and thumbnail on the broadcast bound to our key."""
        if (self.session.get("steps", {}).get("youtube") or {}).get("ok") and not self.session.get("reapply"):
            return True
        meta = self.session.get("prepared") or {}
        thumb_path = Path((self.session.get("thumbnail") or {}).get("path") or "")
        if not meta or not thumb_path.is_file():
            self._step("youtube", False, error="metadata or thumbnail missing")
            return False
        from . import obs_control

        call = asyncio.to_thread
        try:
            client = self._client()
            expected = stream_channel_id()
            mine = await call(client.my_channel_id)
            if not mine or not expected or mine != expected:
                self._step("youtube", False, error=f"signed-in channel {mine[:6]}… is not the stream channel {expected[:6] or '(none configured)'}…")
                return False
            other = os.environ.get("YOUTUBE_CHANNEL_ID", "").strip()
            if other and other != expected:
                self.session["channel_warning"] = (f".env YOUTUBE_CHANNEL_ID ({other[:6]}…) is a different channel than the stream "
                                                   f"channel ({expected[:6]}…); it is not used for publishing")
            key = await obs_control.youtube_stream_key()
            stream = await call(client.stream_for_key, key) if key else {}
            if not stream.get("id"):
                self._step("youtube", False, error="no YouTube stream found for the stream key")
                return False
            self.session["channel_id"] = mine
            bid = (self.session.get("applied") or {}).get("broadcast_id") or self.session.get("broadcast_id") or ""
            if bid and await call(client.broadcast_status, bid) in ("", "complete", "revoked"):
                bid = ""
            if not bid and not _flag("VR_TEST_STREAM"):     # a test stream always makes its own (unlisted) broadcast
                waiting = [b for b in await call(client.upcoming_broadcasts) if b["stream"] == stream["id"]]
                made = set(obs_control._made_broadcasts())
                ours = [b for b in waiting if b["id"] in made]
                bid = ours[0]["id"] if ours else ""
            if self.dry_run:
                self.session["applied"] = {"broadcast_id": bid or "(would create)", "at": _iso(), "dry_run": True,
                                           "title": meta["title"], "thumbnail_sha256": self.session["thumbnail"]["sha256"]}
                self._step("youtube", True, dry_run=True, channel_verified=True, stream_found=True)
                logger.info("Pre-live dry run: channel and stream key verified; nothing written to YouTube")
                return True
            if not bid:
                bid = await call(client.create_broadcast, meta["title"], meta["description"])
                if not bid:
                    raise RuntimeError("YouTube did not return a broadcast id")
                if not _flag("VR_TEST_STREAM"):
                    obs_control._remember_broadcast(bid)    # (a test broadcast is never reused by the show)
                await call(client.bind, bid, stream["id"])
                logger.info(f"Pre-live: broadcast {bid} created and bound to the stream key")
            self.session["broadcast_id"] = bid
            self._save()
            if _flag("VR_TEST_STREAM"):
                # read back from YouTube: a test stream never goes out unless its broadcast is really unlisted
                st = await call(lambda: client._call("GET", "/liveBroadcasts", params={"part": "status", "id": bid}))
                privacy = (((st.get("items") or [{}])[0]).get("status") or {}).get("privacyStatus", "")
                if privacy != "unlisted":
                    raise RuntimeError(f"test broadcast {bid} is '{privacy}', not unlisted: refusing to stream")
                logger.info(f"Pre-live: test broadcast {bid} confirmed unlisted")
            snippet = await call(client.get_snippet, bid)
            from . import launch_days
            title = ("[TEST] " + meta["title"])[:100] if _flag("VR_TEST_STREAM") else launch_days.title_with_day(meta["title"])
            # a broadcast made a second ago can answer 403 Forbidden to its first update (2026-10-16 test stream:
            # the same update went through moments later): tried again a few times before the step fails
            for attempt in range(4):
                try:
                    await call(client.set_title_and_description, bid, snippet, title, meta["description"])
                    break
                except Exception as exc:
                    if attempt == 3 or "403" not in str(exc):
                        raise
                    await asyncio.sleep(5 * (attempt + 1))
                    snippet = await call(client.get_snippet, bid)
            thumb_note = ""
            try:
                await call(client.set_thumbnail, bid, thumb_path.read_bytes(), "image/jpeg")
            except Exception as exc:
                thumb_note = f"thumbnail upload failed: {str(exc)[:160]}"
                raise
            obs_control.set_target_broadcast(bid)
            obs_control.set_pending_details(meta["title"], meta["description"])
            self.session["applied"] = {"broadcast_id": bid, "at": _iso(), "title": meta["title"],
                                       "description_sha256": hashlib.sha256(meta["description"].encode()).hexdigest(),
                                       "thumbnail_sha256": self.session["thumbnail"]["sha256"]}
            self.session.pop("reapply", None)
            self._step("youtube", True, broadcast_id=bid, note=thumb_note)
            logger.info(f"Pre-live: title, description and thumbnail applied to broadcast {bid}")
            return True
        except Exception as exc:
            self._step("youtube", False, error=str(exc)[:240])
            logger.warning(f"Pre-live: YouTube update failed: {exc}")
            return False

    # ---- the whole preparation and the barrier
    async def prepare(self, capture: Optional[Callable[[], Awaitable[bytes]]]) -> bool:
        async with self.lock:
            ok = await self.prepare_text()
            ok = await self.prepare_thumbnail(capture) and ok
            ok = ok and await self.apply_youtube()
            self.session["state"] = "ready" if ok else "blocked"
            self._save()
            if ok:
                self.prepared_event.set()
            return ok

    @property
    def rehearsal(self) -> bool:
        return _flag("VR_REHEARSAL")

    def confirm(self) -> dict[str, Any]:
        if self.rehearsal:
            return {"ok": False, "reason": "rehearsal: going live is disabled"}
        st = self.status()
        if not st["ready"]:
            return {"ok": False, "reason": "not ready", "missing": st["missing"]}
        self.session["confirmed_at"] = _iso()
        self._save()
        self.go_event.set()
        return {"ok": True}

    async def gate(self) -> bool:
        """Wait until prepared AND confirmed (or VR_AUTO_GO_LIVE=1). True = go."""
        if not self.active:
            return True
        while not self.status()["ready"]:
            await asyncio.sleep(1)
        if _flag("VR_AUTO_GO_LIVE") and not self.rehearsal and not self.session.get("confirmed_at"):
            self.session["confirmed_at"] = _iso() + " (auto)"
            self._save()
            self.go_event.set()
        if not self.go_event.is_set():
            logger.warning("Pre-live: READY. Waiting for the go-live confirmation (mika-live.sh asks for it)")
        await self.go_event.wait()
        self.session["state"] = "going_live"
        self._save()
        return True

    def confirmed(self) -> bool:
        return not self.active or bool(self.session.get("confirmed_at"))

    # ---- after YouTube says live
    async def on_live(self, live_broadcast_id: str) -> None:
        if not self.active or not live_broadcast_id:
            return
        from ..room.world_mode import mark_live

        mark_live()
        if not self.dry_run:
            from . import launch_days
            launch_days.went_live(live_broadcast_id)       # Day 1 on the first public launch; broadcasts / hours
        self.session["state"] = "live"
        self.session["live_broadcast_id"] = live_broadcast_id
        self.session.setdefault("live_at", _iso())
        self._save()
        if self.dry_run:
            return
        applied = (self.session.get("applied") or {}).get("broadcast_id")
        if applied != live_broadcast_id:
            # YouTube went live on a different broadcast: it gets the same metadata.
            logger.warning(f"Pre-live: live broadcast {live_broadcast_id} is not the prepared {applied}; applying there")
            self.session["broadcast_id"] = live_broadcast_id
            self.session["applied"] = {"broadcast_id": live_broadcast_id}
            self.session["reapply"] = True
            self.session.setdefault("steps", {}).pop("youtube", None)
            await self.apply_youtube()
        await self.post_opening_comment(live_broadcast_id)

    async def post_opening_comment(self, broadcast_id: str) -> None:
        chat = self.session.get("chat") or {}
        if chat.get("state") == "posted" and chat.get("broadcast_id") == broadcast_id:
            return
        text = (self.session.get("prepared") or {}).get("opening_comment") or ""
        if not text or has_dash(text):
            return
        call = asyncio.to_thread
        try:
            client = self._client()
            chat_id = ""
            for _ in range(6):  # the chat can lag a few seconds behind "live"
                chat_id = await call(client.active_live_chat_id, broadcast_id)
                if chat_id:
                    break
                await asyncio.sleep(5)
            if not chat_id:
                raise RuntimeError("the live chat is not available")
            if chat.get("state") == "posting" and chat.get("broadcast_id") == broadcast_id:
                # A restart between posting and recording: look before posting again.
                mine = self.session.get("channel_id") or await call(client.my_channel_id)
                if text in (await call(client.recent_chat_texts, chat_id, mine)):
                    self.session["chat"] = {**chat, "state": "posted", "verified_after_restart": True}
                    self._save()
                    return
            self.session["chat"] = {"state": "posting", "broadcast_id": broadcast_id, "chat_id_known": True, "text": text, "at": _iso()}
            self._save()
            await call(client.post_chat_message, chat_id, text)
            # Pinning: the YouTube Data API has no endpoint to pin chat messages.
            self.session["chat"] = {"state": "posted", "broadcast_id": broadcast_id, "text": text, "at": _iso(), "pinned": False}
            self._save()
            logger.info("Pre-live: opening chat message posted (pinning is not available through the API)")
        except Exception as exc:
            self.session["chat"] = {**(self.session.get("chat") or {}), "state": "failed", "error": str(exc)[:200]}
            self._save()
            logger.warning(f"Pre-live: opening chat message not posted: {exc}")

    def end(self, reason: str = "stop") -> None:
        try:
            from . import launch_days
            launch_days.ended()
        except Exception as exc:
            logger.warning(f"launch days: {exc}")
        """A stream that went live is finished. One stopped during standby stays
        resumable (no second paid thumbnail for the same unaired stream)."""
        if not self.active or not self.session:
            return
        if self.session.get("state") not in ("live", "going_live"):
            self.session["stopped_in_standby_at"] = _iso()
            self.session.pop("confirmed_at", None)  # a new start asks again
            self._save()
            return
        history = _read(HISTORY_FILE, []) if not _flag("VR_TEST_STREAM") else None
        if history is None:
            self.session["state"] = "ended"
            self.session["ended_at"] = _iso()
            self._save()
            return
        history.append({"id": self.session.get("id"), "title": (self.session.get("prepared") or {}).get("title"),
                        "broadcast_id": self.session.get("live_broadcast_id"), "ended": _iso(), "reason": reason})
        _write(HISTORY_FILE, history[-200:])
        self.session["state"] = "ended"
        self.session["ended_at"] = _iso()
        self._save()


PRELIVE = PreLive()
