# VFX style guide - Mika & Luna

Every power effect (spells, auras, transformations, fights, impacts) follows these rules. "Simple" is not allowed:
each effect is layered, timed and coloured for its character, and it must still hold 30 fps on the stream laptop.

## 1. Each character's light

| | Mika | Luna |
|---|---|---|
| Element | wind, growing things, starlight | moonlight, shadow, gold |
| Core (white-hot) | pure white, faint periwinkle | pure white, faint gold |
| Body | silver and periwinkle (#B9C4FF / #8C9EFF) | gold and violet (#FFC85A / #8A5BFF) |
| Edge / smoke | deep blue night (#1E2A78) | deep violet shadow (#2A0F4A) |
| Signature shapes | star flowers, petals, spirals of wind, sparkles | crescent moons, shadow wisps, gilded runes, mirrored shards |

## 2. Shape, timing, colour (every effect)

- **Shape:** a readable silhouette at stream size (wide or medium camera, never a face close-up); a clear direction.
- **Timing - three beats:** anticipation (the charge: glow gathering, particles pulled inwards, the space around her
  darkening a touch) -> the strike (fast) -> the fade (slow, so viewers register what happened). Most of the felt
  power comes from the anticipation. At 30 fps: anticipation 6-18 frames, strike 2-6, fade 10-30.
- **Colour in layers:** a white additive core (bloom catches it), a saturated mid in the character's colour, a darker
  or complementary edge (alpha blended). Test against both the bright day and the night sky.
- **Every effect ends:** it fades, dissolves or leaves a short residue - nothing loops forever.

## 3. Impacts

- Big hits only: an **impact frame** stack of one-frame passes - background darkened, a flash frame, radial speed
  lines, the silhouette inverted - plus a radial shockwave and a brief colour shift; then back.
- **Hit stop:** 1-2 frames (33-66 ms) on big hits only (a demo-sized 0.3 s freeze reads as lag on stream).
- **Knockback:** strong at first, eased out. **Hit flash:** the struck body flashes white for 1-2 frames.
- Camera shake: small and short; the lens stays wide/medium.

## 4. Budget (the stream's GPU is shared: see the duel lag of 2026-10-17)

- Nothing is built during a fight: effects are instanced and pre-warmed (drawn once, off screen or under a flash)
  before the fight and **pooled**; the shader pipelines exist before the first cast.
- No extra real-time lights for effects: emission + bloom instead.
- Overdraw is the main cost: few large transparent quads near the camera; particle counts follow RenderProfile.
- Hold 30 fps; every effect has a lower-quality fallback.

## 5. Sources and licenses (only these)

See `~/Downloads/Mika_Asset_Sources/LICENSES.md`. In short: Quaternius UAL 1/2 (CC0), GODOT-VFX-LIBRARY (MIT),
VFX Sketchbook by Thibaud Goiffon (MIT - credit "<VFX name>" from VFX sketchbook by Thibaud Goiffon), GDQuest
VFX assets (MIT code and shaders ONLY - their textures and models are non-commercial and never used), OBKF trails
(MIT), godotshaders.com shaders marked CC0 or MIT, Brackeys VFX bundle (CC0), Binbun3D free packs (CC0). Custom anime
textures: generated for this project (Gemini). Never: the Bandai Namco motion dataset (non-commercial).

## 6. References

- Impact frames as layered passes: https://realtimevfx.com/t/easy-impact-frames-for-unreal-engine-and-unity/30252
- One-frame post passes over 12 frames: https://80.lv/articles/my-hero-academia-style-attack-vfx-in-unreal-engine-5
- Shape / timing / colour framework: https://playbooks.com/skills/omer-metin/skills-for-antigravity/vfx-realtime
- Hit fast, fade slow: https://realtimevfx.com/t/vfx-blue-fire-burst-with-spear/24180
- Juicy attacks (anticipation, smear, ease, hit flash, hit stop): https://www.gdquest.com/library/juicy_attack/
