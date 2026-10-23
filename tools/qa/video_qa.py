#!/usr/bin/env python3
"""Video quality check for every recording made for Selwyn's review (24 Oct: "create a subsystem to check the videos
you created and its goal is quality"). Two sources, one verdict:

  * the picture itself (ffmpeg at 10 fps, 96x54 grey): black or near-black stretches, white-outs (a flash or a glowing
    thing filling the frame), frozen stretches, and long silences in the sound;
  * the game's own shot audit (scripts/qa/shot_audit.gd, --shot-audit=<csv>): Mika cut off (head or feet out of the
    picture), too close (not head to feet: her face too big), hidden behind something solid, the lens inside a
    keep-out, while the area is really on screen (the travel card is left out).

Writes <video>.qa.txt (issues with their times, a score, PASS or FAIL) and <video>.qa.jpg (a still of each issue).
  python3 tools/qa/video_qa.py <video.mp4> [shot_audit.csv] [--fps 30]
Exit 0 = PASS, 1 = FAIL, 2 = could not read the video.
"""
import csv, os, subprocess, sys

W, H, RATE = 96, 54, 10
# thresholds (the whole-body rule: at the follow lens's 4 m the face fraction is about 0.05; chest-up is 0.09 and up)
CLOSE_FACE = 0.075
RULES = {  # kind: (minimum run in s to count, major?)
    "cut off": (1.0, True), "too close": (0.6, True), "hidden": (1.0, True), "lens in a keep-out": (0.1, True),
    "black": (0.5, True), "white-out": (0.5, False), "frozen": (4.0, True), "silent": (25.0, False),
}


def frames(video):
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-i", video, "-vf", f"fps={RATE},scale={W}:{H}", "-f", "rawvideo",
                          "-pix_fmt", "gray", "-"], stdout=subprocess.PIPE)
    n = W * H
    while True:
        b = p.stdout.read(n)
        if len(b) < n:
            break
        yield b
    p.wait()


def runs(flags, step):
    """[(start_s, end_s)] of consecutive True samples."""
    out, start = [], None
    for i, f in enumerate(flags + [False]):
        if f and start is None:
            start = i
        elif not f and start is not None:
            out.append((start * step, i * step))
            start = None
    return out


def audio_silence(video):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-i", video, "-af", "silencedetect=n=-45dB:d=8", "-f", "null", "-"],
                       capture_output=True, text=True)
    out, st = [], None
    for line in r.stderr.splitlines():
        if "silence_start:" in line:
            st = float(line.split("silence_start:")[1].split()[0])
        elif "silence_end:" in line and st is not None:
            out.append((st, float(line.split("silence_end:")[1].split()[0])))
            st = None
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    fps = 30.0
    if "--fps" in sys.argv:
        fps = float(sys.argv[sys.argv.index("--fps") + 1])
    if not args or not os.path.exists(args[0]):
        print(__doc__)
        return 2
    video = args[0]
    audit = args[1] if len(args) > 1 and os.path.exists(args[1]) else ""
    lum, bright, dark, diff = [], [], [], []
    prev = None
    for b in frames(video):
        m = sum(b) / len(b)
        lum.append(m)
        bright.append(sum(1 for v in b if v > 240) / len(b))
        dark.append(m < 14)
        diff.append(0.0 if prev is None else sum(abs(x - y) for x, y in zip(b, prev)) / len(b))
        prev = b
    if not lum:
        print("could not read", video)
        return 2
    dur = len(lum) / RATE
    step = 1.0 / RATE

    # the game's audit: when the area is really on screen (not the travel card), per 0.1 s sample
    on_screen = [True] * len(lum)
    issues = []
    if audit:
        rows = list(csv.DictReader(open(audit)))
        by_t = {}
        for r in rows:
            t = int(r["frame"]) / fps
            i = int(round(t * RATE))
            if 0 <= i < len(lum):
                by_t[i] = r
        for i in range(len(lum)):
            r = by_t.get(i)
            if r is not None:
                on_screen[i] = r["streaming"] == "idle" and r["mika_in"] == "1"
        def flag(fn):
            return [(by_t.get(i) is not None and on_screen[i] and fn(by_t[i])) for i in range(len(lum))]
        checks = {
            "cut off": flag(lambda r: r["head_in"] == "0" or r["feet_in"] == "0"),
            "too close": flag(lambda r: float(r["face_frac"]) > CLOSE_FACE),
            "hidden": flag(lambda r: r["hidden"] == "1"),
            "lens in a keep-out": flag(lambda r: r["in_keepout"] == "1"),
        }
        for kind, fl in checks.items():
            for a, b in runs(fl, step):
                if b - a >= RULES[kind][0]:
                    issues.append((kind, a, b))
    # the picture
    pic = {
        "black": [dark[i] and on_screen[i] for i in range(len(lum))],
        "white-out": [bright[i] > 0.45 for i in range(len(lum))],
        "frozen": [i > 0 and diff[i] < 0.3 and on_screen[i] for i in range(len(lum))],
    }
    for kind, fl in pic.items():
        for a, b in runs(fl, step):
            # (a test scene idles a few seconds before it quits: not stream content)
            if kind == "frozen" and a > dur - 8.0:
                continue
            if b - a >= RULES[kind][0]:
                issues.append((kind, a, b))
    for a, b in audio_silence(video):
        if b - a >= RULES["silent"][0]:
            issues.append(("silent", a, b))
    issues.sort(key=lambda x: x[1])

    major = [x for x in issues if RULES[x[0]][1]]
    bad_s = sum(b - a for k, a, b in major)
    score = max(0, round(100 - 100 * bad_s / max(dur, 1) * 3 - 2 * len(major) - 0.5 * (len(issues) - len(major))))
    verdict = "PASS" if not major else "FAIL"
    lines = [f"Quality check of {os.path.basename(video)}", f"length {dur:.0f} s, shot audit {'yes' if audit else 'no (picture only)'}",
             f"verdict {verdict}, score {score} of 100, {len(major)} major and {len(issues) - len(major)} minor issues", ""]
    for k, a, b in issues:
        lines.append(f"{'MAJOR' if RULES[k][1] else 'minor'}  {k:<20} {int(a // 60)}:{a % 60:04.1f} to {int(b // 60)}:{b % 60:04.1f}  ({b - a:.1f} s)")
    if not issues:
        lines.append("no issues found")
    rep = os.path.splitext(video)[0] + ".qa.txt"
    open(rep, "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    # a still of each issue (its middle), tiled
    try:
        from PIL import Image, ImageDraw
        tiles = []
        tmp = os.path.splitext(video)[0] + ".qa_tmp.jpg"
        for k, a, b in issues[:24]:
            mid = (a + b) / 2
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{mid:.2f}", "-i", video, "-frames:v", "1", "-vf", "scale=480:-1", tmp])
            if os.path.exists(tmp):
                im = Image.open(tmp).convert("RGB")
                d = ImageDraw.Draw(im)
                d.rectangle((0, 0, im.width, 20), fill=(0, 0, 0))
                d.text((6, 4), f"{k} at {int(mid // 60)}:{mid % 60:04.1f}", fill=(255, 220, 0))
                tiles.append(im)
                os.remove(tmp)
        if tiles:
            cols = 4
            w, h = tiles[0].size
            sheet = Image.new("RGB", (w * cols, h * ((len(tiles) + cols - 1) // cols)))
            for i, im in enumerate(tiles):
                sheet.paste(im.resize((w, h)), ((i % cols) * w, (i // cols) * h))
            sheet.save(os.path.splitext(video)[0] + ".qa.jpg", quality=82)
    except ImportError:
        pass
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
