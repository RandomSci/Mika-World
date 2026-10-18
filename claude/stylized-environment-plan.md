# Stylized environment pass: plan (starting with the ruins), Oct 18 2026

## Why
Selwyn's bench screenshot shows the rocks, moss, bench and ground as photo-scanned PBR textures (Poly Haven,
ambientCG) next to an anime character. In the references (videos 5 and 6, Genshin, Wuthering Waves) the world is
painted:
- flat value groups and soft gradients, not photographic micro-detail;
- few colours per material (2–3 values, a hue shift in the shadows);
- the world desaturated so the character and effects own the colour (breakdown rule 2).

## Steps
1. **A toon-friendly world shader** (`shaders/world/painted_surface.gdshader`), used in place of StandardMaterial3D on stone, ground and wood:
   - **Albedo:** the photo texture is low-passed (a mip bias of +2, or a pre-blurred copy), then posterized into 3 value bands and remapped through a per-material palette ramp (for example, ruins stone: cool grey-violet shadow, warm sand light).
   - **Lighting:** a 2-step ramp (light / shadow) with a soft edge, and a hue-shifted shadow colour (blue-violet), not black.
   - **Detail:** large shapes only. Moss becomes painted patches with a soft edge mask, from the existing moss mask.
   - **Normals:** the normal map's strength is cut to about 30% (no pebbly micro-relief).
   - **Edges:** a thin edge highlight on rock silhouettes (a fresnel rim), as on Genshin rocks.
2. **The ruins first**, around the watchpoint bench (scripts/world/sanctuary.gd, kit_area materials): the bench, the walls, the floor slabs, the columns and the moss.
3. **Ground and grass:**
   - The terrain gets the same painted treatment, with 2–3 green values and a warm dry tint on paths.
   - Stylized grass: GPU MultiMesh blades (curved quads with a root-to-tip gradient and wind sway), dense near the camera and fading out at about 25 m. The existing grass placement is reused.
   - Budget: under 1.5 ms at 30 fps on the RTX 5050. Measured, and denser only where the camera actually looks.
4. **Trees (item 5, measured):**
   - The background trees are Poly Haven jacaranda models with 1k leaf cards and alpha scissor. At 30–150 m the leaf mips collapse into blocks, and the sky shows through as white squares.
   - Fix: alpha-to-coverage, or alpha hash plus a mip-preserving alpha bias on the far LOD's leaf material. The far LOD gets painted leaf-clump cards, which hold a silhouette instead of noise.
   - Longer term: stylized trees, with clumped leaf cards and normals edited towards a sphere (the Genshin foliage technique).
5. **Per-area colour grade:** a post grade per region (ruins: cool morning; meadow: warm), with low saturation in the world and full saturation kept on the characters (a mask from the character light layer).
6. **QA:** the same bench shot before and after, plus the 8-direction benchscan sheet, judged against reference frames v6_026.5 (moonlit field) and v5 (the stone arena) for the painted stone look.

## Found while scanning (item 6)
- **Stray pole:** the Lantern Lake waymark had only its night light, so by day it was a bare post. Fixed: it now carries an arm and a lantern (ddc869c). From far away it still reads as a thin post; if it bothers you in that view, it can move 3 m off the sight line.
- **Floating leaf clump:** none found within 45 m of the bench. The scan lists floating meshes, and only expected ones came up (lantern, table top). I need the screenshot or the camera position to find it.
- **Also seen:** a white crenellated shape above the ruin wall in the side view. Most likely a distant vista impostor (castle silhouette) showing through the fog. To check in the same pass.
