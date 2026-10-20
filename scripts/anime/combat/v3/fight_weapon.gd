class_name FightWeapon
extends Node3D
## Her weapon in a fight (2026-10-20, Selwyn: "each girl's weapon is attached to her hand with a proper grip pose and
## gets collision so it never passes through either girl. Before Level 20 the weapon is a conjured light blade that
## appears with a flash and dissolves after, from Level 20 it is the Gale Rapier or the Shadow Glaive").
##   the weapon     from Level 20 Mika's Gale Rapier (1.0 m) or Luna's Shadow Glaive (1.7 m, held at the middle of the
##                  shaft), the transformation lab's exports (origin at the grip, the length along +Y); below Level 20
##                  a conjured blade of light in the same shape (ult_glow), drawn out of the air from the grip to the
##                  tip in 0.18 s with the impact starburst at her hand, and dissolved after the fight's moves
##                  (WeaponArsenal in the outfit worktree keeps the unlocks; when it merges, kind_of() asks it)
##   the grip       placed on her FINAL pose every frame (Skeleton3D.skeleton_updated): the length through her fist,
##                  perpendicular to the palm and the knuckle line (the hammer grip), the grip point between the wrist
##                  and the knuckles; GripPose curls that hand's fingers round the handle
##   collision      the blade is a segment (grip to tip, its own radius) tested against both girls' mesh-sized body
##                  capsules (BodyCapsules) every frame: inside her own body or the other girl it turns about the grip
##                  to the nearest place that is out (at most 70 deg; four passes); during a strike the other girl's
##                  surface may take it 2 cm deep (`strike` true), never more
##   trail          a ribbon from the blade's middle to its tip while `trail_on` (CombatVFX trail, her colours)

const MODELS := {"mika": "res://assets/weapons/MikaGaleRapier_L20.glb", "luna": "res://assets/weapons/LunaShadowGlaive_L20.glb"}
const NAMES := {"mika": "Gale Rapier", "luna": "Shadow Glaive"}
## [butt below the grip, tip above the grip, blade starts at] (m), from the exports' bounds
const SPAN := {"mika": [0.062, 0.936, 0.13], "luna": [0.68, 1.02, 0.62]}
const RADIUS := 0.025
const MAX_DEFLECT := 70.0

var sim: MeleeSim
var who := ""
var side := "Right"
var real := false                            # the real weapon (Level 20 on) or the conjured light blade
var f: MeleeFighter
var grip: GripPose
var body: Node3D
var _mats: Array = []
var strike := false                          # a strike owns the contact with the other girl (2 cm deep at most)
var trail_on := false
var _trail = null
var hold_w := 0.0
var _alive := true
var deflect_deg := 0.0                       # QA: how far the collision turned the blade this frame
var contact_other := false


static func level_of(who_: String) -> int:
	if RenderProfile.options.has("weapon-level"):
		return int(RenderProfile.options["weapon-level"])
	var m = WorldState.mind(who_)
	return int(m.level()) if m else 1


## Draws her weapon into her hand (side "Right" or "Left").
static func draw(s: MeleeSim, who_: String, hand := "Right") -> FightWeapon:
	var w := FightWeapon.new()
	w.name = "FightWeapon_" + who_
	w.sim = s
	w.who = who_
	w.side = hand
	w.f = s.F[who_]
	w.real = level_of(who_) >= 20
	w.top_level = true
	s.d.main.add_child(w)
	w._build()
	return w


func _build() -> void:
	# the grip pose on her skeleton (one per skeleton, shared by both hands)
	grip = f.sk.get_node_or_null("GripPose") as GripPose
	if grip == null:
		grip = GripPose.new()
		grip.name = "GripPose"
		f.sk.add_child(grip)
		PosePipeline.arrange_for(f.sk)
	body = Node3D.new()
	add_child(body)
	if real and ResourceLoader.exists(MODELS[who]):
		var sc: PackedScene = load(MODELS[who])
		var inst := sc.instantiate() as Node3D
		body.add_child(inst)
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		real = false
		_build_conjured()
	f.sk.skeleton_updated.connect(_place)
	# it appears: a flash at her hand, the blade drawn from the grip to the tip
	var hand_p: Vector3 = f.trace.get(side + "Hand", f.sk.global_position)
	FlipbookFX.play(sim.d.main, "fx_impact_starburst", func() -> Vector3: return hand_p, {"size": 1.0 if real else 1.2, "f0": 4.0,
		"f1": 63.0, "dur": 0.6, "fade_in": 0.02, "fade_out": 0.25, "intensity": 1.5, "light": 2.5, "black_cut": 0.16})
	var tw := create_tween()
	tw.tween_property(self, "hold_w", 1.0, 0.15)
	if not real:
		for m in _mats:
			m.set_shader_parameter("reveal", 0.0)
			tw.parallel().tween_method(func(v: float): m.set_shader_parameter("reveal", v), 0.0, 1.0, 0.18)
	else:
		body.scale = Vector3.ONE * 0.01
		tw.parallel().tween_property(body, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The light blade below Level 20: Mika a slim rapier of light with a small guard, Luna a glaive (a long shaft of light
## and a crescent blade at its head).
func _build_conjured() -> void:
	var svfx: SpellVFX = sim.magic.svfx
	var col := Vector3(1.0, 0.55, 0.78) if who == "mika" else Vector3(0.62, 0.4, 1.0)
	var hi := Vector3(1.0, 0.95, 0.98) if who == "mika" else Vector3(1.0, 0.88, 0.62)
	var parts := []
	var sp: Array = SPAN[who]
	if who == "mika":
		parts.append([svfx.crystal(float(sp[1]) - 0.05, 0.018, 4, 0.06), Transform3D(Basis(), Vector3(0, 0.05, 0))])
		parts.append([svfx.crystal(0.16, 0.022, 4, 0.5), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.08, 0.05, 0))])
		parts.append([svfx.crystal(0.11, 0.016, 6, 0.5), Transform3D(Basis(), Vector3(0, -0.06, 0))])
	else:
		parts.append([svfx.crystal(float(sp[0]) + float(sp[1]) - 0.3, 0.014, 6, 0.5), Transform3D(Basis(), Vector3(0, -float(sp[0]), 0))])
		parts.append([svfx.crescent_mesh(0.3, 0.06, 150.0, 24), Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), Vector3(0.12, float(sp[1]) - 0.32, 0))])
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.transform = p[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/magic/ult_glow.gdshader")
		m.set_shader_parameter("col", col)
		m.set_shader_parameter("hi", hi)
		m.set_shader_parameter("intensity", 1.6)
		mi.material_override = m
		_mats.append(m)
		body.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(col.x, col.y, col.z)
	l.omni_range = 2.2
	l.light_energy = 0.8
	l.position = Vector3(0, float(sp[1]) * 0.5, 0)
	l.shadow_enabled = false
	body.add_child(l)


## The grip on her final pose, then the collision.
func _place() -> void:
	if not _alive or not is_instance_valid(f.sk):
		return
	grip.hold[side] = hold_w
	var sk := f.sk
	var hb := sk.find_bone(side + "Hand")
	var mb := sk.find_bone(side + "MiddleProximal")
	var ib := sk.find_bone(side + "IndexProximal")
	var lb := sk.find_bone(side + "LittleProximal")
	if hb < 0 or mb < 0 or ib < 0 or lb < 0:
		return
	var gx := sk.global_transform
	var hand: Vector3 = gx * sk.get_bone_global_pose(hb).origin
	var mid: Vector3 = gx * sk.get_bone_global_pose(mb).origin
	var knuck: Vector3 = (gx * sk.get_bone_global_pose(ib).origin) - (gx * sk.get_bone_global_pose(lb).origin)   # little -> index
	var length := (mid - hand)
	# the hammer grip: the blade leaves the fist on the thumb side, across the palm (perpendicular to the hand's
	# length, in the plane of the knuckle line)
	var y := (knuck - length.normalized() * knuck.dot(length.normalized())).normalized()
	if y.length() < 0.5:
		return
	var z := length.normalized().cross(y).normalized()
	var x := y.cross(z).normalized()
	var at := hand.lerp(mid, 0.55) + z * 0.012 * f.k
	var b := Basis(x, y, z).scaled(Vector3.ONE * f.k)
	global_transform = Transform3D(b, at)
	_collide()
	if trail_on and _trail == null:
		# (the references' weapon arcs: a wide bright ribbon from near the grip to past the tip, a long history)
		_trail = sim.vfx.trail(func() -> Array: return [tip_point(0.2), tip_point(1.08)] if _alive else [Vector3.ZERO, Vector3.ZERO], who, 9999.0, 3.4, 3.0)
		if _trail is Dictionary:
			(_trail as Dictionary)["hist_max"] = 12
	elif not trail_on and _trail != null:
		_stop_trail()


func _stop_trail() -> void:
	if _trail is Dictionary:
		(_trail as Dictionary)["left"] = 0.0
	_trail = null


## A point along the weapon: 0 the grip, 1 the tip (world).
func tip_point(u: float) -> Vector3:
	var sp: Array = SPAN[who]
	return global_transform * Vector3(0, float(sp[1]) * u, 0)


func butt_point() -> Vector3:
	var sp: Array = SPAN[who]
	return global_transform * Vector3(0, -float(sp[0]), 0)


## The blade out of both bodies: test points along it against the capsules, turn it about the grip toward the way out.
func _collide() -> void:
	deflect_deg = 0.0
	contact_other = false
	var other: MeleeFighter = sim.F[String(sim.d.F[who].other)]
	var own_caps := _caps(f, true)
	var oth_caps := _caps(other, false)
	var g := global_position
	var start := global_basis
	for pass_i in 4:
		var worst := 0.0
		var push := Vector3.ZERO
		var lever := 0.0
		for u in [0.35, 0.55, 0.75, 0.95]:
			var p := tip_point(u)
			for set in [[own_caps, 0.0], [oth_caps, -0.02 if strike else 0.0]]:
				var dp: Array = BodyCapsules.deepest(p, RADIUS * f.k, set[0])
				var depth := float(dp[0]) + float(set[1])
				if depth > worst:
					worst = depth
					push = (dp[1] as Vector3) * depth
					lever = p.distance_to(g)
					if set[0] == oth_caps:
						contact_other = true
		if worst <= 0.001 or lever < 0.05:
			break
		var tip := tip_point(1.0)
		var dir := (tip - g).normalized()
		var want := (tip - g + push * (tip.distance_to(g) / lever) * 1.15).normalized()
		var ax := dir.cross(want)
		if ax.length() < 1e-5:
			break
		var ang := dir.angle_to(want)
		global_basis = Basis(ax.normalized(), ang) * global_basis
	deflect_deg = rad_to_deg(start.y.normalized().angle_to(global_basis.y.normalized()))
	if deflect_deg > MAX_DEFLECT:
		var ax2 := start.y.cross(global_basis.y)
		if ax2.length() > 1e-5:
			global_basis = Basis(ax2.normalized(), deg_to_rad(MAX_DEFLECT)) * start
		deflect_deg = MAX_DEFLECT


## Her capsules in world space; her own holding hand and forearm left out (the weapon sits in that hand).
func _caps(mf: MeleeFighter, own: bool) -> Array:
	var bc := BodyCapsules.of(mf.c, mf.sk)
	var out := []
	var gx := mf.sk.global_transform
	for cp in bc.world(mf.sk):
		var nm := String(cp[4])
		if own and (nm.begins_with(side + "Hand") or nm.begins_with(side + "Lower") or nm.begins_with(side + "Index") or nm.begins_with(side + "Middle")
				or nm.begins_with(side + "Ring") or nm.begins_with(side + "Little") or nm.begins_with(side + "Thumb")):
			continue
		out.append([gx * (cp[0] as Vector3), gx * (cp[1] as Vector3), float(cp[2]) * mf.k, float(cp[3]) * mf.k, nm])
	return out


## Puts it away: the light blade dissolves into petals, the real weapon shrinks into a flash.
func sheathe() -> void:
	if not _alive:
		return
	trail_on = false
	_stop_trail()
	_alive = false
	var hand_p := tip_point(0.4)
	var tw := create_tween()
	tw.tween_property(self, "hold_w", 0.0, 0.25)
	tw.parallel().tween_method(func(v: float): grip.hold[side] = v, hold_w, 0.0, 0.25)
	if real:
		tw.parallel().tween_property(body, "scale", Vector3.ONE * 0.01, 0.2)
	else:
		for m in _mats:
			tw.parallel().tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, 0.35)
		sim.magic.arts.impact(hand_p, sim.d.pos(who).y, who, 0.3)
	tw.tween_callback(func():
		if f.sk.skeleton_updated.is_connected(_place):
			f.sk.skeleton_updated.disconnect(_place)
		queue_free())
