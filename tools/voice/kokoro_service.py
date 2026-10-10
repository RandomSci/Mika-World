"""Local Kokoro-82M speech service (CPU, ONNX). Runs in its own venv.

The model is loaded and warmed up once at start, then kept in memory, so each
line costs only inference. One synthesis runs at a time (the CPU is shared
with the 3D world and the stream encoder; parallel runs would only slow every
line down). Only 127.0.0.1 is served.

  GET  /health      -> {"ready": true, "voice": "af_heart", ...}
  POST /synthesize  {"text": "...", "voice": "af_heart", "lang": "en-us",
                     "speed": 1.0} -> audio/wav (16-bit PCM, 24 kHz)

Run:  tools/kokoro/.venv/bin/python tools/kokoro/service.py --port 12460
"""

import argparse
import io
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import onnxruntime as ort
import soundfile as sf
from kokoro_onnx import Kokoro

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAX_CHARS = 1200


class Engine:
    def __init__(self, model, voices, threads, voice):
        started = time.perf_counter()
        options = ort.SessionOptions()
        options.intra_op_num_threads = threads
        options.inter_op_num_threads = 1
        session = ort.InferenceSession(model, options, providers=["CPUExecutionProvider"])
        self.kokoro = Kokoro.from_session(session, voices)
        self.load_s = time.perf_counter() - started
        self.style(voice)  # fails early on an unknown voice
        started = time.perf_counter()
        # The first runs pay for graph optimisation; do them before any viewer waits.
        for text in ("Hello.", "Welcome to my little world, everyone!"):
            self.kokoro.create(text, voice=self.style(voice), speed=1.0, lang="en-us")
        self.warmup_s = time.perf_counter() - started
        self.lock = threading.Lock()
        self.info = {
            "ready": True,
            "model": os.path.basename(model),
            "voice": voice,
            "threads": threads,
            "load_s": round(self.load_s, 3),
            "warmup_s": round(self.warmup_s, 3),
            "lines": 0,
        }

    def style(self, voice):
        """A voice name, or a blend of style vectors such as 'af_bella:0.6,jf_alpha:0.4'."""
        known = set(self.kokoro.get_voices())
        if ":" not in voice:
            if voice not in known:
                raise ValueError(f"unknown voice {voice}")
            return voice
        total = None
        for part in voice.split(","):
            name, weight = part.split(":")
            if name not in known:
                raise ValueError(f"unknown voice {name}")
            vec = float(weight) * self.kokoro.get_voice_style(name)
            total = vec if total is None else total + vec
        return total

    def synthesize(self, text, voice, lang, speed, phonemes=False, gain=1.0):
        with self.lock:
            started = time.perf_counter()
            audio, rate = self.kokoro.create(text, voice=self.style(voice), speed=speed, lang=lang, is_phonemes=phonemes)
            audio = audio * float(gain)
            # Short fades: Kokoro trims silence, so a clause can start or stop on
            # a non-zero sample, which clicks at chunk boundaries.
            fade = min(len(audio) // 4, int(rate * .008))
            if fade > 1:
                ramp = np.linspace(0.0, 1.0, fade, dtype=audio.dtype)
                audio[:fade] *= ramp
                audio[-fade:] *= ramp[::-1]
            generated = time.perf_counter() - started
            self.info["lines"] += 1
        buffer = io.BytesIO()
        sf.write(buffer, np.clip(audio, -1.0, 1.0), rate, format="WAV", subtype="PCM_16")
        return buffer.getvalue(), generated, len(audio) / rate


def handler_for(engine):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def _json(self, code, body):
            data = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/health":
                return self._json(200, engine.info)
            self._json(404, {"error": "not found"})

        def do_POST(self):
            if self.path != "/synthesize":
                return self._json(404, {"error": "not found"})
            try:
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                text = " ".join(str(body.get("text") or "").split())[:MAX_CHARS]
                voice = str(body.get("voice") or engine.info["voice"])
                lang = str(body.get("lang") or "en-us")
                speed = float(body.get("speed") or 1.0)
                if not text:
                    return self._json(400, {"error": "empty text"})
                phonemes = str(body.get("phonemes") or "").strip()
                gain = min(1.5, max(.1, float(body.get("gain") or 1.0)))
                try:
                    engine.style(voice)
                except ValueError as exc:
                    return self._json(400, {"error": str(exc)})
                wav, generated, seconds = engine.synthesize(phonemes or text, voice, lang, speed, phonemes=bool(phonemes), gain=gain)
            except Exception as exc:
                return self._json(500, {"error": str(exc)[:300]})
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(wav)))
            self.send_header("X-Generation-Seconds", f"{generated:.3f}")
            self.send_header("X-Audio-Seconds", f"{seconds:.3f}")
            self.end_headers()
            self.wfile.write(wav)

    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=12460)
    parser.add_argument("--model", default=os.path.join(ROOT, "models/kokoro/kokoro-v1.0.onnx"))
    parser.add_argument("--voices", default=os.path.join(ROOT, "models/kokoro/voices-v1.0.bin"))
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--parent-pid", type=int, default=0,
                        help="exit when this process (the app that started us) is gone")
    args = parser.parse_args()
    if args.parent_pid:
        def watch_parent():
            while True:
                try:
                    os.kill(args.parent_pid, 0)
                except ProcessLookupError:
                    os._exit(0)
                except PermissionError:
                    pass
                time.sleep(2)

        threading.Thread(target=watch_parent, daemon=True).start()
    engine = Engine(args.model, args.voices, args.threads, args.voice)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(engine))
    print(json.dumps({"listening": args.port, **engine.info}), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
