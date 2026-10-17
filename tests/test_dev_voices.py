"""DEV must speak with the real voices, built the same way as the livestream.

Regression: the DEV server used to replace every voice with a test tone, so
Mika and Luna sounded like a vibration instead of Ana and Maisie.

Nothing here touches the network: Edge TTS only connects when it speaks, and
these tests only build the engines.
"""

from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
sys.path.insert(0, str(ROOT))

from open_llm_vtuber.config_manager.tts import EdgeTTSConfig, TTSConfig  # noqa: E402
from tests.harness.fake_tts import FakeTTS  # noqa: E402
from tests.harness.full_dev_server import create_app  # noqa: E402

ANA = "en-US-AnaNeural"
MAISIE = "en-GB-MaisieNeural"


def edge_context(voice: str = ANA):
    tts = TTSConfig(tts_model="edge_tts", edge_tts=EdgeTTSConfig(voice=voice))
    return SimpleNamespace(character_config=SimpleNamespace(tts_config=tts))


def engine_of(app, character_id):
    engine = app.state.session.voices.engine(character_id)
    return getattr(engine, "primary", engine)


def unwrap(engine):
    """The real engine under FallbackTTS / the DEV VoiceMeter."""
    while hasattr(engine, "primary"):
        engine = engine.primary
    return engine


def fallback_of(app, character_id):
    return unwrap(app.state.session.voices.engine(character_id).fallback)


def test_dev_uses_real_voices_by_default():
    app = create_app(ROOT, context=edge_context())
    mika = unwrap(engine_of(app, "mika"))
    luna = unwrap(engine_of(app, "luna"))
    assert not isinstance(mika, FakeTTS)
    assert not isinstance(luna, FakeTTS)
    # Mika: Kokoro (af_bella/jf_alpha blend) from mika.yaml, natural speed, Edge Ana as fallback.
    assert type(mika).__module__.endswith("kokoro_tts")
    assert (mika.voice, mika.lang, mika.speed, mika.gain) == ("af_bella:0.6,jf_alpha:0.4", "en-us", 1.0, 0.7)
    assert type(fallback_of(app, "mika")).__module__.endswith("edge_tts")
    assert fallback_of(app, "mika").voice == ANA
    assert type(luna).__module__.endswith("edge_tts")
    assert luna.voice == MAISIE  # her own voice from luna.yaml


def test_mika_keeps_her_own_voice_when_conf_yaml_changes():
    app = create_app(ROOT, context=edge_context("en-US-JennyNeural"))
    assert unwrap(engine_of(app, "mika")).voice == "af_bella:0.6,jf_alpha:0.4"
    assert unwrap(engine_of(app, "luna")).voice == MAISIE


def test_fake_voices_only_when_asked():
    tone = FakeTTS()
    app = create_app(ROOT, context=edge_context(), tts=tone)
    mika = app.state.session.voices.engine("mika")
    assert unwrap(mika) is tone and unwrap(mika.fallback) is tone  # primary and fallback
    assert app.state.session.voices.engine("luna") is tone


def test_no_conf_yaml_never_falls_back_to_the_tone():
    app = create_app(ROOT, context=SimpleNamespace(character_config=None))
    assert not isinstance(app.state.session.voices.engine("mika"), FakeTTS)
    assert not isinstance(app.state.session.voices.engine("luna"), FakeTTS)


def test_world_profile_keeps_mika_voice_and_disables_teaching():
    app = create_app(ROOT, context=edge_context(), world_mode=True)
    session = app.state.session
    assert [character.id for character in session.room.characters] == ["mika"]
    assert unwrap(engine_of(app, "mika")).voice == "af_bella:0.6,jf_alpha:0.4"
    assert fallback_of(app, "mika").voice == ANA
    assert not session.room.ambient.moves_enabled
    assert not session.room.camera.auto_focus
    assert session.director.teaching_intent_classifier is None
    assert session.director.coding_action_runner is None
