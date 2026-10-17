"""Matched samples and objective measurements for candidate Kokoro voices."""
import json, os, sys, time
import numpy as np, soundfile as sf
sys.path.insert(0, os.path.dirname(__file__))

M = os.path.join(os.path.dirname(__file__), '..', '..', 'models', 'kokoro')
LINES = {
    'greeting': "Hi everyone! I'm Mika. Okay, you caught me right as I was about to go practise magic.",
    'joke': "Wait, haven't I walked past this exact bush like five times already? It's following me.",
    'incantation': "Orbis lucis.",
    'coding': "Oh no, it ran, but the button does absolutely nothing. Classic me. Let me check the click handler.",
    'long': "I finally passed the first spell lesson, so now the book wants me to hold a floating orb between my hands, which sounds easy until you actually try it.",
}

def style(k, spec):
    if ':' not in spec:
        return spec
    parts = [p.split(':') for p in spec.split(',')]
    return sum(float(w) * k.get_voice_style(v) for v, w in parts)

def main(out, voices):
    from kokoro_onnx import Kokoro
    from compare import features  # F0 median / IQR from the same estimator
    k = Kokoro(os.path.join(M, 'kokoro-v1.0.onnx'), os.path.join(M, 'voices-v1.0.bin'))
    k.create('Hello.', voice='af_heart', speed=1.0, lang='en-us')
    rows = {}
    for spec in voices:
        allaudio, gen, dur = [], 0.0, 0.0
        for name, text in LINES.items():
            t = time.perf_counter(); audio, sr = k.create(text, voice=style(k, spec), speed=1.0, lang='en-us'); g = time.perf_counter() - t
            gen += g; dur += len(audio) / sr; allaudio.append(audio)
            sf.write(os.path.join(out, f"{spec.replace(':', '').replace(',', '+')}-{name}.wav"), audio, sr)
        a = np.concatenate(allaudio); f = features(a, sr)
        words = sum(len(t.split()) for t in LINES.values())
        rows[spec] = {'f0_median_hz': round(f['f0_median'], 1), 'f0_iqr_hz': round(f['f0_iqr'], 1),
                      'words_per_minute': round(words / dur * 60), 'rtf': round(gen / dur, 3),
                      'peak_dbfs': round(20 * np.log10(np.abs(a).max()), 1), 'rms_db': round(20 * np.log10(np.sqrt((a ** 2).mean())), 1),
                      'spectral_centroid_hz': round(float((np.abs(np.fft.rfft(a)) * np.fft.rfftfreq(len(a), 1 / sr)).sum() / np.abs(np.fft.rfft(a)).sum()))}
        print(spec, rows[spec], flush=True)
    json.dump(rows, open(os.path.join(out, 'voice-measurements.json'), 'w'), indent=1, default=float)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2].split(';'))
