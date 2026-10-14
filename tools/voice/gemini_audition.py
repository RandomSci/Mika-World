#!/usr/bin/env python3
"""Voice auditions for Mika and Luna (the directive: Mika = Gemini "Leda" +15 %, Luna = Gemini "Achernar" +15 %; NOT
approved yet - these files are for the developer to listen to; production voices are untouched).

For each character and each of five deliveries (casual, excitement, surprise, concern, magic casting):
  1_original     the voice with no direction
  2_pitch15      (1) shifted up 15 % (2.42 semitones) with formant preservation (ffmpeg rubberband, formant=preserved):
                 higher, younger, but NOT sped up and without the chipmunk timbre of a resample
  3_directed     the voice re-synthesised with a per-line delivery style (speech_metadata.style) written for her
  4_best         (3) + a gentler formant-preserving lift (+8 %), a light presence EQ, de-harsh and loudness match
  5_alt_<Voice>  other youthful prebuilt voices with the same direction
Writes WAVs + an index (auditions.json) + a side-by-side listening order to <out>. The key is read from the project
.env (GEMINI_API_KEY only) and never printed. Results are cached by hash, so re-runs cost nothing.

  python3 tools/voice/gemini_audition.py [--out assets/voice/auditions] [--only mika|luna] [--dry]
"""
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "voice", "auditions")
CACHE = os.path.expanduser("~/.cache/mika_voice_auditions")
MODEL = "gemini-3.8-flash-tts"
FALLBACK_MODEL = "gemini-2.5-flash-preview-tts"

CAST = {
	"mika": {
		"voice": "Leda",
		"alts": ["Zephyr", "Autonoe", "Laomedeia"],
		"persona": "a young girl of about sixteen, a cheerful apprentice mage: bright, gentle, playful and warm, natural youthful voice",
		"lines": {
			"casual": ("Morning, Luna! I saved you the last honey bun... well, half of it. Okay, a third.", "relaxed, playful and warm, smiling while she talks, easy natural pace"),
			"excitement": ("Did you see that? The whole pond lit up! I actually did it!", "bursting with excitement, breathless and delighted, bright and quick"),
			"surprise": ("Whoa! Where did that come from?", "genuinely startled, a quick gasp at the start, high and sudden"),
			"concern": ("Luna... are you hurt? Here, take my hand. Slowly.", "soft and worried, gentle and caring, a little shaky, slower"),
			"magic": ("Light of the dawn, gather in my hands... Radiant Bloom!", "focused and determined, building from a hushed incantation to a confident cry"),
		},
	},
	"luna": {
		"voice": "Achernar",
		"alts": ["Vindemiatrix", "Aoede", "Despina"],
		"persona": "a young girl of about sixteen, a quiet, clever moon mage: soft, calm, curious and a little mysterious, sometimes teasing",
		"lines": {
			"casual": ("Mm. The library smells like rain today. I think I'll stay a while.", "calm, soft and dreamy, unhurried, a faint smile in the voice"),
			"excitement": ("Mika, look. The runes answered me. They actually answered.", "quietly thrilled, wonder breaking through her usual calm, a little faster"),
			"surprise": ("Ah! You startled me... don't do that.", "a small surprised gasp, then softly embarrassed and a little cross"),
			"concern": ("Stay still. You fell hard... let me look at it.", "low, gentle and worried, careful and tender, slow"),
			"magic": ("Shadows of the quiet moon, bind and hold.", "hushed and mysterious, steady and controlled, an incantation with quiet power"),
		},
	},
}


def key():
	k = os.environ.get("GEMINI_API_KEY", "")
	if not k:
		for line in open(os.path.join(ROOT, ".env")):
			if line.startswith("GEMINI_API_KEY="):
				k = line.split("=", 1)[1].strip().strip('"').strip("'")
	if not k:
		sys.exit("GEMINI_API_KEY not configured")
	return k


def _post(url, body, k):
	req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "x-goog-api-key": k})
	with urllib.request.urlopen(req, timeout=90) as r:
		return json.loads(r.read())


def pcm_to_wav(pcm, rate=24000):
	import struct
	n = len(pcm)
	return b"RIFF" + struct.pack("<I", 36 + n) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16) + b"data" + struct.pack("<I", n) + pcm


def synth(voice, text, style, k, log):
	h = hashlib.sha1(("%s|%s|%s|%s" % (MODEL, voice, style, text)).encode()).hexdigest()
	cp = os.path.join(CACHE, h + ".wav")
	if os.path.exists(cp):
		return open(cp, "rb").read(), "cache"
	content = {"type": "text", "text": text}
	if style:
		content["annotations"] = [{"type": "speech_metadata", "style": style}]
	body = {"model": MODEL, "input": [{"type": "user_input", "content": [content]}], "response_format": {"type": "audio"},
		"generation_config": {"speech_config": [{"voice": voice}]}}
	for attempt in range(4):
		try:
			r = _post("https://generativelanguage.googleapis.com/v1beta/interactions", body, k)
			data = None
			for st in r.get("steps", []):
				if st.get("type") == "model_output":
					for c in st.get("content", []):
						if c.get("type") == "audio":
							data = c.get("data")
			if not data:
				raise RuntimeError("no audio in response: " + json.dumps(r)[:300])
			wav = base64.b64decode(data)
			if not wav.startswith(b"RIFF"):
				wav = pcm_to_wav(wav)
			src = MODEL
			break
		except urllib.error.HTTPError as e:
			msg = e.read().decode(errors="replace")[:300]
			log.append({"voice": voice, "http": e.code, "msg": msg})
			if e.code == 429:
				time.sleep(30 * (attempt + 1))
				continue
			if e.code in (400, 404) and attempt == 0:
				# the interactions API / model not available to this key: the generateContent shape Oriel already uses
				prompt = text if not style else "Say this %s: %s" % (style, text)
				b2 = {"contents": [{"parts": [{"text": prompt}]}], "generationConfig": {"responseModalities": ["AUDIO"],
					"speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}}}}
				try:
					r = _post("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % FALLBACK_MODEL, b2, k)
					part = r["candidates"][0]["content"]["parts"][0]["inlineData"]
					wav = pcm_to_wav(base64.b64decode(part["data"]))
					src = FALLBACK_MODEL
					break
				except urllib.error.HTTPError as e2:
					log.append({"voice": voice, "fallback_http": e2.code, "msg": e2.read().decode(errors="replace")[:300]})
					raise
			raise
	else:
		raise RuntimeError("rate limited")
	os.makedirs(CACHE, exist_ok=True)
	open(cp, "wb").write(wav)
	time.sleep(4)
	return wav, src


def ff(src, dst, af):
	subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-af", af, "-ar", "24000", "-ac", "1", "-c:a", "pcm_s16le", dst], check=True)


LOUD = "loudnorm=I=-18:TP=-1.5:LRA=9"
PITCH15 = "rubberband=pitch=1.15:formant=preserved:pitchq=quality:transients=smooth"
BEST = ("rubberband=pitch=1.08:formant=preserved:pitchq=quality:transients=smooth,highpass=f=90,"
	"equalizer=f=250:t=q:w=1.0:g=-2,equalizer=f=3200:t=q:w=1.2:g=2.5,equalizer=f=7500:t=q:w=2:g=-1.5,"
	"acompressor=threshold=-20dB:ratio=2.2:attack=8:release=120:makeup=1.5," + LOUD)


def main():
	args = sys.argv[1:]
	out = args[args.index("--out") + 1] if "--out" in args else OUT
	only = args[args.index("--only") + 1] if "--only" in args else ""
	k = key()
	os.makedirs(out, exist_ok=True)
	index = {"model": MODEL, "note": "Auditions only - production voices unchanged. Listening order per line: 1 -> 2 -> 3 -> 4 -> alts.", "characters": {}}
	log = []
	for who, c in CAST.items():
		if only and who != only:
			continue
		d = os.path.join(out, who)
		os.makedirs(d, exist_ok=True)
		entry = {"voice": c["voice"], "persona": c["persona"], "files": {}}
		for kind, (text, mood) in c["lines"].items():
			style = "%s; %s" % (c["persona"], mood)
			files = {}
			raw, src = synth(c["voice"], text, "", k, log)
			p1 = os.path.join(d, "%s_1_original.wav" % kind)
			tmp = p1 + ".raw.wav"
			open(tmp, "wb").write(raw)
			ff(tmp, p1, LOUD)
			ff(tmp, os.path.join(d, "%s_2_pitch15.wav" % kind), PITCH15 + "," + LOUD)
			os.remove(tmp)
			raw3, src3 = synth(c["voice"], text, style, k, log)
			p3 = os.path.join(d, "%s_3_directed.wav" % kind)
			tmp = p3 + ".raw.wav"
			open(tmp, "wb").write(raw3)
			ff(tmp, p3, LOUD)
			ff(tmp, os.path.join(d, "%s_4_best.wav" % kind), BEST)
			ff(tmp, os.path.join(d, "%s_3b_directed_pitch15.wav" % kind), PITCH15 + "," + LOUD)
			os.remove(tmp)
			files.update({"text": text, "style": style})
			for alt in c["alts"]:
				ra, _ = synth(alt, text, style, k, log)
				pa = os.path.join(d, "%s_5_alt_%s.wav" % (kind, alt))
				tmp = pa + ".raw.wav"
				open(tmp, "wb").write(ra)
				ff(tmp, pa, LOUD)
				os.remove(tmp)
			entry["files"][kind] = files
			print("%s %s done (%s)" % (who, kind, src3), flush=True)
		index["characters"][who] = entry
	index["processing"] = {"pitch15": PITCH15, "best": BEST, "loudness": LOUD}
	index["errors"] = log
	json.dump(index, open(os.path.join(out, "auditions.json"), "w"), indent=1)


if __name__ == "__main__":
	main()
