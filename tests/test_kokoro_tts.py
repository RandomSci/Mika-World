"""Kokoro af_heart: real local synthesis, sentence order, fast fallback, recovery.

Uses the real model and service (tools/kokoro). Skipped where the isolated
environment or the model files are not installed.
"""

from __future__ import annotations

import asyncio
import os
import signal
import sys
import time
import wave
from pathlib import Path

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from open_llm_vtuber.room.speech import FallbackTTS  # noqa: E402
from open_llm_vtuber.tts import kokoro_tts  # noqa: E402
from open_llm_vtuber.tts.tts_factory import TTSFactory  # noqa: E402

NEEDED = [
    ROOT / "tools/kokoro/.venv/bin/python",
    ROOT / "models/kokoro/kokoro-v1.0.onnx",
    ROOT / "models/kokoro/voices-v1.0.bin",
]
pytestmark = pytest.mark.skipif(
    not all(p.exists() for p in NEEDED), reason="Kokoro is not installed"
)
PORT = 12461  # never the DEV server's own service
LINE = (
    "Hey, everyone! I'm Mika! Welcome to my little world. The garden looks "
    "beautiful today, doesn't it? I think I'll take a walk by the koi pond!"
)


def read_wav(path):
    with wave.open(str(path)) as w:
        rate, frames = w.getframerate(), w.readframes(w.getnframes())
        assert w.getnchannels() == 1 and w.getsampwidth() == 2
    return rate, np.frombuffer(frames, np.int16).astype(np.float32) / 32768


@pytest.fixture(scope="module")
def engine():
    e = TTSFactory.get_tts_engine("kokoro_tts", voice="af_heart", port=PORT)
    assert e._ready.wait(90), "Kokoro service did not become ready"
    yield e
    process = kokoro_tts._services.pop(PORT, None)
    if process:
        process.terminate()
        process.wait(10)


def test_service_preloads_and_warms_the_exact_voice(engine):
    h = engine.health
    assert h["ready"] and h["voice"] == "af_heart" and h["model"] == "kokoro-v1.0.onnx"
    assert h["warmup_s"] > 0 and h["load_s"] > 0
    assert (engine.voice, engine.lang, engine.speed) == ("af_heart", "en-us", 1.0)


def test_test_line_is_natural_speech_at_24khz(engine):
    path = engine.generate_audio(LINE, "kokoro_unit_line")
    try:
        rate, audio = read_wav(path)
        seconds = len(audio) / rate
        assert rate == 24000
        assert 6 < seconds < 12, seconds  # natural pace, not sped up
        assert np.sqrt(np.mean(audio**2)) > 0.03 and np.abs(audio).max() <= 1
        assert engine.last_generation_seconds < seconds  # faster than real time
    finally:
        engine.remove_file(path, verbose=False)


def test_sentences_of_one_reply_are_synthesized_in_order(engine):
    sentences = ["Hey, everyone!", "I'm Mika!", "Welcome to my little world.",
                 "The garden looks beautiful today, doesn't it?", "I think I'll take a walk by the koi pond!"]
    finished = []

    async def one(i, text):
        path = await engine.async_generate_audio(text, f"kokoro_unit_{i}")
        finished.append(i)
        return path

    async def run():
        return await asyncio.gather(*(one(i, s) for i, s in enumerate(sentences)))

    paths = asyncio.run(run())
    for p in paths:
        engine.remove_file(p, verbose=False)
    assert finished == list(range(len(sentences)))


def test_interrupted_reply_does_not_block_the_next_one(engine):
    async def run():
        long = [asyncio.create_task(engine.async_generate_audio(LINE, f"kokoro_cut_{i}")) for i in range(4)]
        await asyncio.sleep(0.3)
        for t in long:
            t.cancel()
        await asyncio.gather(*long, return_exceptions=True)
        started = time.perf_counter()
        path = await engine.async_generate_audio("Okay, next question!", "kokoro_after_cut")
        return path, time.perf_counter() - started

    path, waited = asyncio.run(run())
    engine.remove_file(path, verbose=False)
    # At most the one sentence already being synthesized finishes first;
    # the cancelled ones never reach the service.
    assert waited < 5.0, waited


class Backup:
    voice = "backup"

    def __init__(self, tmp):
        self.tmp, self.lines = tmp, 0

    def generate_audio(self, text, file_name_no_ext=None):
        self.lines += 1
        path = self.tmp / f"backup_{self.lines}.wav"
        path.write_bytes(b"RIFF" + b"\0" * 64)
        return str(path)

    async def async_generate_audio(self, text, file_name_no_ext=None):
        return self.generate_audio(text, file_name_no_ext)

    def remove_file(self, path, verbose=True):
        os.remove(path)


def test_unavailable_kokoro_falls_back_without_delay(tmp_path):
    dead = TTSFactory.get_tts_engine("kokoro_tts", port=12469, autostart=False)
    voice = FallbackTTS(dead, Backup(tmp_path), "mika")
    started = time.perf_counter()
    path = asyncio.run(voice.async_generate_audio("Hello there!"))
    assert Path(path).name == "backup_1.wav" and voice.fallbacks_used == 1
    assert time.perf_counter() - started < 1.0


def test_killed_service_falls_back_then_recovers(engine, tmp_path):
    voice = FallbackTTS(engine, Backup(tmp_path), "mika")
    os.kill(kokoro_tts._services[PORT].pid, signal.SIGKILL)
    kokoro_tts._services[PORT].wait(10)
    started = time.perf_counter()
    path = voice.generate_audio("Oops, one second.")
    assert Path(path).name == "backup_1.wav" and time.perf_counter() - started < 3.0
    # The service restarts by itself; Kokoro speaks again.
    deadline = time.time() + 60
    while time.time() < deadline and not engine._ready.is_set():
        time.sleep(0.25)
    path = voice.generate_audio("And I'm back!")
    assert Path(path).suffix == ".wav" and "backup" not in Path(path).name
    engine.remove_file(path, verbose=False)


def test_service_exits_when_the_app_that_started_it_is_killed():
    import socket
    import subprocess

    port = 12462
    child = subprocess.Popen(
        [sys.executable, "-c", (
            "import sys,time; sys.path.insert(0, 'src');"
            "from open_llm_vtuber.tts.tts_factory import TTSFactory;"
            f"e = TTSFactory.get_tts_engine('kokoro_tts', port={port});"
            "print('ready' if e._ready.wait(90) else 'failed', flush=True); time.sleep(600)"
        )],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    try:
        assert child.stdout.readline().strip() == "ready"
    finally:
        child.kill()  # SIGKILL: no atexit, no cleanup in the app
        child.wait(10)

    def listening():
        with socket.socket() as s:
            return s.connect_ex(("127.0.0.1", port)) == 0

    deadline = time.time() + 10
    while time.time() < deadline and listening():
        time.sleep(0.25)
    assert not listening(), "the Kokoro service outlived the app that started it"
