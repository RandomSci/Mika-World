"""Mika L1 outfit v2 (Selwyn 2026-10-20): the look prototype's inputs for the v2 outfit, laid out like look_proto/maps
and l1_flat/flat so the look lab runs on it with --maps and --l1tex.
  maps: ramp.png and face_sdf.png from look_proto/maps, the kept pieces' ILMs from there, and an ILM per v2 material
        from its palette texture (Genshin lightmap layout as tools/t03_look_maps.py: R specular, G shadow threshold,
        B specular size, A ramp row / 16; white row 1, navy row 2 shading a little sooner, gold row 3 with specular,
        sky blue row 6)
  flat: the kept pieces' cleaned base colours from l1_flat/flat (the v2 parts use their own VRAM compressed textures);
  flat_v2: the v2 bakes and the palette swatch uncompressed, for comparison; the same pngs go to the test build
  python3 l1_v2/tools/v2_lookmaps.py"""
import os, shutil
import numpy as np, cv2

LAB = '/home/selwyn/Downloads/Mika-Transformation-Lab'
V2 = LAB + '/l1_v2'
MAPS, FLAT = V2 + '/look/maps', V2 + '/look/flat'
# the v2 base colours go to look/flat_v2 (uncompressed, for A/B against the build's own VRAM compressed textures,
# which the lab uses when --l1tex points at look/flat) and to the test build's texture folder in anime-proof
FLAT_V2 = V2 + '/look/flat_v2'
TEX = '/home/selwyn/Downloads/Mika-Godot-Dev-Anime/assets/characters/mika/tests/l1v2_tex'
for d in (MAPS, FLAT, FLAT_V2, TEX): os.makedirs(d, exist_ok=True)
for f in os.listdir(FLAT):
    if f.startswith('L1_v2_'): os.remove(f'{FLAT}/{f}')
PAL = np.array([[0xF4, 0xF4, 0xFA], [0x1C, 0x25, 0x56], [0xD8, 0xB2, 0x6A], [0x6F, 0xA8, 0xE8]], np.int32)
# white, navy, gold, sky -> (ramp row, spec strength, spec size, threshold), as t03's LABEL
LUT = np.array([[s, th, z, (row + 0.5) / 16] for row, s, z, th in
                [(1, 0.0, 0.0, 0.5), (2, 0.0, 0.0, 0.42), (3, 1.0, 0.55, 0.5), (6, 0.0, 0.0, 0.5)]])
for f in ('ramp.png', 'face_sdf.png'):
    shutil.copy(f'{LAB}/look_proto/maps/{f}', MAPS)
for p in ('Shoe', 'Bracelet', 'HairFlower', 'BackBow'):
    shutil.copy(f'{LAB}/look_proto/maps/L1_{p}_ILM.png', MAPS)
    shutil.copy(f'{LAB}/l1_flat/flat/L1_{p}_BaseColor.png', FLAT)
sw = np.zeros((16, 64, 3), np.uint8)
for k in range(4):
    sw[:, k * 16:(k + 1) * 16] = PAL[k]
cv2.imwrite(V2 + '/look/swatch.png', sw[..., ::-1])
SRC = {'Under_A': 'under_p0', 'Under_B': 'under_p1', 'Bodice': 'bodice_core', 'Sash': 'sash', 'Collar': 'collar', 'Bow': 'bow', 'Brooch': 'brooch',
       'Sleeve': 'sleeve', 'Panel': None, 'Star': None}
for piece, part in SRC.items():
    src = f'{V2}/bake/MIKA_L1_{part}.png' if part else V2 + '/look/swatch.png'
    im = cv2.imread(src)[..., ::-1].astype(np.int32)
    lab = ((im[..., None, :] - PAL[None, None]) ** 2).sum(-1).argmin(-1)
    shutil.copy(src, f'{FLAT_V2}/L1_v2_{piece}_BaseColor.png')
    shutil.copy(src, f'{TEX}/L1_v2_{piece}_BaseColor.png')
    ilm = (LUT[lab] * 255 + 0.5).astype(np.uint8)
    if ilm.shape[0] > 2048:
        ilm = ilm[::2, ::2]                                              # nearest, the material ids stay exact
    cv2.imwrite(f'{MAPS}/L1_v2_{piece}_ILM.png', cv2.cvtColor(ilm, cv2.COLOR_RGBA2BGRA))
    print('ILM', piece, ilm.shape)
