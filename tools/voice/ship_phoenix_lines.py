#!/usr/bin/env python3
"""Ships Oriel's authored lines (data/phoenix.json) as pre-rendered Kore audio, so the game speaks them without
the network and without spending quota again: the session cache (user://voice_cache/gemini) is scanned for
the WAVs VoiceService wrote for exactly those lines (same key: sha1 of model|voice|style|text) and they are
copied to assets/voice/phoenix/ with a manifest. Lines not yet rendered are listed, not invented.

  python3 tools/voice/ship_phoenix_lines.py [--cache <dir>] [--dry]
"""
import argparse
import hashlib
import json
import os
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DEFAULT_CACHE = os.path.expanduser("~/.local/share/godot/app_userdata/Mika World 2.0 - Arcane Sanctuary (DEV)/voice_cache/gemini")
OUT = os.path.join(ROOT, "assets", "voice", "phoenix")


def clean(t):
    s = t.replace(" — ", ", ").replace("—", ", ").replace(" – ", ", ").replace("–", "-")
    return s.replace(",,", ",").strip()


def style_for(cfg, form, mood):
    styles = cfg.get("styles", {})
    s = styles.get(form, styles.get("humanoid", ""))
    if mood and mood in styles.get("moods", {}):
        s += " " + styles["moods"][mood]
    return s


def key_for(cfg, text, style):
    return hashlib.sha1(("%s|%s|%s|%s" % (cfg.get("model", ""), cfg.get("voice", ""), style, text)).encode()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=DEFAULT_CACHE)
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    voices = json.load(open(os.path.join(ROOT, "data", "voices.json")))
    cfg = voices["speakers"]["phoenix"]
    ph = json.load(open(os.path.join(ROOT, "data", "phoenix.json")))
    lines = []
    forms = {"lighting": "phoenix", "before_transform": "phoenix", "arrive": "phoenix", "creature": "phoenix", "fallback": "humanoid",
             "after_transform": "humanoid", "farewell": "humanoid", "reform": "humanoid"}
    moods = {"before_transform": "playful", "after_transform": "playful", "farewell": "tender", "reform": "serious"}
    for k, text in ph["lines"].items():
        lines.append({"id": "line:" + k, "text": clean(text), "form": forms.get(k, "humanoid"), "mood": moods.get(k, "")})
    for b in ph["beats"]:
        lines.append({"id": "beat:" + b["id"], "text": clean(b["npc"]), "form": "humanoid", "mood": b.get("mood", "")})
    for kind, texts in voices.get("reactions", {}).get("clips", {}).items():
        if isinstance(texts, dict) and "phoenix" in texts:
            lines.append({"id": "reaction:" + kind, "text": clean(texts["phoenix"]), "form": "humanoid", "mood": ""})
    os.makedirs(OUT, exist_ok=True)
    manifest = {"_note": "Pre-rendered lines in Oriel's confirmed voice (Google Gemini TTS, Kore; generated once with the developer's key during verification runs; audio/wav 24 kHz mono). VoiceService looks here first, then user://voice_cache/gemini, then the cloud (once per line), then the Kokoro fallback. Keys: sha1(model|voice|style|text).", "voice": cfg["voice"], "model": cfg["model"], "lines": {}}
    missing = []
    for ln in lines:
        style = style_for(cfg, ln["form"], ln["mood"])
        key = key_for(cfg, ln["text"], style)
        src = os.path.join(a.cache, key + ".wav")
        dst = os.path.join(OUT, key + ".wav")
        if os.path.exists(src) or os.path.exists(dst):
            if os.path.exists(src) and not a.dry:
                shutil.copyfile(src, dst)
            manifest["lines"][key] = {"id": ln["id"], "text": ln["text"], "form": ln["form"], "mood": ln["mood"], "bytes": os.path.getsize(dst if os.path.exists(dst) else src)}
        else:
            missing.append(ln["id"])
    if not a.dry:
        with open(os.path.join(OUT, "manifest.json"), "w") as f:
            json.dump(manifest, f, indent=1)
    total = sum(v["bytes"] for v in manifest["lines"].values())
    print("shipped %d lines (%.1f MB), missing %d: %s" % (len(manifest["lines"]), total / 1e6, len(missing), ", ".join(missing)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
