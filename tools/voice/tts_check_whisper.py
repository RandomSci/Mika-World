"""TTS pronunciation check, step 2 (anaconda python with openai-whisper): transcribe every BEFORE and AFTER clip of
tts_check_synth.py and flag a line when a word comes back spelled out as letters (H M, B R B, aitch), skipped, or
garbled. Writes <dir>/report.json and prints the flagged items.
  python tools/voice/tts_check_whisper.py <dir> [whisper model]
"""
import difflib
import json
import os
import re
import sys

import whisper

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tts_text  # noqa: E402  (the recogniser writes numbers as digits: read them back as words)

PROFANE = re.compile(r"\b(fuck\w*|shit\w*|piss\w*|bitch\w*|damn\w*|cunt|dick|cock|ass(?:hole)?|bastard|slut|whore|nigg\w*|fag\w*|retard\w*)\b", re.I)

d = sys.argv[1]
model = whisper.load_model(sys.argv[2] if len(sys.argv) > 2 else "small")
items = json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))
INLINE = re.compile(r"\[([^\]]+)\]\(/[^/]+/\)")
LETTERS = re.compile(r"(?:\b(?![AaIi]\b)[A-Za-z]\b[\s\.\-,]*){2,}|\baitch\b|\b(?!AM\b|PM\b|AI\b|OK\b)[A-Z]{2,4}\b")


def words(s):
    return re.findall(r"[a-z']+", s.lower().replace("-", " "))


def heard(path):
    r = model.transcribe(path, language="en", fp16=True, temperature=0.0, condition_on_previous_text=False)
    return r["text"].strip()


def judge(it, mode, text):
    """Problems in one transcription: profanity, spelled-out letters, words missing from what was meant to be said."""
    probs = []
    if PROFANE.search(text) and not PROFANE.search(it["text"]):
        probs.append("PROFANITY heard: '%s'" % text)
    text = tts_text._numbers(re.sub(r"\b([ap])\.\s?m\.?", r"\1m", text, flags=re.I))
    if it["kind"] == "dict":
        m = re.search(r"said\s*(.*?)\s*again", text, re.I | re.S)
        mid = m.group(1) if m else text
        if LETTERS.search(mid) and it["key"].upper() not in ("AI", "VR", "XP", "HP", "MP", "NPC", "TV", "USA", "UK", "EU", "PC", "DJ", "VIP", "MVP", "RPG", "FPS", "CEO", "DM", "ID", "ASMR", "UFO", "DIY", "OBS", "GPU", "CPU", "UI"):
            probs.append("spelled out: '%s'" % mid.strip(" .,"))
        if not m:
            probs.append("carrier lost: '%s'" % text)
        return probs
    want = INLINE.sub(lambda x: x.group(1), it.get("spoken", it["text"]))
    got = words(text)
    if LETTERS.search(text.replace("AI", "").replace("I ", " ")):
        probs.append("spelled out in: '%s'" % text)
    miss = []
    for w in words(want):
        if len(w) < 3 or w in ("the", "and", "you", "for", "she", "her", "was", "are", "that"):
            continue
        if not difflib.get_close_matches(w, got, n=1, cutoff=0.6):
            miss.append(w)
    if len(miss) >= 2 or (miss and len(words(want)) <= 4):
        probs.append("missing or garbled: %s (heard '%s')" % (miss, text))
    return probs


report = []
n = {"before": 0, "after": 0}
for it in items:
    row = {"id": it["id"], "kind": it["kind"], "key": it["key"]}
    for mode in ("before", "after"):
        t = heard(it[mode])
        p = judge(it, mode, t)
        row[mode] = {"heard": t, "problems": p}
        if p:
            n[mode] += 1
    report.append(row)
json.dump(report, open(os.path.join(d, "report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("[ttscheck] flagged BEFORE %d / %d, AFTER %d / %d" % (n["before"], len(items), n["after"], len(items)))
for r in report:
    if r["after"]["problems"]:
        print("[ttscheck] AFTER %s %r: %s" % (r["id"], r["key"], "; ".join(r["after"]["problems"])))
