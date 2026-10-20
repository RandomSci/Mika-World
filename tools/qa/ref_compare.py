#!/usr/bin/env python3
"""ref_compare.py OURS.mp4 START DUR REF.mp4 REF_START REF_DUR OUT_PREFIX [label_ours] [label_ref]

Our render next to one of Selwyn's reference videos at 10 fps, both scaled to the same height (the references are
portrait or landscape), the longer one sets the length (the shorter holds its last frame). Writes
  OUT_PREFIX.mp4        the pair at 10 fps
  OUT_PREFIX_sheet.jpg  every frame of the pair at 5 fps in a sheet (4 pairs a row)
"""
import subprocess
import sys


def main():
	ours, s0, d0, ref, s1, d1, out = sys.argv[1:8]
	lo = sys.argv[8] if len(sys.argv) > 8 else "OURS"
	lr = sys.argv[9] if len(sys.argv) > 9 else "REFERENCE"
	H = 540
	dur = max(float(d0), float(d1))
	lab = "drawtext=text='%s %%{pts\\:hms}':x=6:y=6:fontsize=16:fontcolor=white:box=1:boxcolor=black@0.6"
	fc = (f"[0:v]trim=start={s0}:duration={d0},setpts=PTS-STARTPTS,fps=10,scale=-2:{H},tpad=stop_mode=clone:stop_duration={dur},{lab % lo}[a];"
		f"[1:v]trim=start={s1}:duration={d1},setpts=PTS-STARTPTS,fps=10,scale=-2:{H},tpad=stop_mode=clone:stop_duration={dur},{lab % lr}[b];"
		f"[a][b]hstack=inputs=2,trim=duration={dur}[v]")
	subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ours, "-i", ref, "-filter_complex", fc, "-map", "[v]", "-c:v", "libx264",
		"-preset", "veryfast", "-crf", "20", "-r", "10", out + ".mp4"], check=True)
	n = int(dur * 5) + 1
	rows = (n + 3) // 4
	subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", out + ".mp4", "-vf", f"fps=5,scale=-2:220,tile=4x{rows}", "-frames:v", "1",
		out + "_sheet.jpg"], check=True)
	print(out + ".mp4", out + "_sheet.jpg")


if __name__ == "__main__":
	main()
