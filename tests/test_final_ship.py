"""Final ship pass: rehearsal life loop, OBS-led Stage with Firefox monitors,
time wording, opening comment and resolved pre-live failures."""
import asyncio
import json
from pathlib import Path

from src.open_llm_vtuber.publishing import prelive
from src.open_llm_vtuber.room import world_mode
from src.open_llm_vtuber.room.profiles import load_room
from src.open_llm_vtuber.room.session import RoomSession
from src.open_llm_vtuber.room.world_calendar import WorldCalendar

ROOT = Path(__file__).resolve().parents[1]


def session():
    return RoomSession(load_room(ROOT / "room", ROOT))


def test_rehearsal_is_not_held_waiting_for_a_live_stream(monkeypatch):
    # The hold gated her whole life loop; a rehearsal never goes live.
    monkeypatch.setenv("VR_MODE", "world")
    monkeypatch.setenv("VR_WORLD_HOLD_SPEECH", "1")
    monkeypatch.setattr(world_mode.WORLD_LIVE, "is_set", lambda: False)
    monkeypatch.delenv("VR_REHEARSAL", raising=False)
    assert world_mode.stream_is_live() is False
    monkeypatch.setenv("VR_REHEARSAL", "1")
    assert world_mode.stream_is_live() is True


def _stage_state(scene):
    return {"ready": True, "camera": "PHONE_HANDHELD_FRONT", "activity": "idle", "location": scene,
            "worldState": {"scene": scene}}


def test_obs_stage_leads_and_a_monitor_never_rewrites_reality():
    s = session()
    sent = []

    def sender(uid):
        async def send(text):
            sent.append((uid, json.loads(text)))
        return send

    async def go():
        show = s.lifestyle
        show.run = lambda: asyncio.sleep(0)  # no autonomous loop in this test
        # Firefox opens first, then the OBS Browser source.
        show.register("firefox")
        await s.register("firefox", sender("firefox"), role="scene1-stage")
        show.on_state("firefox", _stage_state("HOME"))
        assert show.leader() == "firefox"
        show.register("obs", obs=True)
        await s.register("obs", sender("obs"), role="scene1-stage")
        show.on_state("obs", _stage_state("GROUNDS"))
        assert show.leader() == "obs" and show.monitors() == ["firefox"]
        # The monitor reports its own (stationary) copy: Mika's reality is unchanged.
        show.on_state("firefox", _stage_state("HOME"))
        assert show.reality.physical.get("scene") == "GROUNDS"
        assert s.speech_target()[0] == "obs"
        # Speech audio goes to the monitor too, marked so it never acknowledges.
        sent.clear()
        await s.mirror_speech("obs", {"type": "audio", "audio": "AAAA", "volumes": [0.2]})
        assert [(uid, p.get("monitor")) for uid, p in sent] == [("firefox", True)]
        # Physical commands are mirrored; only the leader's answer counts.
        task = asyncio.create_task(show.command("casual_phone_chat"))
        await asyncio.sleep(0.01)
        actions = [(uid, p.get("mirror")) for uid, p in sent if p.get("type") == "lifestyle-action"]
        assert actions == [("obs", None), ("firefox", True)]
        ident = next(iter(show.waiters))
        show.acknowledge("firefox", {"id": ident, "ok": True})
        assert not task.done()
        show.acknowledge("obs", {"id": ident, "ok": True, "state": {}})
        assert (await task)["ok"]

    asyncio.run(go())


def test_leader_is_sticky_between_plain_pages():
    s = session()

    async def send(_text):
        return None

    async def go():
        show = s.lifestyle
        show.run = lambda: asyncio.sleep(0)
        for uid in ("a", "b"):
            show.register(uid)
            await s.register(uid, send, role="scene1-stage")
        show.on_state("b", _stage_state("HOME"))
        show.on_state("a", _stage_state("HOME"))
        assert show.leader() == "b"  # the later page does not steal it

    asyncio.run(go())


def test_spoken_and_displayed_time_name_am_pm_and_city():
    cal = WorldCalendar(clock=lambda: 1791614940.0)  # 2026-10-10 06:49 UTC = 02:49 in New York
    snap = cal.snapshot()
    assert snap["localTime"] == "02:49" and snap["clock12"] == "2:49 AM" and snap["city"] == "New York"


def test_opening_comment_is_the_creator_message_once_and_never_in_rehearsal():
    # the Godot world opens chat with the creator's character invite (fixed, never the LLM's line)
    text = prelive.CHARACTER_INVITE_CHAT
    assert len(text) <= 200 and not prelive.has_dash(text)
    assert "original character" in text
    meta = prelive.compose_metadata({"title": "t", "opening_comment": "an LLM line"}, {})
    assert meta["opening_comment"] == text


def test_resolved_failures_are_history_not_the_current_problem():
    s = {"failures": [{"step": "youtube", "at": "2026-10-10T06:23:59+00:00", "error": "invalid_grant"}],
         "steps": {"youtube": {"ok": True, "at": "2026-10-10T06:32:09+00:00"}}}
    assert prelive._current_failure(s) is None
    s["steps"]["youtube"] = {"ok": False, "at": "2026-10-10T06:32:09+00:00"}
    assert prelive._current_failure(s)["error"] == "invalid_grant"


def test_perception_separates_seen_hidden_and_within_reach(tmp_path):
    show = session().lifestyle
    show.places_file = tmp_path / "places.json"
    sp = {"subzone": "MAGIC_SANCTUARY",
          "landmarks": [{"label": "koi pond", "visible": True, "direction": "front", "distance": 6},
                        {"label": "bookshelf", "visible": False, "direction": "front", "distance": 8},
                        {"label": "stone lantern", "visible": True, "direction": "behind", "distance": 3}],
          "interactive": [{"label": "yellow flower", "reachable": True, "distance_m": 1.2},
                          {"label": "easel", "reachable": True, "distance_m": 9}]}
    seen = show.perception(sp)
    assert seen["inView"] == ["koi pond (6 m, in front)"]
    assert seen["nearbyNotInView"] == ["stone lantern (behind you)", "bookshelf (blocked from view)"]
    assert seen["withinReach"] == ["yellow flower"]
    show.remember_place(sp)  # a place she stood in is remembered across restarts
    assert json.loads(show.places_file.read_text()).keys() == {show.AREA_LABELS["MAGIC_SANCTUARY"]}


def test_spell_request_is_a_lesson_not_just_a_walk():
    from src.open_llm_vtuber.room.viewer_intents import classify_viewer
    assert classify_viewer("Mika, could you go practise a spell at your magic sanctuary?").action == "magic_lesson"
    assert classify_viewer("go to your magic sanctuary").arguments == {"place": "magic_sanctuary"}
    assert classify_viewer("don't cast a spell").action == "listen_to_viewer"


def test_go_dancing_is_a_request_but_a_compliment_is_not():
    from src.open_llm_vtuber.room.viewer_intents import classify_viewer
    assert classify_viewer("Mika, can you go dancing for us?").action == "dance_session"
    assert classify_viewer("I love your dancing").action is None
    assert classify_viewer("show me your magic sanctuary").arguments == {"place": "magic_sanctuary"}


def test_viewer_dance_session_counts_as_her_dance_practice():
    from types import SimpleNamespace
    from src.open_llm_vtuber.room.viewer_intents import ViewerIntent

    show = session().lifestyle

    async def step(_value):
        return {}

    async def publish():
        return None

    show.run_step, show.publish = step, publish
    show.autonomy.pool.state.update({"cycleStartedAt": show.clock(), "cycle": 1, "remaining": ["dance_practice", "explore"]})
    message = SimpleNamespace(timestamp=show.clock(), clean_text="can you go dancing?")
    asyncio.run(show.perform_viewer_action(ViewerIntent("ACTION_INTENT", "dance_session"), message))
    assert show.autonomy.history[-1]["id"] == "dance_practice"
    assert show.autonomy.cooldowns["dance_practice"] > show.clock()
    assert "dance_practice" not in show.autonomy.pool.remaining()
    reality = {"scene": "HOME", "dayPart": "AFTERNOON", "capabilities": {"dance_session": {"implemented": True}, "explore": {"implemented": True}}}
    assert "dance_practice" not in {s.id for s, _ in show.autonomy.candidates(reality)}
