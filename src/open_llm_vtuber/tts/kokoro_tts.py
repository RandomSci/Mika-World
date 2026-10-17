import asyncio
import atexit
import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request

from loguru import logger
from .tts_interface import TTSInterface

# Kokoro-82M (Apache-2.0) through kokoro-onnx on the CPU, free and local.
# Inference runs in a separate process (tools/kokoro/service.py, own venv) that
# loads and warms the model once and stays up, so no line pays the load cost
# and the server's event loop never runs the model. This engine starts that
# service when it is not running yet and keeps the lines of one reply in order:
# a reply's sentences arrive together, and the first must be synthesized first.

ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..")
)
_services: dict[int, subprocess.Popen] = {}
_start_lock = threading.Lock()


def _stop_services() -> None:
    for process in _services.values():
        if process.poll() is None:
            process.terminate()


atexit.register(_stop_services)


class TTSEngine(TTSInterface):
    def __init__(
        self,
        voice: str = "af_heart",
        lang: str = "en-us",
        speed: float = 1.0,
        port: int = 12460,
        threads: int = 4,
        model_path: str = "models/kokoro/kokoro-v1.0.onnx",
        voices_path: str = "models/kokoro/voices-v1.0.bin",
        python_path: str = "tools/kokoro/.venv/bin/python",
        autostart: bool = True,
        ready_timeout: float = 60.0,
        start_wait: float = 8.0,
        clause_chunk_chars: int = 60,
        gain: float = 1.0,
        pronunciations_path: str = "tools/kokoro/pronunciations.json",
    ):
        self.voice = voice
        self.lang = lang
        self.speed = float(speed)
        self.port = int(port)
        self.threads = int(threads)
        self.model_path = self._path(model_path)
        self.voices_path = self._path(voices_path)
        self.python_path = self._path(python_path)
        self.autostart = autostart
        self.ready_timeout = float(ready_timeout)
        self.start_wait = float(start_wait)
        # Long sentences are spoken in clause-sized pieces (see tts_manager):
        # at ~0.35x real time each piece is ready before the previous ends.
        self.clause_chunk_chars = int(clause_chunk_chars) if clause_chunk_chars else None
        self.gain = float(gain)
        # Whole lines with a fixed pronunciation (incantations) are sent as IPA.
        self.pronunciations = {}
        try:
            data = json.loads(open(self._path(pronunciations_path), encoding="utf-8").read())
            self.pronunciations = {self._key(k): v for k, v in (data.get("lines") or {}).items()}
        except Exception:
            pass
        self.url = f"http://127.0.0.1:{self.port}"
        self.file_extension = "wav"
        self.health: dict = {}
        self.last_generation_seconds = None
        self.last_audio_seconds = None
        self._ready = threading.Event()
        self._order: asyncio.Lock | None = None
        self._order_loop = None
        self._starter: threading.Thread | None = None
        # Load and warm up now, in the background, not on the first viewer line.
        self._start_in_background()

    def _start_in_background(self) -> None:
        if self._starter is None or not self._starter.is_alive():
            self._starter = threading.Thread(target=self._ensure_service, daemon=True)
            self._starter.start()

    @staticmethod
    def _key(text: str) -> str:
        return " ".join(str(text).lower().split()).strip(" .!")

    @staticmethod
    def _path(path: str) -> str:
        return path if os.path.isabs(path) else os.path.join(ROOT, path)

    def _check(self) -> bool:
        try:
            with urllib.request.urlopen(self.url + "/health", timeout=1.5) as r:
                self.health = json.loads(r.read())
            return bool(self.health.get("ready"))
        except (urllib.error.URLError, OSError, ValueError):
            return False

    def _ensure_service(self) -> bool:
        if self._ready.is_set() and self._check():
            return True
        self._ready.clear()
        with _start_lock:
            if not self._check():
                process = _services.get(self.port)
                if (process is None or process.poll() is not None) and self.autostart:
                    missing = [
                        p
                        for p in (self.python_path, self.model_path, self.voices_path)
                        if not os.path.exists(p)
                    ]
                    if missing:
                        logger.error(f"Kokoro TTS cannot start, missing: {missing}")
                        return False
                    logger.info(f"Kokoro TTS: starting the local service on port {self.port}")
                    _services[self.port] = subprocess.Popen(
                        [
                            self.python_path,
                            os.path.join(ROOT, "tools", "kokoro", "service.py"),
                            "--port", str(self.port),
                            "--model", self.model_path,
                            "--voices", self.voices_path,
                            "--voice", self.voice,
                            "--threads", str(self.threads),
                            # Exits with this app, even when it is killed.
                            "--parent-pid", str(os.getpid()),
                        ],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        start_new_session=True,
                    )
                if self.port not in _services:
                    return False  # nothing to wait for (autostart is off)
                deadline = time.time() + self.ready_timeout
                while time.time() < deadline and not self._check():
                    process = _services.get(self.port)
                    if process is not None and process.poll() is not None:
                        logger.error(f"Kokoro TTS service exited with code {process.returncode}")
                        return False
                    time.sleep(0.25)
            if not self._check():
                logger.error("Kokoro TTS service did not become ready")
                return False
        logger.info(f"Kokoro TTS ready: {self.health}")
        self._ready.set()
        return True

    def generate_audio(self, text, file_name_no_ext=None):
        if not self._ready.is_set():
            # Never hold a line for a (re)start: wait briefly for a start that
            # is already under way, otherwise fail now so the fallback voice
            # speaks this line while the service comes back in the background.
            deadline = time.time() + self.start_wait
            while (
                self._starter is not None
                and self._starter.is_alive()
                and time.time() < deadline
                and not self._ready.wait(0.1)
            ):
                pass
            if not self._ready.is_set():
                if self._check():
                    self._ready.set()
                else:
                    self._start_in_background()
                    raise RuntimeError("Kokoro TTS service is not ready")
        request_body = {"text": text, "voice": self.voice, "lang": self.lang, "speed": self.speed, "gain": self.gain}
        ipa = self.pronunciations.get(self._key(text))
        if ipa:
            request_body["phonemes"] = ipa
        body = json.dumps(request_body).encode()
        request = urllib.request.Request(
            self.url + "/synthesize",
            data=body,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=25) as r:
                wav = r.read()
                self.last_generation_seconds = float(r.headers.get("X-Generation-Seconds") or 0)
                self.last_audio_seconds = float(r.headers.get("X-Audio-Seconds") or 0)
        except (urllib.error.URLError, OSError) as exc:
            # The service went away: this line falls back, the service restarts.
            self._ready.clear()
            self._start_in_background()
            raise RuntimeError(f"Kokoro TTS request failed: {exc}") from exc
        file_name = self.generate_cache_file_name(file_name_no_ext, self.file_extension)
        with open(file_name, "wb") as f:
            f.write(wav)
        return file_name

    async def async_generate_audio(self, text, file_name_no_ext=None):
        # asyncio.Lock wakes waiters first-in first-out, so sentences are
        # synthesized in the order the reply produced them. A cancelled
        # (interrupted) reply leaves the queue without sending its request.
        loop = asyncio.get_running_loop()
        if self._order is None or self._order_loop is not loop:
            self._order, self._order_loop = asyncio.Lock(), loop
        async with self._order:
            return await asyncio.to_thread(self.generate_audio, text, file_name_no_ext)
