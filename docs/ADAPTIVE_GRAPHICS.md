# Adaptive graphics: as beautiful as the GPU allows, at 60 FPS

`AdaptiveQuality` (`scripts/core/adaptive_quality.gd`) keeps Mika V3 at 1920x1080 / 60 FPS, including with a
livestream encoder sharing the GPU, while drawing the best quality that frame budget allows at that moment.

## Profiles (`RenderProfile`, `--profile=...`, P cycles them in the dev build)

| profile | what it is | FPS cap |
|---|---|---|
| **Adaptive 60** (`adaptive`), recommended for streaming | CINEMATIC quality is the ceiling; quality follows the measured frame budget | 60 |
| **Stable 60** (`stable`) | the old live settings, fixed (0.75 FSR 1, no SSIL/SSR/fog, 2048 shadows, 55 % foliage): the diagnostic baseline | 60 |
| **Cinematic Maximum** (`cinematic_max`) | CINEMATIC quality, never reduced: screenshots, recordings | none, no 60 FPS promise |
| CINEMATIC / LIVE_OPTIMIZED / ULTRA | the earlier profiles, unchanged | 60 / 30 / none |

Adaptive 60 never changes the 60 FPS cap, never falls back to a lower frame rate, and never touches GPU power
limits, game logic, physics, AI, animation or the characters. Mika's and Luna's meshes are pinned at full LOD
detail; their textures, rigs and clothes are never altered.

## How it decides

* **Measured every frame:** frame time; the GPU's own render time (`viewport_get_measured_render_time_gpu`); the
  CPU's render-thread plus physics time; new pipeline compilations; whether an area is loading.
* **Windows:** decisions use rolling 3 s and 8 s windows (average, p95, p99, 1% low), never one frame. Frames
  during an area load or a pipeline-compilation stall are counted as stutters and left out of the decision.
* **What limits the frame:**

  | classification | condition |
  |---|---|
  | `gpu` | the game's GPU work is over ~82 % of the budget |
  | `cpu` | the CPU work is over budget while the GPU is not |
  | `contention` | frames are late although neither explains it (an encoder, the compositor, another process) |

* **Down (one step):** only for **sustained** lateness, meaning the 3 s average is over budget or more than 5 % of
  frames are late, and only when the GPU or contention explains it. Isolated stalls over 2x the budget are left out
  of the average and counted as spikes.
  * An isolated spike is never answered with lower graphics; that would not help.
  * CPU-bound frames are reported, not "fixed" with graphics.
  * Steps are at least 2.5 s apart, 1 s when frames are more than 35 % over budget. It is always one step at a
    time, and the next step waits until the last one's effect has been measured.
* **Up (one step):** only after 8 s of clear headroom: the GPU time plus the step's measured cost must stay under
  60 % of the budget, with p95 on time.
  * When the scene has become much lighter (GPU under half the budget), steps come back every 3 s.
  * A step that has to be re-applied within 20 s of being restored counts as an **oscillation**. That step then
    needs more headroom and a longer wait before it comes back.
  * No restorations happen during cinematic shots (scenes, signature spells, performances, stargazing). A
    downgrade happens there only if a shot is truly struggling (1% low under 50).
* **Memory:** once a situation (this area, or this area in a fight) has held 60 FPS for 10 s, its level is
  remembered. Coming back jumps straight there in one change, instead of stuttering down through the ladder again.
  * The first fight of a session starts at level 6, or at whatever fights needed before.
  * Measurement refines the level from there.
* **No compile stalls later:** the GPU pipelines of every on/off the ladder can make (SSR, SSIL, volumetric fog,
  both upscalers) are drawn once when the first area opens.

## The ladder: ordered by measured savings

The ladder was measured, not assumed. `--mktest=gfxcal` tries each knob **alone**, uncapped, in the dense forest,
the village and the ambush, and records the GPU milliseconds it saves (`--cal-base=floor` measures on top of the
ladder's bottom):

| knob | forest | village | ambush fight |
|---|---|---|---|
| distant foliage range (visibility ranges with fade, no popping) | -4.9 ms | -2.8 | noise |
| internal 3D scale 0.83 / 0.67 (FSR 2 upscaled to 1080p) | -3.3 / -6.2 | -2.8 / -4.8 | -3.3 / -6.4 |
| screen-space reflections off | -0.3 | -0.6 | -2.8 |
| volumetric fog off | 0 | -0.3 | -2.5 |
| mesh LOD threshold x2.5 | 0 | -0.3 | -1.9 |
| screen-space indirect light off | -0.3 | -0.9 | -1.1 |
| undergrowth density 55 % | -0.5 | 0 | 0 |
| SSAO quality low | about 0 | about 0 | about 0 |

A second calibration, measured on top of the ladder's floor in the fight (`--cal-base=floor`), plus a GPU breakdown
(hiding whole categories), found what dominates a fight:

| change | fight (on top of the floor) |
|---|---|
| hide trees / sun shadows off / all particles (diagnostic only) | -16.6 / -17.3 / -13.5 ms |
| sun shadow map 4096 to 2048 | **-12.4 ms** (only -1.9 in the calm forest) |
| mesh LOD x2.5 | -3.7 |
| FSR 1 + FXAA instead of FSR 2 | -2.7 |
| SSAO off | -2.3 |
| secondary particles 60 % | -2.0 |
| sun shadow distance 60 % | -1.3 |

The trees' shadows in the 4096 shadow atlas are the fight's main cost. Changing the atlas size reallocates it (a
possible hitch), so that step is taken **at a fight's first moment in one go** (the camera cuts to the stand-off
then anyway) and is given back only after the fight, never in the middle of one.

The ladder, 18 levels, least noticeable first:

1. distant foliage range 82 %
2. 3D scale 0.90
3. mesh LOD x1.8
4. distant range 66 %
5. SSR off
6. scale 0.83
7. **sun shadow map 2048** (reallocating: fight start / outside fights only)
8. SSIL off
9. distant range 52 %
10. scale 0.75
11. volumetric fog off
12. undergrowth 60 %
13. scale 0.67 (FSR 2 "Quality")

The fight-only tail (calm scenes never get this far down):

14. mesh LOD x2.5
15. secondary particles 65 %
16. sun shadow distance 66 %
17. ambient occlusion off
18. FSR 1 + FXAA: **the floor**

At the floor a fight's GPU frame fits the 16.7 ms budget. The first fight of a session starts at level 13; any later
fight starts at the level fights needed before, which is remembered.

FSR 2 is used from native scale in Adaptive 60. It is also the temporal anti-aliasing, so lowering the internal
scale changes sharpness a little but never the AA style. Sharpening is set to 0.25 so faces stay crisp.

## Benchmarks (1920x1080 fullscreen, Mika + Luna, 45 s per scene, `~/.cache/mika_qa/bench/bench_profile.sh`)

Clean passes. The sampler recorded no other process on the GPU; contaminated passes were marked and re-run.
Values are average FPS / 1% low FPS. "Level" is the average quality level the controller held (0 = full CINEMATIC).

| scene | Stable 60 (fixed, live settings) | **Adaptive 60** | Adaptive 60 + NVENC 1080p60 | CINEMATIC fixed at 60 |
|---|---|---|---|---|
| Sanctuary | 59.7 / 39.6 | **59.9 / 43.8** (level 2) | 59.2-60.0 / 25-55 (level 2-4) | 59.8 / 46.2 |
| Dense forest | 59.9 / 46.4 | **59.6 / 38.7** (level 6) | 59.7-59.8 / 40-55 (level 6) | **43.8 / 28.9** |
| Village + residents | 59.9 / 46.3 | **59.8 / 45.6** (level 5) | 59.9-60.0 / 46-58 (level 5-6) | 59.8 / 45.2 |
| Ambush fight + magic | 59.8 / 44.2 | **58.4 / 36.9** (level 16) | 57.9-58.3 / 33-44 (level 16) | **24.1 / 17.5** |

GPU time per frame: Stable 60 used 6-15 ms; Adaptive 60 used 8-15 ms (it spends the headroom on quality);
fixed CINEMATIC used 12-41 ms.

Hardware during the passes:

* GPU 67-76 C. CPU package **85-97 C**: the laptop's `performance` power profile keeps all cores near 3.9 GHz at
  any load (see below).
* VRAM: Stable 1.5-2.1 GB; Adaptive 1.7-2.8 GB (the FSR 2 buffers), out of 8 GB.
* System RAM: 8.6-11.8 GB of 16 GB (the game itself uses 2.0-2.7 GB).

Earlier, the same machine also measured Stable 60 at a clean 60.0 / 60.0 in every scene, with and without NVENC.
Those numbers came while the GPU and CPU were otherwise idle. The 1% lows in this table (all profiles alike) are
lower because the CPU was at 91-97 C and another session's apps were running. Compare the columns with each other,
not with that idle run.

**What it buys:** calm scenes (the Sanctuary, the village) run at or near full CINEMATIC quality: volumetric fog,
SSR, SSIL, 4096 shadows, native or 0.9 scale. Stable 60 never has those. The forest and the fight, where fixed
CINEMATIC collapses to 44 and 24 FPS, hold 58-60 FPS, and the controller gives back exactly the quality those
scenes cost. Visual comparison: `screenshots/adaptive_comparison.jpg` (four scenes x three profiles).

## Developer view (F6)

The F6 panel shows:

* FPS, frame average, p95, p99 and 1% low;
* GPU and CPU milliseconds and what limits the frame;
* the quality level and every knob: 3D scale and upscaler, distant range, LOD, foliage, SSR, SSIL, fog;
* compile and load stutters, the last decision's reason, and the recent changes.

Every change is also logged once as `[gfx] quality down/up -> level N (step): reason`.

## Tests

* `--profile=adaptive --mktest=adaptive`: the decision rules, driven by synthetic frame windows, independent of
  the GPU:
  * one step at a time, with the gap;
  * loads and compiles ignored; CPU-bound frames left alone;
  * restored only after sustained headroom; oscillation patience; remembered situations;
  * the knobs reach the renderer; the characters are protected.
* `--profile=adaptive --mktest=gfxcal [--cal-base=floor] [--bench-scenes=...] [--cal-knobs=...]`: per-knob GPU
  savings.
* `--mktest=bench --bench-fps=60 --bench-scenes=...` under any profile, via
  `~/.cache/mika_qa/bench/bench_profile.sh <profile> <nvenc 0|1>`. Hardware is sampled every second, and other
  processes on the GPU are recorded so contaminated passes are marked.

## Honest limitations

* **Isolated spikes remain.** The 1% lows (33-46 FPS) come from single long frames, not slow scenes:
  * pipeline compilation the first time a material is drawn with a new effect combination;
  * area streaming;
  * CPU stalls at 90-97 C.

  The controller ignores them on purpose, because lowering graphics cannot fix a stall. Compilation is reduced by
  drawing every ladder extreme once behind each travel card, but not eliminated.
* **The first fight of a session** starts at level 13 and then refines. Until that fight's level has been learned,
  frames can run late for a few seconds after an ambush starts.
* **CPU temperature is the main stability risk for long streams, and it is not graphics.** With the
  `performance` power profile (chosen by the developer), the i5-13420H holds about 3.9 GHz on all cores and sits at
  85-97 C even at 10-30 % load. The `balanced` profile would likely cool it substantially at little FPS cost (the
  game is GPU-bound). This was not changed: system power settings are the developer's call.
* **OBS itself was not tested.** The OBS flatpak cannot be run on an isolated configuration: it loads the live
  profile and records the desktop. The NVENC column uses ffmpeg with the same encoder (H.264 NVENC p5, CBR 12 Mbps,
  1080p60) in real time. Real OBS also captures the game window and composites its scene, so expect slightly worse
  numbers than that column. A real OBS test should be run by the developer with a dedicated profile.
* VRAM under Adaptive 60 is about 0.5-0.7 GB higher than Stable 60 (FSR 2 history buffers), which is well within
  8 GB.
* The protected `sanctuary.gd` (developer WIP) still compares `profile == LIVE_OPTIMIZED` directly, so Stable 60
  draws the Sanctuary's extra shadows and props at CINEMATIC density. Other areas use `RenderProfile.tier()`.
