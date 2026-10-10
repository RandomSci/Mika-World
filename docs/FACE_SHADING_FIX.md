# Mika's black face in interiors — root cause and fix

## Symptom
In point-lit interiors (Ancient Spell Library) Mika's face rendered almost black ("dark mask") while hair, body and outfit looked
normal. Outdoors it looked fine.

## Investigation (measured, see `scripts/face_test.gd`, screenshots in `screenshots/face/`)
1. Dumped the VRM/MToon materials: face and body skin both use `mtoon_cutout*` + outline pass; the face differs by
   `_ShadeShift = 0.71` (body −0.20).
2. Read the MToon port (`addons/Godot-MToon-Shader/mtoon_common.gdshaderinc`): for non-directional lights it uses
   **black** as shade colour, halves the light, and (Godot-specific code) thresholds distance attenuation by `_ShadeShift`.
   With 0.71, any omni light whose attenuation at the face is < ~0.71 contributes **zero** → only weak ambient remains.
3. Compared with the source VRM: `Mika.vrm` is **VRM 1.0**; its face has `shadingShiftFactor = 0.71`. In VRM 1.0 MToon,
   `shading = N·L + shift` — a *positive* shift means **more lit** (VroidStudio makes faces flat-lit). godot-vrm copies it
   straight into MToon 0.x `_ShadeShift`, where a positive value means **more shaded**. Sign/semantics error → the face was
   lit only where N·L > 0.72.

## Fix (both parts required; original textures, shade colours, outlines and expressions untouched)
1. `WorldCharacter._fix_vrm1_mtoon_shading()` converts every MToon material (and its outline pass) of a VRM 1.0 avatar:
   `S0 = −shift − (1 − toony)`, `T0 = 1 − 2(1 − toony)/(1 − S0)` (matches ramp centre and width).
   Face (0.71, 0.91) → (−0.80, 0.90). Body (−0.20, 0.80) → (0.00, 0.59).
2. `_Vrm1Lighting` uniform added to the project's copy of the MToon shader: for VRM 1.0 materials, point/spot lights shade
   between shade and lit colour with smooth attenuation (MToon 1.0 behaviour) instead of black + threshold.
   Without (2) the corrected parameters made white hair look brown under candle light.

`--mtoon-legacy` reproduces the old behaviour for comparison.

## Verification (before → after face luminance / screenshots)
* Library daylight front, ¾, side; night; mid-cast — black mask → natural skin with eyes and blush.
* Sanctuary day / night / casting — no regression; daylight face loses the patchy half-shadow (cleaner anime look).
* CINEMATIC and LIVE_OPTIMIZED profiles.
