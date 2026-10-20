class_name PetalArts
extends RefCounted
## The petal arts (2026-10-20, Selwyn: "research how the Bleach character that uses Bankai with the cherry blossoms ...
## and apply it", "it shouldn't be simple"). Our own technique set built on that idea, not its look: every spell is the
## girl's petal storm taking one shape, so the whole fight speaks one visual language and nothing appears out of
## nowhere. The storm she gathers in her hand is the storm that leaves it.
## A technique is layered the way action games build a cast:
##   anticipation   her aura flares (a rim of her colour over her body) and the world dims round her while she gathers
##   release        the gathered storm leaves her hand in the spell's shape (comets, a torrent, a tide, pillars ...)
##   travel         the shape carries its own light, so it lights the ground and the girls as it passes
##   impact         the petals burst where it lands (ImpactPetals), a ring of petals runs over the ground on the heavy ones
##   dissipation    the petals scatter, drift down and settle on the ground before they fade
## The shapes per spell kind (the spell's timing, aim and hits stay MagicCaster's; this only draws them):
##   volley, arrow           comets: a fan of petal daggers, each to its own point
##   orb                     one heavy comet, then the sphere closes round her and crushes (engulf), the ground answers
##   rows, pillars, array    columns: spiralling petal spires erupt from the ground in sequence toward and round her
##   beam                    stream: a held torrent from her hand to the target
##   sky, seal               cascade: a funnel of petals pours down from the sky onto her
##   meteor, eclipse         comets falling from above (the eclipse: a hanging sphere rains them, then drops)
##   vortex                  a single moving column opening at the top (a petal tornado) crossing the ground
##   wave, crescent          tide: a curling wall of petals rolling at her (on the ground / in the air)
##   domain                  a ring of spires round her, a funnel over her, a ripple out to the domain's edge

var sim: MeleeSim
var _dim_n := 0
var _aura_mat := {}
var _k_count := 1.0                         # the storms' petal count factor (a thin extra layer under a video card)

## The video cards (FlipbookFX, Selwyn's FX_Video_Test_v1): the main look where one fits; particles add to them.
##   Mika      every spell: the petal vortex at her hand through the gather, the petal burst at the release and where
##             it lands
##   Luna      her slash spells (moon_crescent, tide_crescent, her scythe and greatsword swings): the crescent slash;
##             her ground spells (thorn_array, moonlit_pillars): the moon pillar on the other girl's ground
const LUNA_SLASH := ["crescent", "wave"]
const LUNA_GROUND := ["array", "pillars"]
const CARD_EXTRA := 0.3                     # the particle count left as the extra layer under a card


static func carded(who: String, kind: String) -> bool:
	if not FlipbookFX.enabled():
		return false
	return who == "mika" or kind in LUNA_SLASH or kind in LUNA_GROUND or kind == "weapon"


static func make(s: MeleeSim) -> PetalArts:
	var a := PetalArts.new()
	a.sim = s
	return a


func _storm(who: String, count: int, size: float, gy: float) -> PetalStorm:
	var st := PetalStorm.make(sim.d.main, who, maxi(int(count * _k_count), 60))
	st.petal_size(size)
	st.ground(gy)
	return st


static func _fix(p: Vector3) -> Callable:
	return func() -> Vector3: return p


# ------------------------------------------------------------------------------------------------ anticipation

## Her aura through the gather: a rim of her colour over her whole body, up over `rise` seconds, held to the release,
## then down. The world round her dims while it is up (dim), so she is the brightest thing on screen.
func aura(f: MeleeFighter, who: String, rise: float, hold: float, big: bool) -> void:
	var m: ShaderMaterial = _aura_mat.get(who)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = load("res://shaders/magic/aura_rim.gdshader")
		m.set_shader_parameter("col", Vector3(0.55, 0.85, 1.0) if who == "mika" else Vector3(0.78, 0.5, 1.0))
		m.set_shader_parameter("petal", Vector3(1.0, 0.55, 0.78))
		_aura_mat[who] = m
	for mi in f.sk.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_overlay == null or (mi as MeshInstance3D).material_overlay == m:
			(mi as MeshInstance3D).material_overlay = m
	var peak := 1.0 if big else 0.6
	var kit = sim.get("ult_kit")
	if kit and is_instance_valid(kit) and String(kit.who) == who:
		peak = 0.45                                   # (an ultimate's close-ups: her colours stay, no white burn)
	var tw := f.sk.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("k", v), 0.0, peak, maxf(rise, 0.1)).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(hold, 0.0))
	tw.tween_method(func(v: float): m.set_shader_parameter("k", v), peak, 0.0, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		for mi in f.sk.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).material_overlay == m:
				(mi as MeshInstance3D).material_overlay = null)
	if big:
		dim(rise, hold)


## The world dims (exposure down a little, colour up) for a big gather, back at the release.
func dim(rise: float, hold: float) -> void:
	var we: WorldEnvironment = null
	for n in sim.d.get_tree().root.find_children("*", "WorldEnvironment", true, false):
		we = n
		break
	if we == null or we.environment == null:
		return
	var e := we.environment
	if e.has_meta("domain_saved"):
		return                                      # (a domain already holds the grade)
	if _dim_n == 0:
		e.set_meta("dim_saved", [e.adjustment_enabled, e.adjustment_brightness, e.adjustment_saturation])
		e.adjustment_enabled = true
	_dim_n += 1
	var sv: Array = e.get_meta("dim_saved")
	var tw := sim.d.create_tween()
	tw.tween_property(e, "adjustment_brightness", float(sv[1]) * 0.9, maxf(rise, 0.1))
	tw.parallel().tween_property(e, "adjustment_saturation", float(sv[2]) * 1.08, maxf(rise, 0.1))
	tw.tween_interval(maxf(hold, 0.0))
	tw.tween_callback(func():
		_dim_n -= 1
		if _dim_n > 0 or not e.has_meta("dim_saved"):
			return
		var tw2 := sim.d.create_tween()
		tw2.tween_property(e, "adjustment_brightness", float(sv[1]), 0.35)
		tw2.parallel().tween_property(e, "adjustment_saturation", float(sv[2]), 0.35)
		tw2.tween_callback(func():
			if _dim_n == 0 and e.has_meta("dim_saved"):
				e.adjustment_enabled = bool(sv[0])
				e.remove_meta("dim_saved")))


# ------------------------------------------------------------------------------------------------ impact

## Where a spell lands: the petals burst out of the point (more and wider the heavier it is), and on a heavy one a ring
## of petals runs out over the ground under it.
func impact(p: Vector3, gy: float, who: String, power: float) -> void:
	impact_card(p, who, power)
	if power >= 0.9:
		sim.big_hit_fx(p, power)
	_k_count = CARD_EXTRA if who == "mika" and FlipbookFX.enabled() else 1.0
	var st := _storm(who, int(500 + 900 * power), 1.0 + 0.4 * power, gy)
	st.light_k = 1.6 + power
	st.scatter(_fix(p), 0.7 + 1.1 * power, 0.9 + 0.5 * power)
	st.finish()
	if power >= 0.7:
		var rp := _storm(who, 900, 1.2, gy)
		rp.light_k = 0.8
		rp.ripple(_fix(Vector3(p.x, gy, p.z)), 2.2 + 1.2 * power, 0.8)
		rp.finish()


# ------------------------------------------------------------------------------------------------ release

## c: who, kind, src (her hand, a Callable), from, target (the other girl's chest, a Callable), at (the locked point),
## fly (seconds to the hit), gy (ground height), fl (flat direction to her), side, size, n, ult, ok (her scale),
## storm (the storm gathered in the hand, or null), sp (the spell).
func release(c: Dictionary) -> void:
	var who := String(c.who)
	var gy := float(c.gy)
	_k_count = CARD_EXTRA if carded(who, String(c.kind)) else 1.0
	_release_card(c)
	var g: PetalStorm = c.get("storm")
	if g == null or not is_instance_valid(g):
		g = _storm(who, 2000, 1.0, gy)
		g.gather(c.src, 0.05)
	g.ground(gy)
	if String(c.kind) in ["volley", "arrow", "orb", "beam", "wave", "crescent"] or String(c.kind) == "":
		g.ribbons(3)
	var from: Vector3 = c.from
	var at: Vector3 = c.at
	var fly := clampf(float(c.fly), 0.08, 2.5)
	var size := float(c.size)
	var ok := float(c.get("ok", 1.0))
	var fl: Vector3 = c.fl
	var side: Vector3 = c.side
	var rng := sim.rng
	var foot := Vector3(from.x, gy, from.z)
	var at_g := Vector3(at.x, gy, at.z)
	match String(c.kind):
		"volley":
			# the storm splits into a fan of petal daggers, streaming at her one after another
			var n := clampi(int(c.get("n", 12)), 4, 12)
			var pts: Array = []
			for i in n:
				var j := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.25, 0.35), rng.randf_range(-0.3, 0.3))
				pts.append(Vector4(at.x + j.x, at.y + j.y, at.z + j.z, 0.3 + 0.035 * float(i)))
			var f1 := from.distance_to(at) / 26.0 + 0.05
			g.petal_size(1.15)
			g.comets(_fix(from + Vector3.UP * 0.3), func() -> Array: return pts, 0.3 + 0.035 * float(n) + f1 + 0.1, f1, 0.1, 1.6, 0.7)
			g.scatter(_fix(at), 1.0, 1.1)
		"arrow":
			var n2 := clampi(int(c.get("n", 5)), 1, 12)
			var pts2: Array = []
			for i in n2:
				var spread := (float(i) - float(n2 - 1) * 0.5) * 0.16
				var to_a: Vector3 = from + (at - from).rotated(Vector3.UP, spread) if i != n2 / 2 else at
				pts2.append(Vector4(to_a.x, to_a.y, to_a.z, 0.0))
			g.comets(_fix(from), func() -> Array: return pts2, fly + 0.1, fly, 0.08, 0.4, 0.12)
			g.scatter(_fix(at), 1.1, 1.0)
		"orb":
			# one heavy comet (a fat knot with a long tail), then the sphere closes round her and crushes
			g.petal_size(1.2)
			var hold := 0.3
			g.comets(c.src, func() -> Array: return [Vector4(at.x, at.y, at.z, hold)], hold + fly, maxf(fly - 0.02, 0.1), 0.4, 0.2, 0.5)
			g.engulf(c.target, 1.25 * ok, 0.9)
			g.scatter(c.target, 1.8, 1.4)
			sim.at(hold + fly, func(): _ripple(who, at_g, 3.6, gy))
		"rows":
			# two rows of spires erupt one after another from her stomp to the other girl, the last one under her
			var st_r := _storm(who, 3200, 1.3, gy)
			st_r.fore()
			st_r.light_k = 1.4
			var dir := sim._flat(at_g - foot)
			var dl := dir.length()
			dir = dir.normalized()
			var sd := dir.cross(Vector3.UP).normalized()
			var pts3: Array = []
			for i in 5:
				var u := float(i + 1) / 6.0
				for lane in [-1.0, 1.0]:
					var p3 := foot + dir * dl * u + sd * float(lane) * (0.35 + 0.12 * float(i))
					pts3.append(Vector4(p3.x, gy, p3.z, fly * u + (0.025 if lane > 0.0 else 0.0)))
			pts3.append(Vector4(at_g.x, gy, at_g.z, fly))
			st_r.columns(func() -> Array: return pts3, fly + 0.9, 2.2 * size, 0.3, 0.16, 0.3)
			st_r.scatter(_fix(at_g + Vector3.UP * 1.0), 1.6, 1.3)
			st_r.finish()
			g.ripple(_fix(foot), 1.8, 0.6)
		"pillars":
			# rows of tall spires rise over her side of the arena toward her and round her, the last one on her
			var st_p := _storm(who, 3600, 1.4, gy)
			st_p.fore()
			st_p.light_k = 1.5
			var dp := sim._flat(at_g - foot).normalized()
			var spp := dp.cross(Vector3.UP).normalized()
			var pts4: Array = []
			var n4 := mini(int(c.get("n", 10)), 10)
			for i in n4:
				var row := float(i / 2)
				var lane2 := -1.0 if i % 2 == 0 else 1.0
				var p4 := at_g - dp * 1.6 + dp * row * 0.75 + spp * lane2 * (0.6 + 0.25 * row)
				pts4.append(Vector4(p4.x, gy, p4.z, 0.06 * row))
			pts4.append(Vector4(at_g.x, gy, at_g.z, maxf(fly, 0.3)))
			st_p.columns(func() -> Array: return pts4, maxf(fly, 0.3) + 1.0, 3.4 * size, 0.42, 0.22, 0.5)
			st_p.scatter(_fix(at_g + Vector3.UP * 1.6), 2.0, 1.4)
			st_p.finish()
			g.ripple(_fix(foot), 2.4, 0.7)
		"array":
			# a ring of thin spires round her and one through her
			var st_a := _storm(who, 3000, 1.2, gy)
			var pts5: Array = []
			var n5 := mini(int(c.get("n", 7)), 11)
			for i in n5:
				var a5 := TAU * float(i) / float(n5)
				pts5.append(Vector4(at_g.x + cos(a5) * 1.3, gy, at_g.z + sin(a5) * 1.3, 0.06 + 0.015 * float(i)))
			pts5.append(Vector4(at_g.x, gy, at_g.z, 0.12))
			st_a.columns(func() -> Array: return pts5, 0.9, 2.4 * size, 0.28, 0.14, 0.3)
			st_a.engulf(_fix(at_g + Vector3.UP * 1.0), 1.2, 0.45)
			st_a.scatter(_fix(at_g + Vector3.UP * 1.0), 1.8, 1.3)
			st_a.finish()
			g.ripple(_fix(foot), 2.0, 0.6)
		"beam":
			# the storm becomes a held torrent from her hand to the other girl
			var hold_b := float((c.sp as Dictionary).get("dur", 0.6))
			g.petal_size(1.2)
			g.light_k = 1.3
			g.stream(c.src, _fix(at), hold_b + 0.25, 0.32 * size, 0.12, 0.0)
			g.scatter(_fix(at), 1.7, 1.2)
			sim.at(0.12, func(): _ripple(who, at_g, 2.6, gy))
		"sky":
			# a funnel of petals pours down from the sky onto her, then bursts out over the ground
			var top := at_g + Vector3.UP * 9.0 - fl * (0.5 if who == "mika" else 2.0)
			var st_s := _storm(who, 3600, 1.4, gy)
			st_s.fore()
			st_s.light_k = 1.4
			st_s.cascade(_fix(at_g), 9.0, 0.45, 1.3 * size)
			st_s.engulf(_fix(at_g + Vector3.UP * 1.0), 1.3, 0.45)
			st_s.scatter(_fix(at_g + Vector3.UP * 1.0), 2.2, 1.4)
			st_s.finish()
			g.river(c.src, _fix(top), 0.3, 1.0)
			g.scatter(_fix(top), 1.4, 0.8)
			sim.at(0.15, func(): _ripple(who, at_g, 4.0, gy))
		"seal":
			# the funnel closes round her into a sphere and crushes
			var st_c := _storm(who, 3200, 1.3, gy)
			st_c.fore()
			st_c.cascade(_fix(at_g), 4.5, 0.35, 1.6 * size)
			st_c.engulf(_fix(at_g + Vector3.UP * 1.0), 1.4 * size, 0.55)
			st_c.scatter(_fix(at_g + Vector3.UP * 1.0), 2.0, 1.4)
			st_c.finish()
			g.river(c.src, _fix(at_g + Vector3.UP * 4.5), 0.3, 1.2)
			g.scatter(_fix(at_g + Vector3.UP * 4.5), 1.2, 0.8)
			sim.at(0.4, func(): _ripple(who, at_g, 3.0, gy))
		"meteor":
			# petal comets fall out of the sky across her ground, one after another
			var c_m := at_g
			var sky := c_m + Vector3.UP * 8.0 - fl * 2.5
			var n6 := clampi(int(c.get("n", 7)), 1, 12)
			var pts6: Array = []
			for i in n6:
				var off := Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.8, 1.8)) if i != 0 else Vector3.ZERO
				pts6.append(Vector4(c_m.x + off.x, gy + 0.1, c_m.z + off.z, 0.12 * float(i)))
			var st_m := _storm(who, 3000, 1.3, gy)
			st_m.fore()
			st_m.comets(_fix(sky), func() -> Array: return pts6, 0.12 * float(n6) + 0.5, 0.45, 0.22, 3.0, 0.0)
			st_m.scatter(_fix(c_m + Vector3.UP * 0.6), 2.4, 1.4)
			st_m.finish()
			g.river(c.src, _fix(sky), 0.35, 1.0)
			g.scatter(_fix(sky), 1.4, 0.8)
			sim.at(0.5, func(): _ripple(who, c_m, 3.8, gy))
		"eclipse":
			# the storm climbs into a sphere hanging over the field, rains petal comets on her, then drops on her
			var n7 := clampi(int(c.get("n", 6)), 1, 12)
			var hang := at_g.lerp(foot, 0.35) + Vector3.UP * 3.2
			var hold_e := 0.5 + 0.16 * float(n7) + 0.6
			var st_e := _storm(who, 3000, 1.3, gy)
			st_e.fore()
			st_e.light_k = 1.3
			st_e.gather(_fix(hang), 0.3)
			st_e.engulf(_fix(hang), 1.0 * size, hold_e - 0.3)
			st_e.river(_fix(hang), _fix(at_g + Vector3.UP * 0.4), 0.35, 0.4)
			st_e.engulf(_fix(at_g + Vector3.UP * 0.8), 1.5, 0.5)
			st_e.scatter(_fix(at_g + Vector3.UP * 0.8), 2.4, 1.4)
			st_e.finish()
			var pts7: Array = []
			for i in n7:
				pts7.append(Vector4(at.x + rng.randf_range(-0.6, 0.6), gy + 0.9, at.z + rng.randf_range(-0.6, 0.6), 0.5 + 0.16 * float(i)))
			var st_r2 := _storm(who, 1400, 1.1, gy)
			st_r2.comets(_fix(hang), func() -> Array: return pts7, 0.5 + 0.16 * float(n7) + 0.3, 0.18, 0.08, 0.8, 0.0)
			st_r2.scatter(_fix(at_g + Vector3.UP * 0.9), 1.4, 1.0)
			st_r2.finish()
			g.river(c.src, _fix(hang), 0.5, 1.0)
			g.scatter(_fix(hang), 1.0, 0.6)
			sim.at(hold_e + 0.35, func(): _ripple(who, at_g, 4.2, gy))
		"vortex":
			# a petal tornado opening at the top crosses the ground at her
			var b_v := at_g
			var t_v := sim.t
			var dur_v := fly
			var pos_v := func() -> Array:
				var q := foot.lerp(b_v, clampf((sim.t - t_v) / maxf(dur_v, 0.01), 0.0, 1.0))
				return [Vector4(q.x, gy, q.z, 0.0)]
			var st_v := _storm(who, 3200, 1.2, gy)
			st_v.fore()
			st_v.light_k = 1.3
			st_v.columns(pos_v, dur_v + 0.3, 3.0 * size, 0.55, 0.3, 2.2)
			st_v.scatter(_fix(b_v + Vector3.UP * 1.2), 2.0, 1.4)
			st_v.finish()
			g.river(c.src, _fix(foot + Vector3.UP * 0.5), 0.3, 0.6)
			g.scatter(_fix(foot + Vector3.UP * 0.5), 1.0, 0.6)
		"wave":
			# a curling wall of petals rolls over the ground at her
			g.petal_size(1.3)
			g.light_k = 1.2
			g.tide(_fix(foot), _fix(at_g), fly * 1.25, 1.6 * size, 1.8 * size)
			g.scatter(_fix(at_g + Vector3.UP * 0.8), 1.8, 1.3)
		"crescent":
			# a crescent wall of petals flies at her through the air
			g.petal_size(1.15)
			var low := from - Vector3.UP * 0.5
			g.tide(_fix(low), _fix(at - Vector3.UP * 0.5), fly * 1.25, 1.3 * size, 1.1 * size)
			g.scatter(_fix(at), 1.4, 1.1)
		"domain":
			# her ground: a ring of spires rises round her, a funnel pours over her, the ripple runs to the edge
			var R := float((c.sp as Dictionary).get("size", 4.5))
			var linger := float((c.sp as Dictionary).get("linger", 4.0))
			var st_d := _storm(who, 4000, 1.5, gy)
			st_d.fore()
			st_d.light_k = 1.6
			var pts8: Array = []
			for i in 12:
				var a8 := TAU * float(i) / 12.0
				pts8.append(Vector4(foot.x + cos(a8) * R * 0.85, gy, foot.z + sin(a8) * R * 0.85, 0.03 * float(i)))
			st_d.columns(func() -> Array: return pts8, linger, 4.5, 0.5, 0.35, 0.55)
			st_d.scatter(_fix(foot + Vector3.UP * 2.0), R, 1.6)
			st_d.finish()
			g.petal_size(1.4)
			g.cascade(_fix(foot), 6.0, 1.0, R * 0.4)
			g.engulf(_fix(foot + Vector3.UP * 1.0), R * 0.35, maxf(linger - 1.0, 0.5))
			g.scatter(_fix(foot + Vector3.UP * 1.0), R * 0.6, 1.4)
			_ripple(who, foot, R * 1.2, gy)
		_:
			g.comets(c.src, func() -> Array: return [Vector4(at.x, at.y, at.z, 0.0)], fly + 0.1, fly, 0.18, 0.3, 0.3)
			g.scatter(_fix(at), 1.1, 1.0)
	g.finish()


# ------------------------------------------------------------------------------------------------ the video cards

## Mika's gather: the petal vortex at her hand, the streams swirling into a ball (frames 0 to 28) over the gather; the
## release stops it as the burst takes over.
func gather_card(who: String, src: Callable, gather_len: float, big: bool) -> FlipbookFX:
	if who != "mika" or not FlipbookFX.enabled():
		return null
	var k = sim.get("ult_kit")
	if k and is_instance_valid(k) and String(k.who) == who:
		return null                                   # (an ultimate: the halo carries it, the hands stay seen in close-up)
	# (1.2 to 1.5 m: a 2.6 m card at her hand covered her whole body through the gather)
	return FlipbookFX.play(sim.d.main, "mika_petal_vortex", src, {"size": 1.5 if big else 1.2, "f0": 0.0, "f1": 28.0,
		"dur": maxf(gather_len, 0.2), "hold_end": 0.6, "fade_in": 0.12, "fade_out": 0.2, "intensity": 1.6, "light": 2.2,
		"black_cut": 0.16})


func _release_card(c: Dictionary) -> void:
	if not FlipbookFX.enabled():
		return
	var who := String(c.who)
	var kind := String(c.kind)
	var size := float(c.size)
	var fly := clampf(float(c.fly), 0.08, 2.5)
	if bool(c.get("ult", false)):
		pass                                          # (an ultimate: the halo and the kit's flare carry the release)
	elif who == "mika":
		# the burst at her hand as the technique leaves it
		# (from frame 11: frames 4 to 10 of the sheet are one white flash filling the circle, a white disc on screen)
		FlipbookFX.play(sim.d.main, "mika_petal_burst", c.src, {"size": 2.0 * clampf(size, 0.8, 1.4), "f0": 11.0, "f1": 63.0,
			"dur": 1.4, "fade_in": 0.05, "fade_out": 0.5, "intensity": 1.7, "light": 3.0, "black_cut": 0.16})
	elif kind in LUNA_SLASH:
		# the crescent flies from her hand to the other girl, turned to the line it flies along
		var from: Vector3 = c.from
		var at: Vector3 = c.at
		var t0 := sim.t
		var along := func() -> Vector3: return from.lerp(at, clampf((sim.t - t0) / maxf(fly, 0.05), 0.0, 1.0))
		FlipbookFX.play(sim.d.main, "luna_crescent_slash", along, {"size": 3.2 * clampf(size, 0.8, 1.4), "f0": 0.0, "f1": 63.0,
			"dur": maxf(fly + 1.2, 1.8), "fade_in": 0.04, "fade_out": 0.5, "intensity": 2.3, "light": 3.5,
			"roll_fn": func() -> float: return screen_roll(from, at)})
	elif kind in LUNA_GROUND:
		# the moon pillar stands on her ground (upright: it stays standing when the camera looks down)
		var at_g := Vector3((c.at as Vector3).x, float(c.gy), (c.at as Vector3).z)
		# (intensity 1.3: at 2 the core bloomed white and hid the violet and the sigil; the top fades so the pillars
		# thin upward instead of ending at the sheet's round crop)
		FlipbookFX.play(sim.d.main, "luna_moon_pillar", func() -> Vector3: return at_g, {"size": 3.8, "upright": true, "f0": 0.0,
			"f1": 63.0, "dur": 2.6, "fade_in": 0.1, "fade_out": 0.6, "intensity": 1.3, "light": 4.5, "light_range": 7.0,
			"black_cut": 0.18, "top_fade": 0.35, "edge_mask": 0.5})


## Mika's burst where a technique lands (bigger the heavier).
func impact_card(p: Vector3, who: String, power: float) -> void:
	if who != "mika" or not FlipbookFX.enabled():
		return
	# (from frame 14 and softer: frames 11 to 13 still carried a white core that bloomed into a white ball)
	FlipbookFX.play(sim.d.main, "mika_petal_burst", func() -> Vector3: return p, {"size": 2.2 + 1.4 * clampf(power, 0.0, 1.0),
		"f0": 14.0, "f1": 63.0, "dur": 1.3 + 0.6 * power, "fade_in": 0.04, "fade_out": 0.5, "intensity": 1.4, "light": 3.0 + 2.0 * power,
		"black_cut": 0.18})


## Luna's weapon swing: a crescent at the blade, turned to the swing.
func swing_card(who: String, at: Vector3, swing_dir: Vector3, big: bool) -> void:
	if who != "luna" or not FlipbookFX.enabled():
		return
	var to := at + swing_dir
	FlipbookFX.play(sim.d.main, "luna_crescent_slash", func() -> Vector3: return at, {"size": 3.0 if big else 2.2, "f0": 0.0,
		"f1": 40.0 if not big else 63.0, "dur": 0.8 if not big else 1.4, "fade_in": 0.03, "fade_out": 0.35, "intensity": 2.2,
		"light": 3.0, "roll_fn": func() -> float: return screen_roll(at, to)})


## The roll that turns the sheet's horizontal slash onto the line a to b as the camera sees it.
func screen_roll(a: Vector3, b: Vector3) -> float:
	var cam := sim.d.get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var pa := cam.unproject_position(a)
	var pb := cam.unproject_position(b)
	var d := pb - pa
	if d.length() < 2.0:
		return 0.0
	var ang := atan2(d.y, d.x)
	# (keep it within a quarter turn either way: the slash reads the same mirrored, upside down it does not)
	if ang > PI * 0.5:
		ang -= PI
	elif ang < -PI * 0.5:
		ang += PI
	return ang


func _ripple(who: String, at_g: Vector3, r: float, gy: float) -> void:
	var rp := _storm(who, 1400, 1.25, gy)
	rp.light_k = 0.9
	rp.ripple(_fix(at_g), r, 0.9)
	rp.finish()
