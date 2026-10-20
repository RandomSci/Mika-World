FX VIDEO TEST v1 (Oct 20 2026), video to effect

4 effects made with Wan 3.0 Prime text to video on Atlas (4 s, 720p, pure black background), cut to 64 frame 8x8 flipbooks (512 px per frame, 16 fps, centre square crop), near black crushed, soft round edge fade.
check_on_game_frame.jpg shows each one composited additively on Selwyn's own game screenshot.

mika_petal_vortex_8x8.webp   petal streams swirl into a ball, then burst and scatter. Cast build up or aura.
mika_petal_burst_8x8.webp    flash, shockwave ring, petals blast out and flutter down. Impact or release.
luna_crescent_slash_8x8.webp crescent arc, ring of crescents, horizontal slash streak, violet dust. Luna slash.
luna_moon_pillar_8x8.webp    moon sigil on the ground with a light pillar and orbiting crescents. Luna ground spell.
Source clips are left out of this light version.

How to use in Godot
1 A QuadMesh card (MeshInstance3D) with flipbook_fx.gdshader, sheet set to one webp. It always faces the camera.
2 A small script animates the uniform frame from 0 to 63 over the effect time (about 4 s, speed it up or slow it for timing), starting at the gesture release frame, at the casting hand or target.
3 Size the card 2 to 4 m. Keep intensity above 1 so the glow catches bloom. Raise black_cut if a faint haze disc shows.
4 Add one OmniLight3D in the effect colour that follows the effect brightness, so the ground and the girls catch its light.
5 For the moon pillar, which has a ground sigil drawn in perspective, use it from the main camera angle only, or later replace the sigil with a flat ground decal.
Each clip is one fixed animation. Make 2 or 3 versions per spell and randomise scale, rotation and speed for variety.
