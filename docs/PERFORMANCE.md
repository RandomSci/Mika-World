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
* The remaining hitches are first-use costs (a shader or effect seen for the first time); they show as single
  frames of 100-150 ms at fight start. Pre-warming the combat effects at area load would remove most of them
  (*planned*).
