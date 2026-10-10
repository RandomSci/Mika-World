#!/usr/bin/env python3
"""Fetch selected Poly Haven (CC0) assets via the documented API (https://api.polyhaven.com).
Usage: fetch_polyhaven.py <kind:model|texture|hdri> <asset_id> <res> [format]
Writes into assets/polyhaven/<kind>s/<asset_id>/ and appends to assets/ASSET_MANIFEST.jsonl.
All files are md5-verified against the API listing."""
import hashlib, json, os, sys, urllib.request, datetime
UA = {"User-Agent": "MikaGodotDev/1.0 (personal dev project)"}
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()

def save(url, dest, md5):
    if os.path.exists(dest) and hashlib.md5(open(dest, "rb").read()).hexdigest() == md5:
        return 0
    data = get(url)
    if hashlib.md5(data).hexdigest() != md5:
        raise SystemExit(f"md5 mismatch for {url}")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, "wb").write(data)
    return len(data)

def main():
    kind, aid, res = sys.argv[1:4]
    fmt = sys.argv[4] if len(sys.argv) > 4 else None
    files = json.loads(get(f"https://api.polyhaven.com/files/{aid}"))
    out = os.path.join(ROOT, "assets", "polyhaven", kind + "s", aid)
    total, saved = 0, []
    if kind == "model":
        entry = files["gltf"][res]["gltf"]
        total += save(entry["url"], os.path.join(out, os.path.basename(entry["url"])), entry["md5"])
        saved.append(os.path.basename(entry["url"]))
        for rel, inc in entry["include"].items():
            total += save(inc["url"], os.path.join(out, rel), inc["md5"]); saved.append(rel)
    elif kind == "texture":
        maps = {"Diffuse": "jpg", "nor_gl": "jpg", "Rough": "jpg", "AO": "jpg", "Displacement": "png"}
        if "Diffuse" not in files and "col_01" in files:
            maps["col_01"] = "jpg"  # colour-variant sets (fabrics) have col_01/col_02/... instead of Diffuse
        for m, f in maps.items():
            if m not in files or res not in files[m]: continue
            e = files[m][res].get(f) or next(iter(files[m][res].values()))
            name = os.path.basename(e["url"])
            total += save(e["url"], os.path.join(out, name), e["md5"]); saved.append(name)
    elif kind == "hdri":
        e = files["hdri"][res][fmt or "hdr"]
        name = os.path.basename(e["url"])
        total += save(e["url"], os.path.join(out, name), e["md5"]); saved.append(name)
    rec = {"source": "Poly Haven", "asset_id": aid, "kind": kind, "resolution": res,
           "page": f"https://polyhaven.com/a/{aid}", "license": "CC0 1.0 (https://polyhaven.com/license)",
           "files": saved, "local_dir": os.path.relpath(out, ROOT), "fetched": datetime.date.today().isoformat()}
    with open(os.path.join(ROOT, "assets", "ASSET_MANIFEST.jsonl"), "a") as fh:
        fh.write(json.dumps(rec) + "\n")
    print(f"{aid}: {len(saved)} files, {total/1e6:.1f} MB downloaded")

main()
