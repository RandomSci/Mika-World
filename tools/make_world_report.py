#!/usr/bin/env python3
"""Build docs/WORLD_REPORT.md from the raw JSON produced by the in-engine tests (no hand-typed numbers)."""
import json, os, statistics, sys

root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
J = lambda p: json.load(open(os.path.join(root, p))) if os.path.exists(os.path.join(root, p)) else None
live = J("screenshots/world_live/worldtour_live_optimized.json")
cine = J("screenshots/world_cine/worldtour_cinematic.json")
brain = J("screenshots/mock_brain_headless.json")
out = ["# Mika World 2.0 — measured world report", "",
       "Every number below is produced by the in-engine test tools (`--worldtour`, `tools/mock_brain.py`) on this laptop "
       "(Intel Raptor Lake-P iGPU, Vulkan/Forward+, 1600×900; OBS was not running during these measurements). "
       "Regenerate with `python3 tools/make_world_report.py`.", ""]


def perf_table(rep, title):
    out.append(f"## {title} — per location")
    out.append("")
    out.append("| location | FPS | GPU ms | worst frame ms | primitives | draw calls | night FPS / GPU ms | cast FPS / worst ms | activity |")
    out.append("|---|---|---|---|---|---|---|---|---|")
    seen = set()
    for v in rep["visits"]:
        loc = v["location"]
        if loc in seen:
            continue
        seen.add(loc)
        e = v.get("perf_explore", {}); n = v.get("perf_night", {}); c = v.get("perf_cast", {}); i = v.get("interaction", {})
        out.append(f"| {loc} | {e.get('fps','')} | {e.get('gpu_ms','')} | {e.get('worst_frame_ms','')} | {e.get('primitives','')} | {e.get('draw_calls','')} | "
                   f"{n.get('fps','')} / {n.get('gpu_ms','')} | {c.get('fps','')} / {c.get('worst_frame_ms','') if c else ''} | {'✓ ' + str(i.get('detail',''))[:46] if i.get('ok') else str(i.get('detail',''))[:46]} |")
    out.append("")
    gpus = [v["perf_explore"]["gpu_ms"] for v in rep["visits"] if "perf_explore" in v]
    out.append(f"GPU ms across all visits: min {min(gpus)}, median {statistics.median(gpus)}, max {max(gpus)}. "
               f"Locations under 30 FPS: {sorted(set(v['location'] for v in rep['visits'] if v.get('perf_explore',{}).get('fps',99) < 29.5)) or 'none'}.")
    out.append("")


def transitions(rep, title):
    t = rep["checks"]["transitions"]
    out.append(f"## {title} — streaming transitions")
    out.append("")
    out.append("| # | from → to | total ms | preload wait ms | unload ms | build ms (frames) | worst step ms | nav bake ms | static MB | video MB | nodes | areas | nav regions | layout hash |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for k, x in enumerate(t):
        out.append(f"| {k} | {x['from'] or '(start)'} → {x['to']} | {x['total_ms']} | {x['wait_for_preload_ms']} | {x['unload_ms']} | {x['build_ms']} ({x['build_frames']}) | "
                   f"{x['worst_build_step_ms']} | {x['nav_bake_ms']} | {x['mem_static_mb_after']} | {x['video_mb_after']} | {x['nodes_after']} | {x['instantiated_areas']} | {x['nav_regions_after']} | {x.get('layout_hash','')} |")
    tt = [x["total_ms"] for x in t[1:]]
    out.append("")
    out.append(f"Transition total: median {statistics.median(tt)} ms, max {max(tt)} ms. Instantiated areas after every transition: "
               f"{sorted(set(x['instantiated_areas'] for x in t))}; navigation regions: {sorted(set(x['nav_regions_after'] for x in t))}.")
    out.append("")


if live:
    perf_table(live, "LIVE_OPTIMIZED")
    transitions(live, "LIVE_OPTIMIZED")
    s = [v for v in live["visits"] if v["location"] == "ritual_sanctuary"]
    out.append("### Memory over repeated visits (Sanctuary rows)")
    out.append("")
    out.append("| visit | static MB | texture MB | video MB | nodes |")
    out.append("|---|---|---|---|---|")
    for k, v in enumerate(s):
        e = v["perf_explore"]
        out.append(f"| {k + 1} | {e['static_mem_mb']} | {e['texture_mem_mb']} | {e['video_mem_mb']} | {e['nodes']} |")
    out.append("")
if cine:
    perf_table(cine, "CINEMATIC")
    transitions(cine, "CINEMATIC")
if brain:
    v = brain["visits"]
    out.append("## Autonomous traversal (tools/mock_brain.py over the bridge, headless)")
    out.append("")
    out.append(f"Journeys succeeded: {sum(1 for x in v if x.get('journey',{}).get('ok'))}/{len(v)}; locations visited: "
               f"{len(brain['final_state']['visited'])}/24; activities succeeded: {sum(1 for x in v if x.get('interaction',{}).get('ok'))}; "
               f"casts: {sum(1 for x in v if 'cast' in x)} (all finished: {all(x['cast']['finished'] for x in v if 'cast' in x)}); elapsed {brain['elapsed_s']} s.")
    out.append("")
    out.append("Honesty checks (scenic / unfinished landmarks must not be travelable):")
    out.append("")
    for h in brain["honesty_checks"]:
        out.append(f"* `{h['landmark']}` ({h.get('kind','')}): reachable flag = {h.get('reachable_flag', '—')}, travel_to → {h['travel_reply']}")
    out.append("")
    out.append(f"Final world state: skills {brain['final_state']['skills']}, inventory {brain['final_state']['inventory']}, "
               f"{len(brain['final_state']['knowledge'])} knowledge entries.")
    out.append("")
open(os.path.join(root, "docs/WORLD_REPORT.md"), "w").write("\n".join(out) + "\n")
print("wrote docs/WORLD_REPORT.md,", len(out), "lines")
