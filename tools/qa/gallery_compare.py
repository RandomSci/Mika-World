#!/usr/bin/env python3
"""Before and after of the spell gallery (magic_lab renders), side by side at 10 fps, same camera.

usage: gallery_compare.py BEFORE_DIR AFTER_DIR OUT_DIR [--fps 10]
Each dir holds lab.mp4 and log.txt from lab_render.sh magic_lab. For every spell cast in AFTER, the window from its
cast frame to its end frame (+0.6 s) is cut from both renders (by the spell's own frame numbers in each log, so the
same moment of the same cast lines up), scaled, stacked before | after, and written as
  OUT_DIR/compare_<spell>.mp4      the pair at 10 fps
  OUT_DIR/compare_<spell>.jpg      every 10 fps frame of the pair in a sheet (4 pairs a row)
  OUT_DIR/compare_all.mp4          all spells one after another
A spell missing from BEFORE gets a black left half marked "no before".
"""
import re
import subprocess
import sys
from pathlib import Path

FPS_SRC = 30.0


def spans(log: Path) -> dict:
    out = {}
    for line in log.read_text(errors="replace").splitlines():
        m = re.search(r"\[magiclab\] (\S+) open from frame (\d+) to frame (\d+)", line)
        if m:
            out[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return out


def run(cmd):
    subprocess.run(cmd, check=True)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    fps = 10
    if "--fps" in sys.argv:
        fps = int(sys.argv[sys.argv.index("--fps") + 1])
    before, after, out = Path(args[0]), Path(args[1]), Path(args[2])
    out.mkdir(parents=True, exist_ok=True)
    sb = spans(before / "log.txt")
    sa = spans(after / "log.txt")
    parts = []
    W = 640
    for sp, (a0, a1) in sa.items():
        dur = (a1 - a0) / FPS_SRC + 0.6
        lab = f"drawtext=text='%s':x=6:y=6:fontsize=16:fontcolor=white:box=1:boxcolor=black@0.6"
        right = f"[1:v]trim=start={a0 / FPS_SRC:.3f}:duration={dur:.3f},setpts=PTS-STARTPTS,fps={fps},scale={W}:-2,{lab % ('AFTER ' + sp)}[r]"
        if sp in sb:
            b0 = sb[sp][0]
            left = f"[0:v]trim=start={b0 / FPS_SRC:.3f}:duration={dur:.3f},setpts=PTS-STARTPTS,fps={fps},scale={W}:-2,{lab % ('BEFORE ' + sp)}[l]"
        else:
            left = f"[1:v]trim=start={a0 / FPS_SRC:.3f}:duration={dur:.3f},setpts=PTS-STARTPTS,fps={fps},scale={W}:-2,drawbox=c=black:t=fill,{lab % 'no before'}[l]"
        fc = f"{left};{right};[l][r]hstack=inputs=2,drawtext=text='%{{pts\\:hms}}':x=w-120:y=h-24:fontsize=14:fontcolor=white:box=1:boxcolor=black@0.6[v]"
        mp4 = out / f"compare_{sp}.mp4"
        run(["ffmpeg", "-v", "error", "-y", "-i", str(before / "lab.mp4"), "-i", str(after / "lab.mp4"), "-filter_complex", fc,
             "-map", "[v]", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-r", str(fps), str(mp4)])
        n = int(dur * fps) + 1
        rows = (n + 3) // 4
        run(["ffmpeg", "-v", "error", "-y", "-i", str(mp4), "-vf", f"scale=640:-2,tile=4x{rows}", "-frames:v", "1", str(out / f"compare_{sp}.jpg")])
        parts.append(mp4)
    lst = out / "list.txt"
    lst.write_text("".join(f"file '{p.resolve()}'\n" for p in parts))
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(out / "compare_all.mp4")])
    print(f"{len(parts)} spells compared, {sum(1 for s in sa if s in sb)} with a before")


if __name__ == "__main__":
    main()
