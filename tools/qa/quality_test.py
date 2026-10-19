# The quality test (Selwyn, 2026-10-20): 30 s of our fight beside 30 s of the Battle of Mages reference at the same
# height, as a video, plus 10 fps frame sheets pairing them (each sheet 5 s: the reference's 50 frames above ours).
#   python3 tools/qa/quality_test.py <ref.mp4> <ref start s> <ours.mp4> <our start s> <out dir> [seconds]
import os
import subprocess
import sys

import cv2
import numpy as np

ref, rs, ours, os_, outd = sys.argv[1], float(sys.argv[2]), sys.argv[3], float(sys.argv[4]), sys.argv[5]
dur = float(sys.argv[6]) if len(sys.argv) > 6 else 30.0
os.makedirs(outd, exist_ok=True)
H = 768
vid = os.path.join(outd, "quality_side_by_side.mp4")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(rs), "-t", str(dur), "-i", ref, "-ss", str(os_), "-t", str(dur), "-i", ours,
                "-filter_complex", "[0:v]scale=-2:%d,fps=30,setsar=1[a];[1:v]scale=-2:%d,fps=30,setsar=1[b];[a][b]hstack=inputs=2[v]" % (H, H),
                "-map", "[v]", "-an", "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", vid], check=True)
print(vid)


def frames(path, start, n, w, h):
    cap = cv2.VideoCapture(path)
    out = []
    for i in range(n):
        cap.set(cv2.CAP_PROP_POS_MSEC, (start + i / 10.0) * 1000.0)
        ok, img = cap.read()
        out.append(cv2.resize(img, (w, h), interpolation=cv2.INTER_AREA) if ok else np.zeros((h, w, 3), np.uint8))
    return out


per = 50
for k in range(int(dur // 5)):
    a = frames(ref, rs + k * 5, per, 120, 160)
    b = frames(ours, os_ + k * 5, per, 213, 120)
    for i, img in enumerate(a):
        cv2.putText(img, "%.1f" % (k * 5 + i / 10.0), (2, 11), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (0, 255, 255), 1)
    for i, img in enumerate(b):
        cv2.putText(img, "%.1f" % (k * 5 + i / 10.0), (2, 11), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (0, 255, 255), 1)
    top = np.vstack([np.hstack(a[r * 10:(r + 1) * 10]) for r in range(5)])
    bot = np.vstack([np.hstack(b[r * 10:(r + 1) * 10]) for r in range(5)])
    w = max(top.shape[1], bot.shape[1])
    pad = lambda m: np.hstack([m, np.zeros((m.shape[0], w - m.shape[1], 3), np.uint8)])
    bar = lambda txt: cv2.putText(np.full((24, w, 3), 30, np.uint8), txt, (6, 17), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1)
    sheet = np.vstack([bar("reference, Battle of Mages, %.0f to %.0f s" % (rs + k * 5, rs + k * 5 + 5)), pad(top),
                       bar("ours, %.0f to %.0f s" % (os_ + k * 5, os_ + k * 5 + 5)), pad(bot)])
    p = os.path.join(outd, "quality_sheet_%02d.jpg" % k)
    cv2.imwrite(p, sheet, [cv2.IMWRITE_JPEG_QUALITY, 85])
    print(p)
