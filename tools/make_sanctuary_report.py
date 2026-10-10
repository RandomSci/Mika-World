#!/usr/bin/env python3
"""Build docs/SANCTUARY.md from the JSON written by `--sanctuarytour` (no hand-typed numbers)."""
import json, os

root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
def J(p):
    p = os.path.join(root, p)
    return json.load(open(p)) if os.path.exists(p) else None

data = J("data/sanctuary.json")
live = J("screenshots/sanctuary/sanctuary_tour_live_optimized.json")
cine = J("screenshots/sanctuary/sanctuary_tour_cinematic.json")
ab = J("screenshots/sanctuary/expansion_ab.json")
out = ["# Arcane Sanctuary — Mika's home base (mini-region)", "",
       "Measured on this laptop (Intel Raptor Lake-P iGPU, Vulkan/Forward+, 1600×900, 30 FPS cap in LIVE_OPTIMIZED). "
       "Regenerate: run `--sanctuarytour=full` (LIVE) / `--sanctuarytour=activities` (CINEMATIC), then `python3 tools/make_sanctuary_report.py`.", "",
       "## Story", "", data["story"]["premise"], "", f"**Mission:** {data['story']['mission']}", "",
       "Ranks: " + " → ".join(f"{r['name']} ({r['trials']} trials{', skill ≥ ' + str(r['min_skill']) if 'min_skill' in r else ''})" for r in data["ranks"]) + ".", "",
       "## Sub-areas", "", "| sub-area | purpose | activities |", "|---|---|---|"]
acts = {}
for a in data["actions"]:
    acts.setdefault(a["sub_area"], []).append(f"`{a['id']}` ({a['kind']})")
for sid, s in data["sub_areas"].items():
    out.append(f"| **{s['name']}** | {s['purpose']} | {', '.join(acts.get(sid, []))} |")
out += ["", "Trials: " + "; ".join(t["name"] for t in data["trials"]) + ".", ""]


def perf(rep, title):
    out.append(f"## {title}")
    out.append("")
    out.append("| sub-area | establishing FPS / GPU ms | worst frame ms | activity FPS / GPU ms | camera during activity | activity result | night FPS / GPU ms |")
    out.append("|---|---|---|---|---|---|---|")
    for sid, r in rep["sub_areas"].items():
        e = r["establishing"]; a = r.get("perf_activity", {}); n = rep["night"].get(sid, {})
        act = r.get("activity") or {}
        res = ("✓ " + str(act.get("detail", ""))[:48]) if act.get("ok") else (str(act.get("detail", "—"))[:48] if act else "—")
        out.append(f"| {sid} | {e['fps']} / {e['gpu_ms']} | {e['worst_frame_ms']} | {a.get('fps', '—')} / {a.get('gpu_ms', '—')} | {r.get('camera_mode', '—')} | {res} | "
                   f"{n.get('fps', '—')} / {n.get('gpu_ms', '—')} |")
    b = rep.get("build", {})
    out.append("")
    out.append(f"Sanctuary activation (first load, behind the travel mask): total {b.get('total_ms')} ms, build {b.get('build_ms')} ms in {b.get('build_frames')} frames, "
               f"worst step {b.get('worst_build_step_ms')} ms (architecture trimesh collision, pre-existing), nav bake {b.get('nav_bake_ms')} ms, "
               f"static memory {b.get('mem_static_mb_after')} MB, video {b.get('video_mb_after')} MB, {b.get('nodes_after')} nodes, layout hash `{b.get('layout_hash')}`.")
    out.append("")
    p = rep.get("probe", {})
    if p:
        out.append(f"GPU cost by category at the classic establishing view (all: {p['all']['gpu_ms']} ms, {p['all']['primitives']} primitives):")
        out.append("")
        out.append("| hidden category | saves GPU ms | saves primitives |")
        out.append("|---|---|---|")
        for k, v in sorted(p.items(), key=lambda kv: -kv[1].get("saves_gpu_ms", 0) if kv[0] != "all" else 1e9):
            if k == "all":
                continue
            out.append(f"| {k.replace('without_', '')} | {v['saves_gpu_ms']} | {v['saves_prims']} |")
        out.append("")


if live:
    perf(live, "LIVE_OPTIMIZED")
if ab:
    out.append("## Cost of the expansion (A/B, LIVE_OPTIMIZED, same cameras)")
    out.append("")
    out.append("| view | without expansion GPU ms | with expansion GPU ms | Δ |")
    out.append("|---|---|---|---|")
    for k in ab["with"]:
        w = ab["with"][k]; wo = ab["without"].get(k)
        if wo:
            out.append(f"| {k} | {wo['gpu_ms']} | {w['gpu_ms']} | {round(w['gpu_ms'] - wo['gpu_ms'], 2):+} |")
    out.append("")
if cine:
    perf(cine, "CINEMATIC")
if live and live.get("brain_run"):
    br = live["brain_run"]
    out.append("## Mika's own decisions (SanctuaryBrain, 150 s, no external AI)")
    out.append("")
    out.append("| t (s) | action | utility | ok | result |")
    out.append("|---|---|---|---|---|")
    t0 = br["log"][0]["t"] if br["log"] else 0
    for h in br["log"]:
        out.append(f"| {round(h['t'] - t0, 1)} | `{h['action']}` | {h['utility']} | {'✓' if h['ok'] else '✗'} | {h['detail']} |")
    out.append("")
    perf_s = [s for s in br["samples"] if "perf" in s]
    if perf_s:
        p = perf_s[0]["perf"]
        out.append(f"Performance while the brain + director run: {p['fps']} FPS, GPU {p['gpu_ms']} ms, worst frame {p['worst_frame_ms']} ms.")
    m = live.get("mission", {})
    out.append("")
    out.append(f"After the whole tour: rank **{m.get('rank')}**, trials {m.get('trials_done')}/{m.get('trials_total')}.")
    out.append("")
open(os.path.join(root, "docs/SANCTUARY_REPORT.md"), "w").write("\n".join(out) + "\n")
print("wrote docs/SANCTUARY_REPORT.md,", len(out), "lines")
