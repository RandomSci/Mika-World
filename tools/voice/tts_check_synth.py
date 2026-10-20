"""TTS pronunciation check, step 1 (run with the Kokoro venv's python): every dictionary entry (in a short carrier
sentence) and the sample chat lines, spoken BEFORE (raw text into Kokoro, as until now) and AFTER (tts_text cleanup),
as WAVs plus a manifest for step 2 (tts_check_whisper.py).
  <kokoro python> tools/voice/tts_check_synth.py <out dir> [voice]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kokoro_service  # noqa: E402
import tts_text  # noqa: E402

out = sys.argv[1]
voice = sys.argv[2] if len(sys.argv) > 2 else "af_heart:0.6,jf_alpha:0.4"
os.makedirs(out, exist_ok=True)
models = "/home/selwyn/Documents/Mika-Live/models/kokoro"
eng = kokoro_service.Engine(os.path.join(models, "kokoro-v1.0.onnx"), os.path.join(models, "voices-v1.0.bin"), 4, "af_heart")

d = tts_text._load()
items = []
for k in list(d["words"].keys()) + list(d["names"].keys()):
    if d["words"].get(k.lower(), None) == "":
        continue
    items.append({"id": "dict_%d" % len(items), "kind": "dict", "key": k, "text": "She said %s again." % k})
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "tts_chat_samples.txt"), encoding="utf-8") as fh:
    for i, line in enumerate(l.strip() for l in fh if l.strip()):
        items.append({"id": "chat_%02d" % i, "kind": "chat", "key": line, "text": line})

for it in items:
    for mode in ("before", "after"):
        path = os.path.join(out, "%s_%s.wav" % (it["id"], mode))
        if mode == "before":
            # the old path: the raw line straight into Kokoro
            audio, rate = eng.kokoro.create(it["text"], voice=eng.style(voice), speed=1.0, lang="en-us")
            import soundfile as sf
            sf.write(path, audio, rate, subtype="PCM_16")
        else:
            wav, _, _ = eng.synthesize(it["text"], voice, "en-us", 1.0)
            with open(path, "wb") as fh:
                fh.write(wav)
            it["spoken"] = tts_text.normalize(it["text"])
        it[mode] = path
with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as fh:
    json.dump(items, fh, ensure_ascii=False, indent=1)
print("[ttscheck] %d items, before and after, in %s" % (len(items), out))
