# Performance on the RTX 5050 (Laptop) — measured 2026-10-15

Godot 4.7.2, Vulkan Forward+, NVIDIA GeForce RTX 5050 Laptop GPU (driver 615.71.09), power profile
`performance`, 1600x900 window, `--profile=live` (LIVE_OPTIMIZED: the stream target is 30 fps, frame-capped).
Source: `--mktest=tour --areas=<all 15>` (each area held 4 s after its views; numbers from `_fps_stats()`).

| area | avg fps | GPU ms / frame | render CPU ms | draw calls | primitives | video memory |
|---|---|---|---|---|---|---|
| sanctuary | 29.5 | 5.64 | 1.01 | 525 | 1.92 M | 750 MB |
| whispering_woods | 29.4 | 13.25 | 1.40 | 1224 | 3.99 M | 1116 MB |
| ancient_grove | 29.4 | 12.67 | 1.21 | 1145 | 5.36 M | 1087 MB |
| river_valley | 29.5 | 9.62 | 0.98 | 794 | 2.35 M | 990 MB |
| highland_path | 29.3 | 4.27 | 0.92 | 400 | 1.83 M | 934 MB |
| celestial_summit | 29.5 | 8.86 | 0.85 | 400 | 1.71 M | 976 MB |
| crystal_caverns | 29.6 | 4.63 | 0.45 | 91 | 0.37 M | 906 MB |
| deep_caverns | 29.5 | 3.22 | 0.58 | 98 | 0.24 M | 968 MB |
| village | 29.5 | 8.00 | 1.26 | 1051 | 2.60 M | 1462 MB |
| observatory_hill | 29.5 | 14.19 | 1.36 | 1264 | 4.07 M | 1197 MB |
| academy | 29.4 | 5.10 | 1.09 | 572 | 1.09 M | 1409 MB |
| mentor_tower | 29.5 | 11.05 | 1.27 | 1124 | 4.19 M | 1263 MB |
| great_library | 29.6 | 4.15 | 0.43 | 32 | 0.56 M | 1060 MB |
| arcane_library | 29.5 | 2.90 | 0.53 | 67 | 0.30 M | 1110 MB |
| wayside (journey roads) | 29.5 | 9.63 | 1.27 | 1007 | 3.37 M | 1298 MB |

Gameplay scenes on top of that:

| scene | avg fps | GPU ms | notes |
|---|---|---|---|
| ambush fight (4 rivals, trailer camera, afterimages) | 29.7 | 9.3-10.0 | p95 frame 33.3 ms; 32-65 hitches > 50 ms over ~6000 frames (shader / effect first use) |
| multi-day journey (85 000 frames) | 29.7 | 10.5-10.7 | camp fire, night creature, packing |
| town life (Village + Academy, 9 residents) | 29.7-29.8 | 4.9-5.4 | |

## Reading it

* Every area holds the 30 fps stream target with the GPU busy at most **14.2 ms of the 33.3 ms frame**: the
  heaviest areas (dense forests, the observatory hill) would still run at ~60 fps uncapped. There is headroom for
  the camera's cinematic effects, combat VFX and OBS encoding on the same GPU.
* Render CPU time is ~1.5 ms at most; draw calls peak at ~1260 (forests: per-species multimeshes).
* Video memory peaks at ~1.5 GB of the card's 8 GB.
* **Hitches: none from the game itself.** The 30-65 "hitches over 50 ms" the ambush test reported were the test's
  own stills: it saves a screenshot every 6 s (a GPU readback and PNG encode, ~130 ms each). Found with
  `--mktest=hitch` (sits in an area and disables each subsystem in turn): with screenshots off, the Whispering Woods
  with both mages, their brains and the camera director shows **0 stalls** over 18 s and over every 13 s window;
  the Movie Maker reels (no stills) show 0 frames over 50 ms. The only long frames left are inside the masked
  area-load transition (5-7 s after a travel starts, behind the travel card). The shader prewarm (which runs
  behind that card) now also covers every effect shader in `shaders/{fx,magic,vfx,world,phoenix,nature}`.

## Benchmark: 30 vs 60 vs uncapped, and a parallel NVENC encode (measured 2026-10-15 18:00-18:22)

Machine: RTX 5050 Laptop (8 GB, driver 615.71.09), i5-13420H (12 threads), 16 GB RAM, power profile `performance`.
Godot fullscreen **1920x1080**, VSync off, Mika and Luna together, profile `live` (LIVE_OPTIMIZED) with the FPS cap
overridden **only inside the test run** (`--mktest=bench --bench-fps=30|60|0`; production profiles unchanged).
Each scene: 45 s measured after a warm-up, frame times from the game; hardware sampled every second
(`~/.cache/mika_qa/bench/`: nvidia-smi, /proc, `sensors`). Scenes: the Sanctuary, the dense Whispering Woods, the
Village at work (residents), the road-thieves ambush (rivals, wards, spells, impacts).

**The 30 FPS is a deliberate cap** (`render_profile.gd`: LIVE_OPTIMIZED `max_fps: 30`; QUALITY 60; CINEMATIC 0).

| scene | cap 30: avg / 1% low | cap 60: avg / 1% low | uncapped: avg / 1% low | cap 60 + NVENC 1080p60: avg / 1% low |
|---|---|---|---|---|
| Sanctuary | 30.0 / 30.0 | 60.0 / 60.0 | 171 / 78 | 60.0 / 60.0 |
| Dense forest | 30.0 / 29.2 | 60.0 / 60.0 | 108 / 70 | 59.8 / **38.2** (p99 23 ms) |
| Village + residents | 30.0 / 28.8 | 60.0 / 57.1 | 159 / 80 | 60.0 / 60.0 |
| Ambush fight + magic | 30.0 / 30.0 | 60.0 / 59.9 | 78 / **42** | 59.7 / 54.5 |

Hardware (scene averages; max for temperatures / memory):

| | cap 30 | cap 60 | uncapped | cap 60 + NVENC |
|---|---|---|---|---|
| GPU frame time (ms) | 5.5-12.0 | 4.5-11.3 | 4.7-11.9 | 4.5-12.9 |
| GPU utilisation | 20-39 % | 30-72 % (85 % peak, fight) | 82-99 % | 33-81 % (100 % peak, fight) |
| GPU clock / power | 570-875 MHz / 14-21 W | 1000-1760 MHz / 24-36 W | 1920-2030 MHz / 38-44 W | 1830-1985 MHz / 27-38 W |
| GPU temperature | 57-65 C | 64-74 C | 79-81 C | 72-77 C |
| NVENC utilisation | 0 | 0 | 0 | 19-21 % (real time: 22 295 frames in 371.6 s = 60.0 fps) |
| VRAM | 0.93-1.46 GB | 0.93-1.46 GB | 0.93-1.47 GB | 1.14-1.66 GB (of 8 GB) |
| CPU utilisation (system) | 9-19 % | 9-25 % | 15-30 % | 9-23 % |
| Godot process CPU | 27-49 % of a core | 39-70 % | 106-211 % | 39-107 % |
| **CPU package temperature** | 68-94 C | 77-96 C | 93-96 C | 87-95 C |
| RAM in use (system) / Godot RSS | 6.6-8.7 / 2.0-2.7 GB | 6.9-8.3 / 2.0-2.7 GB | 6.8-9.1 / 2.1-2.3 GB | 7.3-9.4 / 2.0-2.7 GB (of 16 GB) |

The NVENC pass encodes a synthetic 1080p60 picture with the encoder OBS would use (H.264 NVENC, p5, CBR 12 Mbps)
alongside the game. It is not OBS capturing the game window. Real OBS also copies the window into its compositor
and renders its own canvas, so expect slightly worse numbers than this column. OBS itself was not driven: its
flatpak cannot be run on an isolated config (it loads the live profile). The flatpak NVIDIA GL extension
`nvidia-615-71-09` was installed for the user; without it the OBS flatpak had no NVENC and fell back to x264.

### What it means

* **1080p30 (the current live profile) is the stable choice.** It holds a locked 30 FPS with 1% lows of 28.8-30 in
  every scene. The GPU idles at low clocks (14-21 W, 57-65 C), which leaves wide headroom for OBS, voice, LLM and
  browser sources on the same machine.
* **1080p60 is achievable but not yet comfortable while streaming.** Without encoding it holds 60 FPS (1% lows of
  57-60). With a 1080p60 NVENC encode running alongside:
  * calm scenes stay perfect;
  * the dense forest dips (1% low 38, p99 23 ms: visible stutter);
  * the fight sits at 81 % GPU (100 % peaks; 1% low 54.5).

  Uncapped, the fight's 1% low is only 42 FPS, so there is little margin left for OBS's capture and compositing.
* **The CPU is the thermal limit, not the GPU.** The i5-13420H package reaches 94-96 C in every configuration,
  including at 30 FPS in the forest, village and fight. That is close to its throttle point while it does
  relatively little work: 10-30 % system load, and Godot itself 0.3-2 cores. It looks like the laptop's
  cooling/power policy (or other processes) rather than the game. Long 60 FPS streams would sit there continuously.
* **Recommendation:**
  * keep **1080p30 for live streams**;
  * use **1080p60 for offline recordings and reels** (Movie Maker, or the QUALITY profile);
  * consider 60 FPS live only after the forest and fight frame spikes are reduced (foliage LOD / shadow distance in
    the dense woods, VFX particle budgets in fights) and the CPU temperature is addressed (cooling pad, fan profile).
* Movement, physics and animation are unchanged: frame-rate-independent code paths were not touched. Only the
  test run's `Engine.max_fps` and VSync mode were overridden.
