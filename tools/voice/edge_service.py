"""DEV speech service for the confirmed Microsoft Edge neural voices (Milestone J).

Wraps the `edge-tts` package (the same one Mika-Voice-Lab used to audition the voices) and returns the
same format as the local Kokoro service, so VoiceService treats both providers alike:

  GET  /health      -> {"ready": true, "provider": "edge", ...}
  POST /synthesize  {"text": "...", "voice": "en-US-AvaNeural", "pitch": "+25Hz", "rate": "+5%",
                     "gain": 0.8} -> audio/wav (16-bit PCM mono, 24 kHz)

Notes
* Edge voices are an ONLINE service: each new line's text is sent to Microsoft's speech endpoint. Lines are
  cached on disk (hash of voice+pitch+rate+text), so repeated lines cost nothing and work offline.
* Only 127.0.0.1 is served. One synthesis at a time. MP3 from the service is decoded with ffmpeg.
* Any failure returns a JSON error; the game then falls back to Kokoro for that line (never silence).

Run:  .venv-voice/bin/python tools/voice/edge_service.py --port 12472 --parent-pid <pid>
"""

import argparse
import asyncio
import hashlib
import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import edge_tts

MAX_CHARS = 1200
CACHE_MAX = 2000           # files; oldest are pruned


class Engine:
    def __init__(self, cache_dir, timeout):
        self.cache_dir = cache_dir
        self.timeout = timeout
        os.makedirs(cache_dir, exist_ok=True)
        self.lock = threading.Lock()
        self.info = {"ready": True, "provider": "edge", "edge_tts": getattr(edge_tts, "__version__", "?"),
                     "lines": 0, "cache_hits": 0, "online_calls": 0, "errors": 0}

    def _key(self, voice, pitch, rate, text):
        return hashlib.sha1(f"{voice}|{pitch}|{rate}|{text}".encode()).hexdigest()

    async def _fetch(self, text, voice, pitch, rate):
        comm = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
        out = bytearray()
        async for chunk in comm.stream():
            if chunk["type"] == "audio":
                out += chunk["data"]
        return bytes(out)

    def synthesize(self, text, voice, pitch, rate, gain):
        key = self._key(voice, pitch, rate, text)
        path = os.path.join(self.cache_dir, key + ".wav")
        started = time.perf_counter()
        with self.lock:
            self.info["lines"] += 1
            if os.path.exists(path):
                self.info["cache_hits"] += 1
                wav = open(path, "rb").read()
                os.utime(path)
            else:
                self.info["online_calls"] += 1
                mp3 = asyncio.run(asyncio.wait_for(self._fetch(text, voice, pitch, rate), self.timeout))
                if not mp3:
                    raise RuntimeError("no audio returned")
                wav = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", "pipe:0", "-ac", "1", "-ar", "24000",
                                      "-af", f"volume={gain:.3f}", "-c:a", "pcm_s16le", "-f", "wav", "pipe:1"],
                                     input=mp3, capture_output=True, check=True).stdout
                wav = _fix_wav_sizes(wav)
                tmp = path + ".tmp"
                open(tmp, "wb").write(wav)
                os.replace(tmp, path)
                self._prune()
        return wav, time.perf_counter() - started

    def _prune(self):
        files = [os.path.join(self.cache_dir, f) for f in os.listdir(self.cache_dir) if f.endswith(".wav")]
        if len(files) > CACHE_MAX:
            files.sort(key=os.path.getmtime)
            for f in files[: len(files) - CACHE_MAX]:
                os.remove(f)


def _fix_wav_sizes(wav):
    """ffmpeg writing WAV to a pipe leaves the RIFF/data sizes unset (0xFFFFFFFF); fill them in."""
    b = bytearray(wav)
    b[4:8] = (len(b) - 8).to_bytes(4, "little")
    i = 12
    while i < len(b) - 8:
        cid = bytes(b[i:i + 4])
        size = int.from_bytes(b[i + 4:i + 8], "little")
        if cid == b"data":
            b[i + 4:i + 8] = (len(b) - i - 8).to_bytes(4, "little")
            break
        i += 8 + size
    return bytes(b)


def handler_for(engine):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _json(self, code, obj):
            data = json.dumps(obj).encode()
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
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
                text = str(body.get("text") or "").strip()[:MAX_CHARS]
                if not text:
                    return self._json(400, {"error": "empty text"})
                voice = str(body.get("voice") or "en-US-AvaNeural")
                pitch = str(body.get("pitch") or "+0Hz")
                rate = str(body.get("rate") or "+0%")
                gain = min(1.5, max(.1, float(body.get("gain") or 1.0)))
                wav, took = engine.synthesize(text, voice, pitch, rate, gain)
            except Exception as exc:
                engine.info["errors"] += 1
                return self._json(502, {"error": str(exc)[:300] or type(exc).__name__})
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(wav)))
            self.send_header("X-Generation-Seconds", f"{took:.3f}")
            self.end_headers()
            self.wfile.write(wav)

    return Handler


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=12472)
    p.add_argument("--cache", default=os.path.expanduser("~/.cache/mika-godot-dev/edge_voice"))
    p.add_argument("--timeout", type=float, default=10.0)
    p.add_argument("--parent-pid", type=int, default=0)
    args = p.parse_args()
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
    engine = Engine(args.cache, args.timeout)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(engine))
    print(json.dumps({"listening": args.port, **engine.info}), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
