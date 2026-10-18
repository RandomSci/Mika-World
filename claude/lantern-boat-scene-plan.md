# Lantern boat at Lantern Lake: plan (queued after the Starlit Harp proof; nothing built)

Selwyn, Oct 19 2026. At night Mika and Luna sit in a small wooden boat that drifts and bobs on Lantern Lake. One of them rows. They light paper lanterns with a small spark of magic from their hands, the glow lights their faces, then they release the lanterns into the sky or onto the water.

## The boat: what to generate with Atlas Tripo
**Prompt:**
> small wooden rowing boat for two people, anime fantasy style, warm varnished planks, two bench seats, short curved wooden lantern posts with iron hooks at bow and stern, two oars resting in oarlocks, gentle upturned bow, clean simple shapes, no people, no lanterns

**Specs to ask for:**
- Length about 3.2 m, beam about 1.2 m, seat height about 0.25 m above the floor boards (I'll scale it in Blender).
- One mesh; the oars as separate objects if Tripo allows (they get animated).
- Under 15k triangles.
- One 2k texture: base colour, plus normal if available. No baked lighting or shadows in the texture.
- Export as GLB, origin at the waterline centre.
- Two or three variants to choose from.

**What I'll do with it:**
- Clean it up in Blender: scale, pivot, separate the oars, a hook bone or empty for each lantern.
- Add a simple box collision for the hull, plus the seat tops, so the seated drape (SkirtDrape) samples the real seats.
- Give it the painted toon material from the stylized-environment plan.

## The scene (about 60–90 s, a scripted night sequence at Lantern Lake)
1. **Wide establishing shot:** the dark lake, the boat a small warm glow at the centre, the far shore lanterns, stars and the Milky Way. A slow push in.
2. **Boat motion:**
   - A gentle procedural bob (two sine waves on pitch and roll, about 2–3 cm of heave).
   - A slow drift along a spline.
   - The rower's oar strokes timed to small pushes forward, each stroke leaving ripple rings (a water decal and ring shader).
3. **The girls:**
   - Both sit (the general sit fix, seat colliders from the boat's seat tops).
   - Mika rows, using a rowing loop: Mixamo has "Rowing" (owner downloads), or keyed in Blender. Luna sits facing her.
4. **Lighting the lanterns:**
   - A close-up insert of a hand: fingertip spark (the harp spark plus a tiny flare), the paper lantern's inner flame igniting, the paper glowing warm.
   - Each lantern carries an OmniLight3D (warm, short range) that lights their faces.
5. **Face close-ups by lantern light:** soft warm key from below and the side, a cool moon rim. Expressions: soft smile, wonder.
6. **Release:** they lift the lanterns and let go.
   - Sky lanterns rise slowly with a slight sway, plus spawned lanterns from the shore.
   - Floating lanterns are set on the water and drift away with reflections.
7. **Crane up:** the camera rises slowly as the lanterns climb, revealing dozens across the lake and sky. Hold on the wide, then a slow fade.

## Pieces to build
- **Lanterns:** a paper lantern mesh (made in Blender by script: a lathe of rice paper ribs with a wire top) and a translucent paper shader with a flame glow inside (HDR emission, flicker). Sky and water variants, with an instanced swarm for the wide shots.
- **Water:** reflections and lantern glints on the existing Lantern Lake water (to check: planar or SSR), plus ripple rings at the oars and the lanterns.
- **Camera:** Phantom Camera shots (wide, close-ups, insert, crane) through PCamDriver.
- **Dresses:** design B, the drape on the boat seat, and the skirt over the boat's side.
- **QA:** fps through the stream pipeline, with many lights. The lanterns use a few real lights near the camera and emissive-only sprites far away.

## Needs from Selwyn
- The boat from Atlas Tripo (prompt above), and the Mixamo "Rowing" clip if he wants mocap-quality rowing.
- Which girl rows (default: Mika rows, Luna lights the first lantern).
