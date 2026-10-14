#!/usr/bin/env python3
"""Mika's and Luna's voice IDENTITIES (data/voices.json, provider "gemini_identity"; docs/VOICES.md).

One voice per character: every clip is made with the identity's model, prebuilt voice, persona + one of its fixed
moods, then the identity's processing chain (formant-preserving +15 % pitch, loudness). The cache key is exactly the
one VoiceService computes at runtime - sha1("<identity>|<persona>; <mood text>|<text>") - so a shipped clip is found
by the game without a network call.

  python3 tools/voice/voice_identity.py ship [--only mika|luna] [--dry]     pre-render the fixed lines
  python3 tools/voice/voice_identity.py say mika "Hello there" [--mood happy] [--out file.wav]

Shipped set (assets/voice/<speaker>/<key>.wav + manifest.json): reaction clips (laugh, gasp, cry, effort ...), every
Latin incantation (data/pronunciations.json), aftermath lines (data/impacts.json), Phoenix bystander lines
(data/phoenix.json). The key comes from the project .env (GEMINI_API_KEY only) and is never printed. Rendered raw
audio is cached in ~/.cache/mika_voice_identity, so a re-run makes no repeated calls.
"""
import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW_CACHE = os.path.expanduser("~/.cache/mika_voice_identity")
SPACING_S = 4.0


def cfg_all():
	return json.load(open(os.path.join(ROOT, "data", "voices.json"), encoding="utf-8"))


def clean(t):
	"""VoiceService.clean(): no em/en dashes in spoken dialogue."""
	s = t.replace(" — ", ", ").replace("—", ", ").replace(" – ", ", ").replace("–", "-")
	return s.replace(",,", ",").strip()


def style(cfg, mood):
	moods = cfg.get("moods", {})
	return "%s; %s" % (cfg.get("persona", ""), moods.get(mood, moods.get("neutral", "")))


def key(cfg, sty, text):
	return hashlib.sha1(("%s|%s|%s" % (cfg["identity"], sty, text)).encode("utf-8")).hexdigest()


def api_key():
	k = os.environ.get("GEMINI_API_KEY", "")
	if not k:
		for line in open(os.path.join(ROOT, ".env")):
			if line.startswith("GEMINI_API_KEY="):
				k = line.split("=", 1)[1].strip().strip('"').strip("'")
	if not k:
		sys.exit("GEMINI_API_KEY not configured")
	return k


def pcm_to_wav(pcm, rate=24000):
	import struct
	n = len(pcm)
	return b"RIFF" + struct.pack("<I", 36 + n) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16) + b"data" + struct.pack("<I", n) + pcm


def _post(url, body, k):
	req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "x-goog-api-key": k})
	with urllib.request.urlopen(req, timeout=90) as r:
		return json.loads(r.read())


def synth_raw(cfg, text, sty, k):
	"""Unprocessed audio for (identity, style, text), cached on disk. Returns (wav bytes, source)."""
	h = hashlib.sha1(("%s|%s|%s|%s" % (cfg["model"], cfg["voice"], sty, text)).encode("utf-8")).hexdigest()
	cp = os.path.join(RAW_CACHE, h + ".wav")
	if os.path.exists(cp):
		return open(cp, "rb").read(), "cache"
	body = {"model": cfg["model"], "input": [{"type": "user_input", "content": [{"type": "text", "text": text,
		"annotations": [{"type": "speech_metadata", "style": sty}]}]}], "response_format": {"type": "audio"},
		"generation_config": {"speech_config": [{"voice": cfg["voice"]}]}}
	for attempt in range(5):
		try:
			r = _post("https://generativelanguage.googleapis.com/v1beta/interactions", body, k)
			data = None
			for st in r.get("steps", []):
				if st.get("type") == "model_output":
					for c in st.get("content", []):
						if c.get("type") == "audio":
							data = c.get("data")
			if not data:
				raise RuntimeError("no audio in the answer")
			wav = base64.b64decode(data)
			if not wav.startswith(b"RIFF"):
				wav = pcm_to_wav(wav)
			break
		except urllib.error.HTTPError as e:
			if e.code == 429:
				body_txt = e.read().decode(errors="replace")
				if "per day" in body_txt and cfg.get("alt_model"):
					return synth_alt(cfg, text, sty, k, cp)
				wait = 40 * (attempt + 1)
				print("  quota (429): waiting %d s" % wait, flush=True)
				time.sleep(wait)
				continue
			if e.code >= 500:
				time.sleep(5)
				continue
			raise RuntimeError("http %d: %s" % (e.code, e.read().decode(errors="replace")[:200]))
	else:
		raise RuntimeError("gave up after repeated quota answers")
	os.makedirs(RAW_CACHE, exist_ok=True)
	open(cp, "wb").write(wav)
	time.sleep(SPACING_S)
	return wav, "new"


def synth_alt(cfg, text, sty, k, cp):
	"""The same prebuilt voice on the identity's second model (generateContent), when the first is out of daily quota."""
	body = {"contents": [{"parts": [{"text": "Say this %s: %s" % (sty, text)}]}], "generationConfig": {"responseModalities": ["AUDIO"],
		"speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": cfg["voice"]}}}}}
	r = _post("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % cfg["alt_model"], body, k)
	part = r["candidates"][0]["content"]["parts"][0]["inlineData"]
	wav = pcm_to_wav(base64.b64decode(part["data"]))
	os.makedirs(RAW_CACHE, exist_ok=True)
	open(cp, "wb").write(wav)
	time.sleep(SPACING_S)
	return wav, "alt"


def process(cfg, raw, model=None):
	"""The identity's chain, with the per-model pitch factor (both models must land on the same voice)."""
	model = model or cfg["model"]
	filt = cfg["post"].replace("{pitch}", "%.3f" % float(cfg.get("pitch", {}).get(model, 1.15)))
	with tempfile.TemporaryDirectory() as d:
		i, o = os.path.join(d, "in.wav"), os.path.join(d, "out.wav")
		open(i, "wb").write(raw)
		subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", i, "-af", filt, "-ar", "24000", "-ac", "1", "-c:a", "pcm_s16le", o], check=True)
		return open(o, "rb").read()


def fixed_lines(speaker, allcfg):
	"""(text, mood, why) for every line this speaker says with a known text and mood."""
	out = []
	for kind, per in allcfg.get("reactions", {}).get("clips", {}).items():
		if isinstance(per, dict) and speaker in per:
			out.append((per[speaker], kind, "reaction:" + kind))      # react(): raw text, mood = kind
	for latin in json.load(open(os.path.join(ROOT, "data", "pronunciations.json"), encoding="utf-8")).get("lines", {}):
		out.append((clean(latin), "latin", "incantation"))
	imp = json.load(open(os.path.join(ROOT, "data", "impacts.json"), encoding="utf-8")).get("lines", {}).get(speaker, {})
	for k, pool in imp.items():
		if isinstance(pool, list):
			for t in pool:
				out.append((clean(t), "urgent" if k.startswith("warn_") else "concerned", "impact:" + k))
	# the ambush exchanges (data/ambush.json): [speaker, text, mood] lines and the fight barks (mood "determined")
	amb = json.load(open(os.path.join(ROOT, "data", "ambush.json"), encoding="utf-8"))
	for bid, band in amb.get("bands", {}).items():
		for phase, lines in band.items():
			if isinstance(lines, list):
				for ln in lines:
					if isinstance(ln, list) and len(ln) >= 2 and ln[0] == speaker:
						out.append((clean(ln[1]), ln[2] if len(ln) > 2 and ln[2] else "neutral", "ambush:%s:%s" % (bid, phase)))
		for t in band.get("barks", {}).get(speaker, []):
			out.append((clean(t), "determined", "ambush:%s:bark" % bid))
	# her own line pools that carry a fixed mood (data/voices.json line_moods; SanctuaryBrain._maybe_say)
	pools = json.load(open(os.path.join(ROOT, "data", "mages.json"), encoding="utf-8")).get("mages", {}).get(speaker, {}).get("lines", {})
	for k, mood in allcfg.get("line_moods", {}).items():
		if k.startswith("_"):
			continue
		for t in pools.get(k, []):
			if "{" not in t:
				out.append((clean(t), mood, "mage_line:" + k))
	ph = json.load(open(os.path.join(ROOT, "data", "phoenix.json"), encoding="utf-8")).get("bystander_lines", {}).get(speaker, {})
	for k, pool in ph.items():
		for t in pool:
			out.append((clean(t), "surprised", "phoenix:" + k))
	return out


def ship(only="", dry=False):
	allcfg = cfg_all()
	k = None if dry else api_key()
	for speaker, cfg in allcfg["speakers"].items():
		if cfg.get("provider") != "gemini_identity" or (only and speaker != only):
			continue
		d = os.path.join(ROOT, "assets", "voice", speaker)
		os.makedirs(d, exist_ok=True)
		mp = os.path.join(d, "manifest.json")
		manifest = json.load(open(mp)) if os.path.exists(mp) else {}
		if manifest.get("identity") != cfg["identity"]:
			manifest = {"identity": cfg["identity"], "lines": {}}
		lines = fixed_lines(speaker, allcfg)
		print("%s (%s): %d fixed lines" % (speaker, cfg["identity"], len(lines)), flush=True)
		for text, mood, why in lines:
			sty = style(cfg, mood)
			kk = key(cfg, sty, text)
			path = os.path.join(d, kk + ".wav")
			if os.path.exists(path):
				continue
			if dry:
				print("  would render", mood, text)
				continue
			wav = None
			for attempt in range(3):
				try:
					raw, src = synth_raw(cfg, text, sty, k)
					wav = process(cfg, raw, cfg.get("alt_model") if src == "alt" else cfg["model"])
				except Exception as e:      # recorded, the rest continue; the game renders a missing line on demand
					print("  FAILED %s %r: %s" % (mood, text, e), flush=True)
					wav = None
					break
				# a TTS model sometimes runs on (a 2 s line returned as 100 s of babble): reject and render again
				secs = (len(wav) - 44) / (2.0 * 24000)
				if secs <= max(5.0, 0.12 * len(text) + 3.0):
					break
				print("  rejected %.1f s for %r: rendering again" % (secs, text), flush=True)
				h = hashlib.sha1(("%s|%s|%s|%s" % (cfg["model"], cfg["voice"], sty, text)).encode("utf-8")).hexdigest()
				try:
					os.remove(os.path.join(RAW_CACHE, h + ".wav"))
				except OSError:
					pass
				wav = None
			if wav is None:
				continue
			open(path, "wb").write(wav)
			manifest["lines"][kk] = {"text": text, "mood": mood, "why": why, "model": cfg.get("alt_model") if src == "alt" else cfg["model"]}
			json.dump(manifest, open(mp, "w"), indent=1, ensure_ascii=False)
			print("  %s %-10s %s" % (src, mood, text), flush=True)
		json.dump(manifest, open(mp, "w"), indent=1, ensure_ascii=False)


def reprocess(alt_texts):
	"""Re-run the processing chain on every shipped clip from the raw cache (no API calls) - after a calibration
	change. alt_texts: {(speaker, mood, text)} rendered on the alt model (older manifests did not record it)."""
	allcfg = cfg_all()
	for speaker, cfg in allcfg["speakers"].items():
		if cfg.get("provider") != "gemini_identity":
			continue
		d = os.path.join(ROOT, "assets", "voice", speaker)
		mp = os.path.join(d, "manifest.json")
		if not os.path.exists(mp):
			continue
		man = json.load(open(mp))
		n = 0
		for kk, e in man["lines"].items():
			sty = style(cfg, e["mood"])
			h = hashlib.sha1(("%s|%s|%s|%s" % (cfg["model"], cfg["voice"], sty, e["text"])).encode("utf-8")).hexdigest()
			cp = os.path.join(RAW_CACHE, h + ".wav")
			if not os.path.exists(cp):
				print("  no raw for", e["text"])
				continue
			model = e.get("model") or (cfg["alt_model"] if (speaker, e["mood"], e["text"]) in alt_texts else cfg["model"])
			e["model"] = model
			open(os.path.join(d, kk + ".wav"), "wb").write(process(cfg, open(cp, "rb").read(), model))
			n += 1
		json.dump(man, open(mp, "w"), indent=1, ensure_ascii=False)
		print(speaker, "reprocessed", n)


def main():
	a = sys.argv[1:]
	if a and a[0] == "reprocess":
		alt = set()
		if "--alt-log" in a:
			for ln in open(a[a.index("--alt-log") + 1]):
				pass
		reprocess(alt)
		return
	if not a or a[0] not in ("ship", "say"):
		sys.exit(__doc__)
	if a[0] == "ship":
		ship(a[a.index("--only") + 1] if "--only" in a else "", "--dry" in a)
		return
	allcfg = cfg_all()
	cfg = allcfg["speakers"][a[1]]
	text = clean(a[2])
	mood = a[a.index("--mood") + 1] if "--mood" in a else "neutral"
	out = a[a.index("--out") + 1] if "--out" in a else os.path.join(tempfile.gettempdir(), "voice_identity_say.wav")
	raw, _ = synth_raw(cfg, text, style(cfg, mood), api_key())
	open(out, "wb").write(process(cfg, raw))
	print(out)


if __name__ == "__main__":
	main()
