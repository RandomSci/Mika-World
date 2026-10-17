"""Ship-now behaviour: five-hour activity pool, direct planning (no bedroom
reset), magic progression, destination intents, public text and the pre-live
thumbnail fallback. Pure Python: no browser, no network, no paid calls."""

from __future__ import annotations

import asyncio
import io
import json
import random
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from open_llm_vtuber.room.activity_registry import CYCLE_SECONDS, ActivityPool, verified_ids  # noqa: E402
from open_llm_vtuber.room.autonomy import Autonomy, GOALS  # noqa: E402
from open_llm_vtuber.room.magic import LESSONS, SPELLS, MagicTraining  # noqa: E402
from open_llm_vtuber.room.viewer_intents import classify_viewer  # noqa: E402
from open_llm_vtuber.conversations.tts_manager import no_dashes  # noqa: E402


class Clock:
    def __init__(self, t=1_000_000.0): self.t = t
    def __call__(self): return self.t


# Capabilities as the real Stage reports them (implemented, any scene).
CAPS = {name: {"implemented": True} for name in [
    "magic_lesson", "dance_session", "dance_challenge", "visit_gardens", "explore", "visit_lantern_retreat", "visit_atelier",
    "quiet_outside", "go_jogging", "sit_chair", "tour_room", "show_window", "show_desk", "return_home"]}
CAPS.update({"read_book": {"implemented": False}, "pick_flower": {"implemented": False}, "sit_bench": {"implemented": False}})


def reality(scene="HOME", **extra):
    return {"scene": scene, "dayPart": "AFTERNOON", "capabilities": CAPS, "availableActions": [k for k, v in CAPS.items() if v["implemented"]], **extra}


def test_registry_only_holds_verified_activities():
    ids = verified_ids(reality())
    assert {"magic_training", "dance_practice", "explore"} <= set(ids)
    # never her own objective: paused features, and bedroom-only ones (the Godot world has no bedroom)
    assert not {"read", "flower", "garden_bench", "coding_session", "head_home", "relax"} & set(ids)


def test_completed_activities_leave_the_pool_and_failures_stay(tmp_path):
    clock = Clock(); pool = ActivityPool(clock, tmp_path / "pool.json")
    assert pool.ensure_cycle(reality())
    pool.complete("explore"); pool.fail("atelier", "route blocked")
    assert "explore" not in pool.remaining() and "atelier" in pool.remaining()
    # Persisted: a restart sees the same open objectives.
    again = ActivityPool(clock, tmp_path / "pool.json")
    assert again.remaining() == pool.remaining() and again.state["cycle"] == 1


def test_pool_resets_only_after_five_hours(tmp_path):
    clock = Clock(); pool = ActivityPool(clock, tmp_path / "pool.json")
    pool.ensure_cycle(reality())
    for i in list(pool.remaining()):
        pool.complete(i)
    assert pool.exhausted()
    clock.t += CYCLE_SECONDS - 60
    assert not pool.ensure_cycle(reality()) and pool.exhausted()  # never refilled early
    clock.t += 120
    assert pool.ensure_cycle(reality()) and not pool.exhausted() and pool.state["cycle"] == 2


def test_exhausted_pool_revisits_older_activities_instead_of_standing_still():
    # Final ship pass: the pool emptied in under an hour and she then stood
    # still until the five-hour reset. Now she revisits, never her last three.
    clock = Clock(); a = Autonomy(clock, random.Random(1))
    a.pool.ensure_cycle(reality())
    cycle = a.pool.state["cycle"]
    for i in list(a.pool.remaining()):
        a.pool.complete(i)
    last_three = ["dance_practice", "magic_training", "explore"]
    a.history = [{"id": g, "status": "completed"} for g in last_three]
    for _ in range(20):
        spec = a.choose(reality())
        assert spec is not None and spec.id not in last_three
    assert a.last_decision["revisit"] and a.blocking_reason is None
    assert a.pool.state["cycle"] == cycle and a.pool.exhausted()  # the cycle is not reset early


def test_plans_start_from_where_she_is_without_a_bedroom_reset():
    a = Autonomy(Clock(), random.Random(2))
    # Outdoor activities end where they end: no return_home afterwards.
    for gid in ("fresh_air", "stargaze", "lantern_walk", "explore", "atelier"):
        assert "return_home" not in GOALS[gid].after
    # A bedroom activity from the garden walks into the house first (a real trip).
    goal = a.start(GOALS["relax"], reality("GROUNDS"))
    assert goal["plan"][0] == ("act", "return_home") and goal["plan"][1] == ("act", "sit_chair")
    a.finish("completed")
    # From the bedroom, no trip at all.
    goal = a.start(GOALS["window"], reality("HOME"))
    assert goal["plan"][0] == ("act", "show_window")


def test_magic_lessons_unlock_in_order_and_persist(tmp_path):
    m = MagicTraining(tmp_path / "magic.json", rng=random.Random(5))
    first = m.next_lesson(); assert first.id == "l1_sparks" and first.level == 1
    m.record_cast(first, {"spell": "lux_surgat", "outcome": "success", "firedAt": 1.33, "effects": ["sparks"]})
    result = m.finish_lesson(first, successes=first.needed, attempts=3)
    assert result["passed"] and m.next_lesson().id == "l2_orb"
    reloaded = MagicTraining(tmp_path / "magic.json")
    assert reloaded.level() == 1 and reloaded.state["practice"]["lux_surgat"] == 1
    m.finish_lesson(m.next_lesson(), successes=0, attempts=3)
    assert m.state["unfinished"]["lesson"] == "l2_orb" and m.next_lesson().id == "l2_orb"  # retried later, not skipped


def test_spell_outcomes_and_incantations():
    m = MagicTraining(None, rng=random.Random(9))
    seen = {m.outcome("lux_surgat") for _ in range(400)}
    assert seen <= {"success", "partial", "fail", "mishap"} and {"success", "fail"} <= seen
    assert all("—" not in s.incantation and "–" not in s.incantation for s in SPELLS.values())
    assert [lesson.level for lesson in LESSONS] == sorted(lesson.level for lesson in LESSONS) and LESSONS[-1].level == 6


@pytest.mark.parametrize("text,place", [
    ("Mika can you go to the koi pond?", "koi_pond"), ("walk to the far corner of the garden", "north_lawn"),
    ("show me your magic sanctuary", "magic_sanctuary"), ("go to your desk", "desk"), ("head to the lantern bench", "lantern_bench")])
def test_viewer_destination_requests_become_actions(text, place):
    intent = classify_viewer(text)
    assert (intent.action, intent.arguments) == ("go_to", {"place": place})


def test_viewer_negations_and_magic_requests():
    assert classify_viewer("dont go to the pond").action == "listen_to_viewer"
    assert classify_viewer("cast a spell!").action == "magic_lesson"
    assert classify_viewer("can you dance?").action == "dance_session"
    assert classify_viewer("what is your favorite fish").action is None


def test_public_text_has_no_dashes():
    assert no_dashes("sparks—definitely, still – learning") == "sparks, definitely, still, learning"


# ---- pre-live thumbnail fallback (no paid call is made here) -----------------
def _png(color=(40, 60, 90)):
    from PIL import Image
    out = io.BytesIO(); Image.new("RGB", (1536, 1024), color).save(out, "PNG"); return out.getvalue()


@pytest.fixture
def prelive(tmp_path, monkeypatch):
    from open_llm_vtuber.publishing import prelive as P
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(P, "DATA", tmp_path / "data/prelive"); monkeypatch.setattr(P, "SESSION_FILE", tmp_path / "data/prelive/session.json")
    monkeypatch.setattr(P, "BUDGET_FILE", tmp_path / "data/prelive/image_budget.json"); monkeypatch.setattr(P, "THUMB_CACHE", tmp_path / "data/prelive/thumbnails")
    default = tmp_path / "default.jpg"; default.write_bytes(P.render_thumbnail(_png(), "MIKA'S WORLD"))
    monkeypatch.setattr(P, "DEFAULT_THUMBNAIL", default)
    monkeypatch.setenv("VR_PRELIVE", "1"); monkeypatch.setenv("OPENAI_API_KEY", "test"); monkeypatch.delenv("VR_REHEARSAL", raising=False)
    pl = P.PreLive(); pl.open_session(force_new=True); pl.session["prepared"] = {"thumbnail_text": "COME SAY HI"}
    return P, pl


def test_quota_error_falls_back_without_retrying_paid_generation(prelive, monkeypatch):
    P, pl = prelive; calls = []

    async def quota(frame, ctx):
        calls.append(1); b = P._budget(); b["blocked_until"] = P._now() + 86400; P._write(P.BUDGET_FILE, b)
        raise P.ImageQuotaError("insufficient_quota")
    monkeypatch.setattr(P, "generate_art", quota)

    async def frame():
        return b"jpg"
    assert asyncio.run(pl.prepare_thumbnail(frame))
    assert pl.session["thumbnail"]["source"] == "default" and len(calls) == 1
    allowed, why = P.image_generation_allowed()
    assert not allowed and "quota" in why  # no further paid attempts for 24 h
    # A restart of the same session never regenerates either.
    pl.session["steps"].pop("thumbnail"); assert asyncio.run(pl.prepare_thumbnail(frame)) and len(calls) == 1


def test_generated_art_is_cached_and_reused_later(prelive, monkeypatch):
    P, pl = prelive

    async def ok(frame, ctx):
        return _png((120, 80, 160))
    monkeypatch.setattr(P, "generate_art", ok)

    async def frame():
        return b"jpg"
    assert asyncio.run(pl.prepare_thumbnail(frame)) and pl.session["thumbnail"]["source"] == "generated"
    assert P.validate_thumbnail(Path(pl.session["thumbnail"]["path"]).read_bytes()) == []
    # Next stream with zero credits: the approved art is reused, the text is fresh.
    monkeypatch.setenv("VR_THUMBNAIL_GENERATE", "0")
    pl.open_session(force_new=True); pl.session["prepared"] = {"thumbnail_text": "MAGIC PRACTICE"}
    assert asyncio.run(pl.prepare_thumbnail(frame)) and pl.session["thumbnail"]["source"] == "reused"


def test_metadata_validation_rejects_dashes_and_links(prelive):
    P, _ = prelive
    good = {"title": "AI VTuber Mika practises magic in her garden", "intro": "Morning practice.", "description": "x" * 300,
            "opening_comment": "Welcome in! Say hi to Mika.", "thumbnail_text": "COME SAY HI"}
    assert P.validate_metadata(good) == []
    assert P.validate_metadata({**good, "title": "Mika — live"})
    assert P.validate_metadata({**good, "opening_comment": "join https://x.y"})
    assert P.validate_metadata({**good, "thumbnail_text": "FRIDAY DEBUT"})


def test_rehearsal_can_never_go_live(prelive, monkeypatch):
    P, pl = prelive
    monkeypatch.setenv("VR_REHEARSAL", "1")
    assert pl.confirm()["ok"] is False


def test_lifestyle_runner_speech_paths_are_intact():
    """Guards the soak regression: prompts build, speak exists, timeouts resolve."""
    from open_llm_vtuber.room import lifestyle as L
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from test_autonomy import make_show
    show = make_show()[0]
    assert callable(getattr(show, "speak", None)) and callable(getattr(show, "say", None))
    state = json.loads(show.state_block())
    assert {"time", "where", "doingNow", "recentlyDoneNewestFirst", "magic", "dance"} <= set(state)
    for text in (show.prompt(True), show.prompt(), show.activity_prompt()):
        assert "MIKA STATE" in text and "—" not in L.CONTENT_RULES
    assert L.action_timeout("magic_prepare") == 250 and L.action_timeout("anything_else") == 65
