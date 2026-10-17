# Luna's face reshape (Blender 4.2 + VRM Add-on, background)

1. `blender -b --python import_vrm.py -- <LunaOracle_L1Outfit.vrm> <work.blend>` (the shipped VRM; the lab's saved .blend
   predates its last two sleeve spring chains, so the round trip starts from the VRM itself)
2. `blender -b <work.blend> --python reshape.py -- luna_l1_params.json <out.blend> <out.vrm>`
3. `blender -b <out.blend> --python render_head.py -- <prefix> [1|0 hair]` for front / three-quarter / side checks

One smooth deformation field moves the face mesh and every shape key (each key's own positions, so blinks and visemes
fit the new eyes and mouth), the blush mesh, the front hair (curtain bangs, kept on the forehead's curve) and the eye
bones. Shorter face, rounder chin, fuller cheeks, mouth higher and smaller, bigger rounder eyes a little lower and
closer, smaller nose, longer upper lashes, brows lifted clear of the bigger lids. Textures are unchanged (UV-mapped,
so tools/face_style/make_luna_face.py's eyes, lips, lashes and blush ride the new shape).
