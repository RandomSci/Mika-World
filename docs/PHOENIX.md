# Oriel, the Ember Keeper — the Phoenix (V3 Part X, Milestone K6)

Mika World's first legendary dual-form creature: **one character, two bodies, one memory, one voice**.
Everything here is original (models scripted in Blender from nothing, textures drawn with numpy, sounds
synthesised, lines written for her) and everything is verified inside the running game
(`--mktest=phoenix`, 31 checks after visual pass 2; reel `--mktest=phoenix_reel`).

## Who she is (story)

Oriel is the oldest witness of the Keepers. Every Keeper's hearth was lit from one flame — hers — and when the
First Circle left for the south they carried that fire with them, which is why the Heartstone has counted two
beats ever since (its third beat was the hearth-fire's). She sleeps at the Celestial Summit's sun-shrine and
wakes when a circle answers someone. Mika woke the Sanctuary's circle; Oriel comes down to the Whispering
Woods' viewpoint to see who did it, lights the old fire bowls there, and — when Mika comes close — takes her
human form to look her in the eye. She is not an enemy: she tests and teaches (`data/phoenix.json`: identity,
lines, beats, knowledge she can teach, where she lives and when she visits).

## True form (`assets/creatures/phoenix/phoenix_true.glb`) — visual pass 2 (after the developer's references)

Built by `tools/models/build_phoenix.py` (Blender 4.2, headless, deterministic). Pass 2 rebuilt her look after
the developer's two phoenix references (a gold-and-flame display pose; a red fire-bird with flame wisps):

* **Silhouette**: ~2.9 m standing; the wings are far greater (primaries 1.7–2.55 m, secondaries 1.4–1.6 m), so
  her **display pose** (`majestic`) raises them high and open toward the viewer like the references — a pose
  solver mode (`display`) aims each wing segment up-and-out and rolls it so the feather fans hang in the frontal
  plane, showing the golden underside, the primaries sweeping up at the top. A slimmer, upright body, a long
  S-neck under a mane of lanceolate hackles, a smaller falcon head (dark raptor eye, bronze-gold hooked beak),
  a tall crest of streamer plumes with two gold flame-horns, dark-red scaled legs with black talons.
* **Plumage colour**: every flight feather burns from a **dark crimson root to a golden-orange tip** (deep
  roots give the wing its structure; the tips are the fire); greater coverts scarlet, median coverts amber-gold,
  and the marginal coverts, the alula, a **gold gorget** where neck meets breast and a **gold crown** are
  ornate **gold filigree** (metallic). The train: two side plumes and three central plumes, crimson → magenta
  → violet, each ending in a **curl**, over a nine-feather tail fan.
* **Fire** (`shaders/phoenix/feather.gdshader`, `flame_card.gdshader`, `fx_sprite.gdshader`,
  `aura_halo.gdshader`): each feather burns from within toward its end with a slow flicker (saturated so AgX
  never turns it pastel), the outer third sways like a flame and the tips flicker in and out as **flame
  licks**; **flame tongues** (additive cards re-drawn every frame through scrolling noise) trail from every
  flight feather, tail feather, plume and crest plume; flame wisps rise from her wingtips and train; sparks
  drift around her; a soft **halo of firelight** stands behind her; her chest light warms the ground.
* **Atlas** (`tools/models/phoenix_textures.py`, 2048², 4×2 long cells): flight feather with separated barbs
  curling into flame licks, scale/contour feather with a bright rim, gold filigree covert (volutes, rib,
  enamel inset, G = metal), flame tongue, hackle plume with a fringed edge, tail streamer, down, spark glint.
* **Armature (110 bones, unchanged names)**: body chain, neck, head, lower beak, crest, eyes, wing arm chains,
  **one bone per flight feather**, tail feathers, 3-bone streamers, legs with four toes.
* **Clips (33)**: the 25 of pass 1 plus `majestic` (her display, looping), `majestic_enter`, `wing_wrap` (the
  cocoon of wings), `wing_burst` (out of the fire), and the power attack: `attack_charge`, `attack_hold`,
  `attack_release`, `attack_recover`.

## Her power attack — the SOLAR NOVA (`scripts/phoenix/phoenix_nova.gd`)

Against a creature (true form; `Phoenix.cast_nova`, used by `cast_flare` for creatures): she rears with her
wings flung high and back while a **sun-orb** gathers before her breast — living flame around a white-hot
heart, a starburst glare, fire drawn into it from the air around her, a rising light and an inhaling roar
(`phoenix_nova_charge`); a held beat of tension; then a full **downstroke** drives it forward with a shock
ring from her chest, a flash, a camera kick and her cry (`phoenix_nova_release`); it flies at 24 m/s trailing
a river of flame and embers; the **detonation**: a flash of light, a fireball that swells and burns out, flames
thrown outward, a ring of shock along the ground, a rain of embers, smoke, a scorch that fades over ten
seconds, a camera shake and a deep detonation (`phoenix_nova_impact`). The target answers with its own
`react("fire", ...)` (damage through its resistances) — judged, not shown. Her gentle sunflare (`PhoenixFlare`)
still lights the bowls and is her human-form cast.

## Human form — the developer's Zahra, restyled as Oriel (`scripts/phoenix/phoenix_human.gd`)

At the developer's request her human body is **Zahra** (`assets/characters/phoenix/Zahra_DesertDancer.vrm`), a
VRM from the developer's own Character Lab (`Mika-New-Character-Lab`, author: the developer), **copied** into
the project (the source file is untouched). The VRM file itself is never modified; her look is restyled at
runtime as material overrides (`tools/textures/oriel_zahra_recolor.py` → `assets/characters/phoenix/
oriel_zahra_tex/`): a deep crimson hood edged in gold, a flame veil, an ivory-gold top, a gold collar, crimson
pleats burning to ember at the hem, auburn-crimson hair, molten-gold eyes, crimson silk where the arm-warmers
were, a ruby and a fire opal for the gems, an ember sash. Everything else — VRoid-grade face, blend-shape
expressions, blinking, lip sync, spring-bone hair and skirt, the shared clip library — is `WorldCharacter`'s.
(The pass-1 procedural body and the Luna-based restyle remain in the repo, unused.)

## The transformation — a magical-girl sequence of her own (`scripts/phoenix/phoenix.gd`, `phoenix_human.gd`)

Researched structure (the classic transformation: a body of light, each part made in turn, a spin, the crown
last, a final pose), made original to her — fire instead of ribbons of light, a phoenix instead of a brooch:

**Phoenix → woman, cinematic (10.4 s; the swap on the music's hit at 3.4 s; seven camera beats)**
1. *Display* (0–1.5 s) — she rises into her display; the fire wakes (heat, halo, glow); **the world dims into
   her light** (sky, ambient and sun fall away, a warm vignette closes in — restored exactly after).
2. *The cocoon* (1.5–3.4 s) — her wings sweep forward and close around her; a veil of burning feathers
   spirals up; her plumage burns from the far ends toward her heart into a core of fire.
3. *The light-body* (3.4 s) — a flash: inside the fire stands a woman of **white-gold light** (a glow pass
   over her whole body: no detail, a rim of fire), arms crossed over her heart, rising off the ground.
4. *Her making* (seconds after the swap): **hair** from the crown down as her hands sweep through it (0.15–1.0);
   **sandals**, ribbons of flame winding up her legs, one knee raised (1.5–2.3); **a full pirouette** while
   the **skirt** is made from the waist down (2.35–3.4); **each arm** offered in turn, ribbons along it
   (3.75–4.6); the **bodice and collar** outward from her heart (4.25–5.0); a hand to her brow and the **hood,
   veil and circlet** (5.0–5.6) with a burst of sparks; **phantom wings of flame** open behind her (5.4–6.6) as
   she descends into her **final pose** — a hand on her hip, the other raised, a smile. The light cools away
   part by part; each part ends in a spark burst.
5. The world returns; she looks at Mika.

Every garment surface draws through a reveal variant of its own MToon shader (`tools/shaders/make_mtoon_reveal.py`
→ `shaders/phoenix/mtoon_reveal.gdshaderinc` + `reveal_mask.gdshaderinc`: per-part sweeps with a burning seam,
the gold and gems revealed with the body part they sit on) plus the light-body pass (`reveal_glow.gdshader`);
the shaders are compiled before the swap (she is drawn invisible while the bird is still on screen), and after
the sequence her normal materials return (no cost in normal play). Flame ribbons: `scripts/phoenix/flame_ribbon.gd`.
The choreography is authored as poses solved on her own skeleton (`scripts/characters/pose_author.gd`).

**Short** (4.2 s, hit 1.6 s): straight into the cocoon, every part made at once in a rush of light. **The way
back** (9 s, hit 4.2 s): her parts unmade into ribbons of fire in reverse (the crown first, the hair last) as
she rises spinning with wings of flame opening from her back; a pillar of fire; the bird **bursts out wings-
first** (`wing_burst`), plumage growing from her heart outward, her cry, her display. Sounds re-composed for
these beats (`tools/audio/synth_phoenix.py`; a sparkle at each part made).

## The cinematic pass (2026-10-14) — the developer: "the attack looks so simple ... nothing special in the transformation ... the sound made it low quality ... the wings produce powerful wind so why are the trees not affected ... the body goes through things"

- **Real fire.** Every flame, fireball, burst, smoke plume and the fire tornado is a simulated flipbook (Blender
  Mantaflow gas sims rendered in Cycles: `tools/vfx/fire_flipbooks.py`, packed by `tools/vfx/pack_flipbooks.py` into
  `assets/vfx/fire/`). Drawn by `shaders/vfx/flipbook.gdshader` (fire light HDR + lit smoke, premultiplied, frame
  cross-blend, soft where it meets geometry). Building blocks: `scripts/magic/fire_fx.gd` (`FireFX`), `fire_vortex.gd`.
- **The nova is an aerial attack** (`Phoenix.cast_nova`): she springs up on two wingbeats (≈5 m), charges in the air
  (white-hot heart inside churning simulated fire, fire drawn in, heat haze, a light that grows to light the clearing),
  holds, throws it with a downstroke (recoil, a gust below her, her scream), it flies trailing rolling fire and smoke,
  and `FireFX.explosion()` detonates: shadow-casting flash, three layered blasts, fire flung out, smoke rising, shock
  ring + dust skirt, debris that lands, a scorch whose cracks glow and cool, fires left burning (crackling), a gust
  that bends the forest and tears its leaves, camera shake. She then sinks back to her perch. The old camera-facing
  glare quad (which cut a bright bar through her wing) is gone; every card fades softly into geometry.
- **The transformation:** a ring of fire catches round her, a fire tornado (a turning wall of simulated fire columns)
  rises over her and roars to the hit, bursts outward at the swap (fire, shock ring, dust, a huge gust); while the
  woman is made, sparkles; at the end wings of fire unfold behind her. The reform mirrors it. The old core sphere is
  now only the white heart inside the tornado.
- **Wind** (`scripts/world/gusts.gd`, `shaders/nature/gust.gdshaderinc`, `scripts/world/wind_fx.gd`): every big
  wingbeat, her landing and takeoff, the blasts and the transformation emit gusts — a wave that runs out at 17 m/s and
  bends every registered plant (real trees trunk and crown together, scanned shrubs/ferns/nettles, the stylised kit,
  grass) away from it with a damped swing back; big ones tear real scanned leaves from the crowns and drive litter
  and dust along the ground. 197 plant materials register in the Woods.
- **No clipping:** `scripts/phoenix/wing_clearance.gd` (a SkeletonModifier3D after the gaze) tests her outer primary
  tips and train against the real ground/stones/walls under them every frame and swings the wing (or train) up just
  enough; verified lowest tip 0.14 m above the ground through every clip of the test. Her arrival circles at 29 m
  (above the 20–26 m crowns) and descends through the clearing.
- **Sound** (`tools/audio/phoenix_cine_sfx.py`): ElevenLabs layers (best of four by measurement) mixed in **stereo**
  with a look-ahead limiter (no waveshaping), played through the new **Cinematic** bus (`AudioDirector.play_cine`;
  Music/Ambience/SFX duck under it). The cinematic transformation plays an 11 s instrumental orchestral cue whose
  hit lands at 3.40 s, the swap.

## Her voice — Google Gemini TTS, Kore (confirmed; permanent)

`scripts/audio/voice_service.gd`, provider `gemini` (`data/voices.json` → `phoenix`):

* The key is `GEMINI_API_KEY`, read from the project `.env` (that one line only, or the process environment);
  it is never printed, logged, reported or committed. `VoiceService.describe().gemini` reports only that it is
  configured and how many characters long.
* Asynchronous (`HTTPRequest`, 28 s timeout), one retry on a transient failure, none on a refusal; a 429
  pauses cloud synthesis for ten minutes (quota-aware); audio validated (format `audio/L16`, 0.15–60 s, not
  silence) and wrapped as WAV (24 kHz mono).
* **Each distinct line is synthesised once, ever**: shipped lines in `assets/voice/phoenix/` (manifest),
  session lines in `user://voice_cache/gemini/`. Her authored lines are prefetched when she is summoned, so
  the conversation never waits on the network.
* Style steering per form and mood (natural, warm, unhurried; playful / serious / tender); the true form
  speaks through the `VoicePhoenix` bus (a low shelf, two short taps, a little reverb: resonance, not
  distortion). Mika's and Luna's voices are untouched. Local fallback: a Kokoro blend that is neither of
  theirs (`af_aoede:0.55,bf_lily:0.45`), used only when the cloud voice is unavailable.
* Subtitles and the mouth follow the audio's own clock (also fixed for Mika and Luna under Movie Maker).

## In the world

`PhoenixManager` (`scripts/phoenix/phoenix_manager.gd`): when the Whispering Woods are loaded and Mika is
within 40 m of the viewpoint (after 25 s of session, and not within the 15-minute cooldown that spans
restarts), Oriel is summoned: she flies in from the east over the valley (`approach` points, 11 m/s), circles
the viewpoint once, calls, hovers and lands on the centre stone; she lights the two **cold fire bowls** on the
old columns with her sunflares (`PhoenixFlare`: a knot of burning feathers whose impact is judged by whatever
it hits — a brazier's own `react("fire")`, a creature's fire damage through its resistances); when Mika comes
within 9 m she speaks, changes (cinematic the first time, short afterwards) and is then a resident NPC the
dialogue system knows (`main.npcs.present.phoenix`, `DialogueService` beats with her own facts and moods, a
line for Luna when she is there), so Mika's planner can choose to talk with her. She sits at the edge to watch
the valley, walks, casts as a woman. After her stay she says goodbye, becomes the Phoenix again and flies back
toward the summit. Her memory of every conversation persists in the save.

## Verification

`--mktest=phoenix` (windowed 1600×900, live profile, her real voice, a disposable save), visual pass 2:
**31/31 checks PASS, 0 script errors** — the original rigged true form with **33 clips**; she flew in (62.4 m
above the perch at most, banked to 0.65 rad), landed exactly on the perch stone (0.00 m off), lit both cold
bowls with her sunflares; the **solar nova** struck the thornback (outcome *defeated*, judged by the creature);
the **cinematic transformation ran 10.45 s with the swap at 3.45 s** (the composed hit is 3.4 s) with **0.00 m
drift**, collision switched, no T-pose (left hand 0.95 m up); the same identity and memory in both forms; her
Kore voice (Gemini) in human form; a real conversation through the dialogue system (taught Mika, memory
persisted); she sat, walked 3.9 m on the navmesh, cast in human form; **the way back ran 9.02 s (swap at
4.20 s), 0.00 m drift**; she took off and left. Stills: `screenshots/phoenix_v3/mktest/phoenix_*.png`
(tf_bow, tf_close, tf_swap, tf_spin, tf_arms, tf_crown, tf_final, rf_core, rf_wings...). Lab stills of each
stage (fixed 30 fps clock): `scripts/tools/oriel_lab.gd` (`--lab=true|human|tf|tf_short|reform|attack`).

## Known limits (honest)

* The true form's feathers are cards: very close shots show their edges; in full daylight her fire reads as
  glowing tips and flame tongues rather than the bloom-drenched glow of a night key-art (by design: AgX keeps it
  saturated instead of washing it pastel).
* The human form is the developer's Zahra restyled at runtime; the VRM's own garments are kept (no new
  phoenix garments were modelled onto it).
* The transformation's choreography is authored poses (solved on her skeleton), not motion capture.
* Gemini TTS latency for a *new* line is 5–16 s on this connection (hence prefetch + permanent cache); the
  first-ever rendering of an improvised line will still wait.
* No facial bones in the human form (expressions are frames), no eye-look bones (the head turns).
