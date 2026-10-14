#!/usr/bin/env python3
"""Shrink a GLB's embedded textures (the rival kits ship 2-4K PNGs: ~53 MB of a 56 MB file).

Each image is resized so its longest side is at most --max (colour / normal maps) or --small (ORM, roughness,
hair), and re-encoded as JPEG (glTF allows image/jpeg; maps with an alpha channel stay PNG). Geometry, skins and
animations are copied byte for byte.

  python3 tools/models/slim_glb.py in.glb out.glb [--max 2048] [--small 1024] [--q 88]
"""
import io
import json
import struct
import sys

from PIL import Image


def pad4(b, fill=b"\x00"):
	return b + fill * ((4 - len(b) % 4) % 4)


def main():
	a = sys.argv[1:]
	src, dst = a[0], a[1]
	mx = int(a[a.index("--max") + 1]) if "--max" in a else 2048
	small = int(a[a.index("--small") + 1]) if "--small" in a else 1024
	q = int(a[a.index("--q") + 1]) if "--q" in a else 88
	f = open(src, "rb").read()
	jl = struct.unpack("<I", f[12:16])[0]
	j = json.loads(f[20:20 + jl])
	bin_off = 20 + jl + 8
	binl = struct.unpack("<I", f[20 + jl:24 + jl])[0]
	blob = f[bin_off:bin_off + binl]
	views = j["bufferViews"]
	img_views = {im["bufferView"]: im for im in j.get("images", []) if "bufferView" in im}
	out = bytearray()
	before = after = 0
	for i, v in enumerate(views):
		data = blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
		if i in img_views:
			im = img_views[i]
			name = (im.get("name") or "").lower()
			pic = Image.open(io.BytesIO(data))
			lim = small if (name.endswith("_orm") or "rough" in name or "metal" in name or "hair" in name) else mx
			if max(pic.size) > lim:
				s = lim / max(pic.size)
				pic = pic.resize((max(1, round(pic.size[0] * s)), max(1, round(pic.size[1] * s))), Image.LANCZOS)
			buf = io.BytesIO()
			has_alpha = pic.mode in ("RGBA", "LA") and pic.getchannel("A").getextrema()[0] < 250
			if has_alpha:
				pic.save(buf, "PNG", optimize=True)
				im["mimeType"] = "image/png"
			else:
				pic.convert("RGB").save(buf, "JPEG", quality=q, optimize=True)
				im["mimeType"] = "image/jpeg"
			before += len(data)
			data = buf.getvalue()
			after += len(data)
		out_off = len(out)
		out += data
		out += b"\x00" * ((4 - len(out) % 4) % 4)
		v["byteOffset"] = out_off
		v["byteLength"] = len(data)
	j["buffers"][0]["byteLength"] = len(out)
	js = pad4(json.dumps(j, separators=(",", ":")).encode(), b" ")
	body = struct.pack("<I", len(js)) + b"JSON" + js + struct.pack("<I", len(out)) + b"BIN\x00" + bytes(out)
	open(dst, "wb").write(b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body)
	print("%s: images %.1f MB -> %.1f MB, file %.1f MB" % (dst, before / 1e6, after / 1e6, (12 + len(body)) / 1e6))


if __name__ == "__main__":
	main()
