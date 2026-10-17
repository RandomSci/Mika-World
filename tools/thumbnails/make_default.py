"""Build the permanent default thumbnail from a real Stage frame (no paid API).

    .venv/bin/python tools/thumbnails/make_default.py [frame.png] [TEXT]

The frame is a real 1280x720 capture of the world Stage (Mika's selfie camera
in her room, assets/thumbnails/mika-world-stage-frame.png). Mika is moved to
the right for the title, and the in-world wall clock (a date and time) is
blurred so the thumbnail stays timeless and can be reused for any stream.
"""

import io
import sys
from pathlib import Path

from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from open_llm_vtuber.publishing.prelive import DEFAULT_THUMBNAIL, render_thumbnail, validate_thumbnail  # noqa: E402

frame = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/thumbnails/mika-world-stage-frame.png")
text = sys.argv[2] if len(sys.argv) > 2 else "MIKA'S WORLD"
img = Image.open(frame).convert("RGB").resize((1280, 720), Image.LANCZOS)
clock = img.crop((900, 0, 1110, 75)).filter(ImageFilter.GaussianBlur(14))
img.paste(clock, (900, 0))
big = img.resize((1600, 900), Image.LANCZOS)  # zoom 1.25: Mika larger and to the right
canvas = big.crop((0, 0 + 10, 1280, 730))
buf = io.BytesIO()
canvas.save(buf, "PNG")
thumb = render_thumbnail(buf.getvalue(), text)
problems = validate_thumbnail(thumb)
if problems:
    raise SystemExit(f"invalid: {problems}")
DEFAULT_THUMBNAIL.parent.mkdir(parents=True, exist_ok=True)
DEFAULT_THUMBNAIL.write_bytes(thumb)
print(f"{DEFAULT_THUMBNAIL} {len(thumb)} bytes")
