import time
from datetime import datetime, timezone
from types import SimpleNamespace

from open_llm_vtuber.live.viewer_identity import ViewerIdentityStore
from open_llm_vtuber.live.youtube_live import YouTubeChatMessage, YouTubeLiveChatService


def yt(message_id: str, channel_id: str, display: str, text: str, handle: str = "") -> YouTubeChatMessage:
    return YouTubeChatMessage(
        message_id=message_id,
        author_channel_id=channel_id,
        author_display_name=display,
        text=text,
        timestamp=datetime.now(timezone.utc),
        author_handle=handle,
    )


def service_config() -> SimpleNamespace:
    return SimpleNamespace(
        youtube_live_enabled=True,
        chat_source="api",
        api_key="key",
        channel_id="UC0000000000000000000000",
        video_id="",
        prefer_stream_list=False,
        max_buffer_messages=20,
        message_buffer_seconds=120,
        same_user_cooldown_seconds=60,
        selector_max_messages=10,
        discovery_retry_seconds=1,
        response_cooldown_seconds=0,
        idle_banter_enabled=False,
    )


def test_mathunlocked_then_frcfinance_does_not_leak_identity(tmp_path, monkeypatch):
    monkeypatch.setenv("VIEWER_IDENTITY_FILE", str(tmp_path / "viewers.json"))
    svc = YouTubeLiveChatService(service_config(), None, SimpleNamespace())

    assert svc._accept(yt("m1", "UCMathUnlockedYT00000000", "@MathUnlockedYT", "hello"), "test")
    assert svc._accept(yt("m2", "UCFRCFinance000000000000", "@FRCFinance", "build a pool"), "test")

    messages = list(svc.buffer.messages)
    assert [m.author_display_name for m in messages] == ["@MathUnlockedYT", "@FRCFinance"]
    assert [m.author_channel_id for m in messages] == ["UCMathUnlockedYT00000000", "UCFRCFinance000000000000"]


def test_two_similar_display_names_remain_distinct(tmp_path):
    store = ViewerIdentityStore(tmp_path / "viewers.json")

    a = store.identify_youtube(yt("a", "UCAAAAAAAAAAAAAAAAAAAAAA", "Builder", "hi"))
    b = store.identify_youtube(yt("b", "UCBBBBBBBBBBBBBBBBBBBBBB", "Builder", "hi"))
    store.note(a)
    store.note(b)

    assert a.channel_id != b.channel_id
    assert len(store.records) == 2


def test_changed_display_name_same_channel_updates_metadata(tmp_path):
    path = tmp_path / "viewers.json"
    store = ViewerIdentityStore(path)

    first = store.identify_youtube(yt("a", "UCAAAAAAAAAAAAAAAAAAAAAA", "Old Name", "hi"))
    second = store.identify_youtube(yt("b", "UCAAAAAAAAAAAAAAAAAAAAAA", "New Name", "hi"))
    store.note(first)
    store.note(second)

    reloaded = ViewerIdentityStore(path)
    record = reloaded.records["youtube:UCAAAAAAAAAAAAAAAAAAAAAA"]
    assert record["display_name"] == "New Name"
    assert record["message_count"] == 2


def test_handle_fallback_when_channel_id_unavailable(tmp_path):
    store = ViewerIdentityStore(tmp_path / "viewers.json")

    identity = store.identify_youtube(yt("a", "", "@FRCFinance", "hi"))
    store.note(identity)

    assert identity.channel_id == "fallback:handle:@frcfinance"
    assert identity.handle == "@FRCFinance"
    assert store.records["youtube:fallback:handle:@frcfinance"]["message_count"] == 1


def test_stale_recent_answered_cannot_overwrite_incoming_identity(tmp_path, monkeypatch):
    monkeypatch.setenv("VIEWER_IDENTITY_FILE", str(tmp_path / "viewers.json"))
    svc = YouTubeLiveChatService(service_config(), None, SimpleNamespace())
    old = yt("old", "UCMathUnlockedYT00000000", "@MathUnlockedYT", "hello")
    svc.buffer.mark_answered(old)

    assert svc._accept(yt("new", "UCFRCFinance000000000000", "@FRCFinance", "build a pool"), "test")

    assert svc.buffer.messages[0].author_display_name == "@FRCFinance"
    assert svc.buffer.messages[0].author_channel_id == "UCFRCFinance000000000000"


def test_viewer_json_missing_and_corrupt_do_not_crash(tmp_path):
    missing = ViewerIdentityStore(tmp_path / "missing.json")
    assert missing.records == {}

    corrupt_path = tmp_path / "corrupt.json"
    corrupt_path.write_text("{not-json", encoding="utf-8")
    corrupt = ViewerIdentityStore(corrupt_path)
    identity = corrupt.identify_youtube(yt("a", "UCAAAAAAAAAAAAAAAAAAAAAA", "Viewer", "hi"))
    corrupt.note(identity)

    assert corrupt.records["youtube:UCAAAAAAAAAAAAAAAAAAAAAA"]["last_seen"] <= time.time()
