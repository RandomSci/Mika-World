"""Clause chunking for slow local voices (Kokoro): order, captions, actions."""

from __future__ import annotations

import asyncio
import json
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from open_llm_vtuber.agent.output_types import Actions, DisplayText  # noqa: E402
from open_llm_vtuber.conversations.tts_manager import TTSTaskManager, clause_chunks  # noqa: E402

LONG = "I'm just enjoying some quiet time in my reading chair, soaking in the morning light while I think about my next small goal."


def test_long_sentence_splits_only_at_clause_punctuation():
    assert clause_chunks(LONG, 60) == [
        "I'm just enjoying some quiet time in my reading chair,",
        "soaking in the morning light while I think about my next small goal.",
    ]


def test_short_sentences_and_other_voices_stay_whole():
    assert clause_chunks("It's a lovely, calm moment for me.", 60) == ["It's a lovely, calm moment for me."]
    assert clause_chunks(LONG, None) == [LONG]  # engines without the attribute
    no_commas = "A long sentence without commas that keeps going and going about the garden and the pond today"
    assert clause_chunks(no_commas, 60) == [no_commas]


def test_chunks_grow_and_never_leave_a_tiny_tail():
    text = ("Okay so here is the plan: I grab my tea, I walk out to the koi pond, I count the fish, "
            "and then, if the light is still good, we watch the sunset together from the little bridge.")
    chunks = clause_chunks(text, 60)
    assert " ".join(chunks) == text
    assert len(chunks[0]) <= 60 and all(len(c) >= 18 for c in chunks)


class SlowVoice:
    """Later chunks finish first, so delivery order must come from the manager."""

    clause_chunk_chars = 60

    def __init__(self, tmp):
        self.tmp, self.n, self.spoken = tmp, 0, []

    async def async_generate_audio(self, text, file_name_no_ext=None):
        self.n += 1
        index = self.n
        self.spoken.append(text)
        await asyncio.sleep(0.2 if index == 1 else 0.01)
        path = self.tmp / f"chunk_{index}.wav"
        with wave.open(str(path), "wb") as w:
            w.setnchannels(1), w.setsampwidth(2), w.setframerate(24000)
            w.writeframes(b"\x10\x20" * 4800)
        return str(path)

    def remove_file(self, path, verbose=True):
        Path(path).unlink(missing_ok=True)


def test_chunks_play_in_order_with_their_own_captions(tmp_path):
    voice, sent = SlowVoice(tmp_path), []

    async def send(payload):
        sent.append(json.loads(payload))

    async def run():
        manager = TTSTaskManager()
        await manager.speak(
            tts_text=LONG,
            display_text=DisplayText(text=LONG, name="Mika"),
            actions=Actions(expressions=["joy"]),
            live2d_model=None,
            tts_engine=voice,
            websocket_send=send,
        )
        await manager.flush()
        manager.clear()

    asyncio.run(run())
    assert voice.spoken == clause_chunks(LONG, 60)
    assert [p["display_text"]["text"] for p in sent] == voice.spoken
    assert all(p["audio"] and p["volumes"] for p in sent)
    assert sent[0]["actions"] and sent[0]["actions"]["expressions"] == ["joy"]
    assert not sent[1].get("actions")
