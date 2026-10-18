import asyncio
from types import SimpleNamespace

from open_llm_vtuber.publishing.stream_autopilot import StreamAutopilot


def _pilot():
    settings = SimpleNamespace(
        youtube_enabled=True, youtube_chat_enabled=False, dry_run=True, youtube_ready=False
    )
    return StreamAutopilot(SimpleNamespace(settings=settings))


def test_end_stream_says_goodbye_then_stops(monkeypatch, tmp_path):
    monkeypatch.setenv("OBS_WEBSOCKET_PASSWORD", "")
    monkeypatch.chdir(tmp_path)  # the 11h55m limit leaves logs/mika-live-limit (a restart marker) in the cwd
    pilot = _pilot()
    calls = []

    async def goodbye(reason):
        calls.append(reason)

    pilot.goodbye = goodbye
    pilot.shutdown = lambda: calls.append("shutdown")
    asyncio.run(pilot.end_stream("limit"))
    asyncio.run(pilot.end_stream("limit"))  # only once
    assert calls == ["limit", "shutdown"]
    assert (tmp_path / "logs" / "mika-live-limit").exists()


def test_the_farewell_is_the_world_show_one():
    text = _pilot().farewell
    assert "Mika" in text and "learning" not in text and "lesson" not in text
