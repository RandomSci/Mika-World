"""Word error rate of each candidate voice (SenseVoice, local) + LPC formants."""
import glob, json, os, re, sys
import numpy as np, soundfile as sf, sherpa_onnx
sys.path.insert(0, os.path.dirname(__file__))
from voice_compare import LINES
MODEL = '/home/selwyn/Documents/Open-LLM-VTuber/models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17'
rec = sherpa_onnx.OfflineRecognizer.from_sense_voice(model=MODEL + '/model.int8.onnx', tokens=MODEL + '/tokens.txt', language='en', use_itn=True, num_threads=4)
norm = lambda t: re.sub(r"[^a-z' ]", ' ', t.lower()).split()

def wer(ref, hyp):
    r, h = norm(ref), norm(hyp); d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1])); prev, d[j] = d[j], cur
    return d[len(h)] / max(1, len(r))

def formants(x, sr):
    from scipy.signal import resample_poly, lfilter
    y = resample_poly(x, 10000, sr); f1s, f2s = [], []
    for s in range(0, len(y) - 300, 150):
        fr = y[s:s + 300] * np.hamming(300)
        if np.sqrt((fr ** 2).mean()) < .02: continue
        fr = lfilter([1, -.63], 1, fr); a = np.correlate(fr, fr, 'full')[299:299 + 13]
        R = np.array([[a[abs(i - j)] for j in range(12)] for i in range(12)])
        try: c = np.linalg.solve(R + 1e-6 * np.eye(12), -a[1:13])
        except Exception: continue
        roots = [r for r in np.roots(np.r_[1, c]) if np.imag(r) > 0]
        fs = sorted(np.angle(roots) * 10000 / (2 * np.pi)); fs = [f for f in fs if 200 < f < 4000]
        if len(fs) >= 2: f1s.append(fs[0]); f2s.append(fs[1])
    return round(float(np.median(f1s))), round(float(np.median(f2s)))

out = {}
for spec in sorted({os.path.basename(p).rsplit('-', 1)[0] for p in glob.glob('review/voice-upgrade/*-greeting.wav')}):
    errs, hyps, f = [], {}, []
    for name, text in LINES.items():
        x, sr = sf.read(f'review/voice-upgrade/{spec}-{name}.wav'); s = rec.create_stream(); s.accept_waveform(sr, x.astype(np.float32)); rec.decode_stream(s)
        hyps[name] = s.result.text
        if name != 'incantation': errs.append(wer(text, s.result.text)); f.append(formants(x, sr))
    out[spec] = {'wer_percent': round(100 * np.mean(errs), 1), 'f1_hz': int(np.median([a for a, _ in f])), 'f2_hz': int(np.median([b for _, b in f])), 'incantation_heard_as': hyps['incantation'], 'joke_heard_as': hyps['joke']}
    print(spec, out[spec], flush=True)
json.dump(out, open('review/voice-upgrade/intelligibility.json', 'w'), indent=1)
