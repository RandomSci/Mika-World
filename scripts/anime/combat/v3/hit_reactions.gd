class_name HitReactions
extends RefCounted
## Combat v3 hit reaction library: every blow is sold by the receiver, from WHERE it landed (the hurtbox zone the
## capsules found: head / chest / stomach / left / right / legs) and HOW hard (light flinch, medium stagger, heavy
## knock-back, launch, knockdown; airborne: juggle, spinning fall, recovery flip or hard landing), plus the block
## family (block-stun slide, guard pushed open, guard break, parry deflect) and the get-ups (standard, slow push-up
## when hurt, kip-up, magic recovery, a playful pout in sparring). Each reaction layers:
##   a key pose of the zone (the body folds around the blow) scaled by the strength, eased in fast and out slow
##   the reaction springs (head snap, spine give, hip shove - MeleeFighter.react) along the blow's direction
##   travel: stagger steps, a slide, a knock-back with skidding feet, a launch arc
##   partial physics on the struck chain for 0.2 - 0.4 s (FightPhysics) - so no two hits look alike
##   hair and skirt whipped from the blow's side (the VRM springs' add-force, the skirt sim's gravity)
##   the face (hurt / shock / pout) and a short shout
## Mocap bases (MoveCatalog): hit_light, hit_heavy_stagger, hit_from_left / right, guard_break_stagger, launched_land,
## knockdown_getup, spin_dizzy_fall (pout) - played full body where the clip reads well, otherwise their key poses.

## zone -> key pose (over her guard) at full strength
const ZONE := {
	"head": {"hip": Vector3(0, -0.02, -0.03), "hip_rot": Vector3(-5, 0, 0), "spine": Vector3(-12, 0, 0), "head": Vector3(-24, 0, 0)},
	"chest": {"hip": Vector3(0, -0.03, -0.05), "hip_rot": Vector3(-3, 0, 0), "spine": Vector3(-14, 0, 0), "head": Vector3(8, 0, 0)},
	"stomach": {"hip": Vector3(0, -0.07, -0.08), "hip_rot": Vector3(10, 0, 0), "spine": Vector3(28, 0, 0), "head": Vector3(14, 0, 0),
		"lh": Vector3(0.07, 1.02, 0.17), "rh": Vector3(-0.06, 0.99, 0.15), "lfist": 0.4, "rfist": 0.4},
	"left": {"hip": Vector3(-0.04, -0.03, -0.01), "hip_rot": Vector3(0, -8, 0), "spine": Vector3(8, -14, -16), "head": Vector3(6, -10, -8),
		"lh": Vector3(0.12, 1.08, 0.12)},
	"right": {"hip": Vector3(0.04, -0.03, -0.01), "hip_rot": Vector3(0, 8, 0), "spine": Vector3(8, 14, 16), "head": Vector3(6, 10, 8),
		"rh": Vector3(-0.12, 1.08, 0.12)},
	"legs": {"hip": Vector3(0, -0.11, -0.02), "hip_rot": Vector3(8, 0, 0), "spine": Vector3(14, 0, 0), "head": Vector3(10, 0, 0)},
}
## strength -> [pose scale, in s, hold s, out s, travel m, spring power]
const STRENGTH := {
	"flinch": [0.45, 0.05, 0.05, 0.2, 0.0, 0.55],
	"stagger": [0.85, 0.06, 0.1, 0.32, 0.35, 0.8],
	"knockback": [1.0, 0.07, 0.16, 0.42, 1.1, 1.0],
}


## The strength a blow deals: from the move (weight, launch, down) and the state she was in.
static func strength_of(m: Dictionary, airborne: bool) -> String:
	if airborne:
		return "juggle"
	if m.get("down", false):
		return "knockdown"
	if m.get("launch", false):
		return "launch"
	match String(m.weight):
		"light":
			return "flinch"
		"medium":
			return "stagger"
	return "knockback"


## A blow landed on `o` (the sim's fighter dict) in `zone`, travelling `dir`; power 0..1. Returns the reaction name
## (QA). The caller already applied damage and the impact feel (hit stop, shake, sparks).
static func hit(sim: MeleeSim, o: Dictionary, zone: String, dir: Vector3, power: float, m: Dictionary) -> String:
	var f: MeleeFighter = sim.F[o.id]
	var d: FightDirector = sim.d
	var air := float(d.F[o.id].lift) > 0.12
	var st := strength_of(m, air)
	if bool(o.get("gather_broken", false)):
		# her gesture was broken in its gather (GestureDirector): a stagger, never the small flinch
		o.gather_broken = false
		if st == "flinch":
			st = "stagger"
	o.last_reaction = st
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	f.react(dir, "high" if zone == "head" else ("low" if zone == "legs" else "mid"), power * (0.6 if st == "flinch" else 1.0))
	if f.phys:
		f.phys.hit(zone, dir, power)
	whip(f.c, dir, power)
	f.move_tag = "react:%s_%s" % [zone, st]
	match st:
		"knockdown":
			sim._knockdown(o, flat)
			return "knockdown"
		"launch":
			_launch(sim, o, f, flat, power)
			return "launch"
		"juggle":
			_juggle(sim, o, f, flat, power)
			return "juggle"
	var spec: Array = STRENGTH[st]
	var pose := _scaled(ZONE.get(zone, ZONE.chest), float(spec[0]) * lerpf(0.8, 1.15, power))
	if zone == "head":
		# the head turns away from a hook (the side the blow came from), snaps back from a straight
		var lat := f.sk.global_transform.basis.inverse() * flat
		pose.head = (pose.head as Vector3) + Vector3(0, -lat.x * 30.0, -lat.x * 14.0) * float(spec[0])
		pose.spine = (pose.spine as Vector3) + Vector3(0, -lat.x * 10.0, 0)
	if zone in ["chest", "stomach", "head"] and pose.has("lh") == false:
		pose["hands"] = "root"
	f.play([{"dur": float(spec[1]), "ease": "snap", "pose": pose}, {"dur": float(spec[2]), "ease": "hold", "pose": pose},
		{"dur": float(spec[3]), "ease": "inout", "pose": {}}])
	o.state = "react"
	o.until = sim.t + float(spec[1]) + float(spec[2]) + float(spec[3]) * 0.6
	var kn: float = minf(float(m.get("knock", float(spec[4]) * lerpf(0.7, 1.2, power))), 1.3 if m.get("separator", false) else 0.8)
	if kn > 0.01:
		o.vel = flat * sqrt(2.0 * 7.5 * kn)
		if kn > 0.3:
			f.skim(minf(0.12 + kn * 0.12, 0.45))
	return st


## Thrown up and back: an arc (the director's hop), the body arches and turns over, then she lands - on her feet in a
## crouch (a hard landing, dust), or with a recovery flip if she is agile and not hit again.
static func _launch(sim: MeleeSim, o: Dictionary, f: MeleeFighter, flat: Vector3, power: float) -> void:
	var d: FightDirector = sim.d
	var h := lerpf(0.7, 1.1, power)
	var dur := lerpf(0.65, 0.85, power)
	d.hop(o.id, h, dur)
	o.vel = flat * 2.2
	o.state = "react"
	o.until = sim.t + dur + 0.3
	f.skim(dur + 0.05)
	var up := {"hip": Vector3(0, 0.02, -0.04), "hip_rot": Vector3(-28, 0, 0), "spine": Vector3(-18, 0, 0), "head": Vector3(-14, 0, 0),
		"lf": Vector3(0.12, 0.22, 0.12), "rf": Vector3(-0.12, 0.16, -0.05), "lh": Vector3(0.28, 1.3, 0.0), "rh": Vector3(-0.28, 1.28, 0.0), "hands": "root"}
	var tuck := {"hip": Vector3(0, -0.06, 0.0), "hip_rot": Vector3(18, 0, 0), "spine": Vector3(20, 0, 0), "head": Vector3(10, 0, 0),
		"lf": Vector3(0.11, 0.35, 0.18), "rf": Vector3(-0.11, 0.32, 0.1), "lh": Vector3(0.14, 1.12, 0.22), "rh": Vector3(-0.14, 1.1, 0.2), "hands": "root"}
	var land := {"hip": Vector3(0, -0.22, -0.02), "hip_rot": Vector3(16, 0, 0), "spine": Vector3(18, 0, 0), "head": Vector3(6, 0, 0),
		"lh": Vector3(0.24, 0.85, 0.2), "rh": Vector3(-0.24, 0.85, 0.16), "hands": "root"}
	f.play([{"dur": dur * 0.4, "ease": "out", "pose": up}, {"dur": dur * 0.6, "ease": "inout", "pose": tuck},
		{"dur": 0.12, "ease": "snap", "pose": land, "start": func(): sim.vfx.dust(d.pos(o.id), -flat, 20, 1.3)},
		{"dur": 0.3, "ease": "inout", "pose": {}}])
	sim.events.append([snappedf(sim.t, 0.01), "launch", o.id, ""])


## Hit again while in the air: thrown a little higher, a spinning fall, a hard landing.
static func _juggle(sim: MeleeSim, o: Dictionary, f: MeleeFighter, flat: Vector3, power: float) -> void:
	var d: FightDirector = sim.d
	var lift := float(d.F[o.id].lift)
	# the arc goes on from where she is in the air: up a little more, then down to the ground
	var fd: Dictionary = d.F[o.id]
	var top := lift + 0.3 * power + 0.12
	if fd.get("hop_tw") and (fd.hop_tw as Tween).is_valid():
		(fd.hop_tw as Tween).kill()
	var tw := d.create_tween()
	fd.hop_tw = tw
	tw.tween_method(func(v: float): fd.lift = v, lift, top, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): fd.lift = v, top, 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	o.vel = flat * 2.6
	o.state = "react"
	o.until = sim.t + 0.85
	f.skim(0.6)
	var spin := {"hip_rot": Vector3(-20, 140, 0), "spine": Vector3(-10, 20, 0), "head": Vector3(-8, 0, 0),
		"lf": Vector3(0.12, 0.3, 0.1), "rf": Vector3(-0.12, 0.25, -0.05), "hands": "root"}
	var land := {"hip": Vector3(0, -0.24, 0.0), "hip_rot": Vector3(18, 0, 0), "spine": Vector3(22, 0, 0),
		"lh": Vector3(0.26, 0.8, 0.22), "rh": Vector3(-0.26, 0.8, 0.18), "hands": "root"}
	f.play([{"dur": 0.5, "ease": "inout", "pose": spin}, {"dur": 0.12, "ease": "snap", "pose": land,
		"start": func(): sim.vfx.dust(d.pos(o.id), -flat, 24, 1.4)}, {"dur": 0.3, "ease": "inout", "pose": {}}])
	sim.events.append([snappedf(sim.t, 0.01), "juggle", o.id, ""])


## A blocked blow: the block-stun slide; a heavy one pushes the guard open (arms thrown wide, chest back); a guard that
## has absorbed too much breaks (the stagger clip, she cannot defend for a moment). Returns the block reaction name.
static func block(sim: MeleeSim, o: Dictionary, dir: Vector3, power: float, m: Dictionary, arm: String) -> String:
	var f: MeleeFighter = sim.F[o.id]
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	f.absorb(dir, arm, power)
	whip(f.c, dir, power * 0.5)
	o.block_load = float(o.get("block_load", 0.0)) + (0.9 if m.weight == "heavy" else 0.35) * power
	var kind := "blockstun"
	if float(o.block_load) > 1.9 or float(o.stam) < 18.0:
		kind = "guard_break"
	elif m.weight == "heavy":
		kind = "guard_open"
	match kind:
		"guard_break":
			o.block_load = 0.0
			o.state = "react"
			o.until = sim.t + 0.75
			o.guard_broken_until = sim.t + 0.9
			f.move_tag = "react:guard_break"
			var open := {"hip": Vector3(0, -0.05, -0.08), "hip_rot": Vector3(-10, 0, 0), "spine": Vector3(-16, 0, 0), "head": Vector3(-10, 0, 0),
				"lh": Vector3(0.42, 1.18, 0.05), "rh": Vector3(-0.42, 1.16, 0.02), "hands": "root", "lfist": 0.3, "rfist": 0.3}
			f.play([{"dur": 0.08, "ease": "snap", "pose": open}, {"dur": 0.3, "ease": "hold", "pose": open}, {"dur": 0.35, "ease": "inout", "pose": {}}])
			o.vel = flat * sqrt(2.0 * 7.5 * 0.6)
			f.skim(0.25)
			sim.d.face_fx(o.id, "shock", 1.0, 0.6)
		"guard_open":
			f._kick("lh", flat * 0.0 + (f.sk.global_transform.basis * Vector3(1.2, 0.3, 0)) * power)
			f._kick("rh", (f.sk.global_transform.basis * Vector3(-1.2, 0.3, 0)) * power)
			f._kick("spine", Vector3(-300.0 * power, 0, 0))
			o.vel = flat * sqrt(2.0 * 7.5 * (0.25 + 0.4 * power))
			f.skim(0.2)
		_:
			o.vel = flat * sqrt(2.0 * 7.5 * (0.1 + 0.15 * power))
	o.block_load = maxf(float(o.block_load), 0.0)
	return kind


## Hair and skirt thrown from the blow's side: the VRM hair springs' add-force and the skirt sim's gravity tilted
## along the blow for ~0.15 s, then back (the springs' own colliders keep hair out of the body; the skirt sim keeps
## its speed limit).
static func whip(c: WorldCharacter, dir: Vector3, power: float) -> void:
	if c == null or power <= 0.05:
		return
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	for n in c.find_children("*", "Node3D", true, false):
		if n.get("springbone_add_force") != null:
			# (world space, added to the springs' gravity every frame: a small nudge - the springs' own gravity is ~0.1-0.5)
			n.set("springbone_add_force", flat * 0.12 * power)
			var tw := n.create_tween()
			tw.tween_interval(0.08)
			tw.tween_callback(func(): if is_instance_valid(n): n.set("springbone_add_force", Vector3.ZERO))
		elif n is SpringBoneSimulator3D:
			var sb := n as SpringBoneSimulator3D
			var dirs := []
			for i in sb.setting_count:
				dirs.append(sb.get_gravity_direction(i))
				sb.set_gravity_direction(i, (Vector3.DOWN + flat * 0.5 * power).normalized())
			var tw2 := sb.create_tween()
			tw2.tween_interval(0.15)
			tw2.tween_callback(func():
				if is_instance_valid(sb):
					for i in mini(sb.setting_count, dirs.size()):
						sb.set_gravity_direction(i, dirs[i]))


static func _scaled(pose: Dictionary, s: float) -> Dictionary:
	var out := {}
	for key in pose:
		var v = pose[key]
		if v is Vector3:
			var g = MeleeBook.GUARD.get(key, null)
			if key in ["hip_rot", "spine", "head"]:
				# rotations: the guard's own angle plus the reaction's, scaled
				out[key] = (g as Vector3) + (v as Vector3) * s if g is Vector3 else (v as Vector3) * s
			elif key == "hip":
				out[key] = (g as Vector3) + (v as Vector3) * s if g is Vector3 else (v as Vector3) * s
			else:
				out[key] = (g as Vector3).lerp(v, s) if g is Vector3 else v
		elif v is float:
			var gf = MeleeBook.GUARD.get(key, 0.0)
			out[key] = lerpf(float(gf), float(v), s)
		else:
			out[key] = v
	return out
