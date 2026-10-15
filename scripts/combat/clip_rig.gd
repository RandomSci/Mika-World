class_name ClipRig
extends CreatureBody
## A creature body driven by its own animation clips (an imported, rigged GLB), with procedural flight on
## top: hover bob, banking into turns, rearing back while it charges, and a dive pitch. Used by the
## Emberwing (Quaternius "Dragon", CC0, recoloured for Mika World - see docs/ASSET_SOURCES.md).
## spec (data/monsters.json -> "body"): {glb, scale, yaw_offset, clips: {state: [clip, speed, loop]},
##   recolor: {material_name: [r, g, b, emission]}, mouth: [x, y, z], ground: true for a walking creature (no hover
##   bob, banking or rearing - its clips carry the body), keep_materials: true to keep the model's own PBR materials}

var spec := {}
var model: Node3D
var player: AnimationPlayer
var _pivot: Node3D                # procedural layer between this node and the model
var _mats := {}                   # material name -> StandardMaterial3D (recoloured copies)
var _hurt := 0.0
var _t := 0.0
var _bank := 0.0
var _prev_yaw := 0.0
var hover := 0.0                  # extra height (m) the monster asks for (rising away, diving)
var pitch := 0.0                  # radians, nose down > 0
var mouth_glow: OmniLight3D
var _own_emission := {}           # material name -> [enabled, colour, energy] as imported (restored after a hurt flash)


func build(p_spec: Dictionary, eye: Color) -> void:
	process_priority = 100          # after the model's AnimationPlayer: weapon aim / limits fit THIS frame's pose
	spec = p_spec
	glow_color = eye
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	model = (load(String(spec.glb)) as PackedScene).instantiate()
	model.scale = Vector3.ONE * float(spec.get("scale", 1.0))
	model.rotation.y = deg_to_rad(float(spec.get("yaw_offset", 0.0)))
	_pivot.add_child(model)
	player = model.find_child("AnimationPlayer", true, false)
	var rc: Dictionary = spec.get("recolor", {})
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			var nm := String(src.resource_name) if src else ""
			var key := ""
			for k in rc:
				if nm.begins_with(k):
					key = k
			var mat := StandardMaterial3D.new()
			if src is BaseMaterial3D:
				mat = (src as BaseMaterial3D).duplicate()
			if key != "":
				var c: Array = rc[key]
				mat.albedo_color = Color(c[0], c[1], c[2])
				if c.size() > 3 and float(c[3]) > 0.0:
					mat.emission_enabled = true
					mat.emission = Color(c[0], c[1], c[2])
					mat.emission_energy_multiplier = float(c[3])
			if not bool(spec.get("keep_materials", false)):
				mat.roughness = 0.75
			_own_emission[nm] = [mat.emission_enabled, mat.emission, mat.emission_energy_multiplier]
			_mats[nm] = mat
			m.set_surface_override_material(si, mat)
	_attach_weapons()
	mouth_glow = FX.light(eye, 0.0, 3.0)
	var mp: Array = spec.get("mouth", [0, 1.2, 0.6])
	mouth_glow.position = Vector3(mp[0], mp[1], mp[2])
	_pivot.add_child(mouth_glow)
	_prev_yaw = global_rotation.y
	_entered("idle")


## Weapons in their hands (human rivals): spec.weapons = [{model, bone, pos [x,y,z], rot [deg x,y,z], scale}] -
## Poly Haven props (katana, sabre, dagger, machete, mace) on a bone attachment of the model's own skeleton.
var weapons: Array[Node3D] = []


func _attach_weapons() -> void:
	var sk: Skeleton3D = model.find_child("*", true, false) as Skeleton3D
	for n in model.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	if sk == null:
		return
	for wspec in spec.get("weapons", []):
		var bone := String(wspec.get("bone", "hand_r"))
		if sk.find_bone(bone) < 0:
			continue
		var ba := BoneAttachment3D.new()
		ba.bone_name = bone
		sk.add_child(ba)
		var holder := Node3D.new()
		ba.add_child(holder)
		var sc := Transform3D(Basis.from_scale(Vector3.ONE * float(wspec.get("scale", 1.0))), Vector3.ZERO)
		if wspec.has("part"):
			Kit.place_prop(holder, String(wspec.model), sc, String(wspec.part))
		else:
			Kit.place_prop_all(holder, String(wspec.model), sc)
		# held as a fighter holds it (Grip): the handle in the fist, the blade rising from the thumb side, the edge
		# leading - measured from the hand bones and the weapon itself, never a guessed offset
		var side := "l" if bone.ends_with("_l") else "r"
		var hand_grip := Grip.hand_frame(sk, side)
		var bf := Grip.blade_frame(holder) if String(wspec.get("grip", "blade")) == "blade" else Grip.tool_frame(holder)
		if bf.is_empty() and String(wspec.get("grip", "blade")) == "blade":
			bf = Grip.tool_frame(holder)
		if not bf.is_empty() and hand_grip.basis != Basis():
			holder.transform = hand_grip * (bf.xf as Transform3D).affine_inverse()
			if bf.has("tip"):
				holder.set_meta("tip_local", bf.tip)       # the weapon's tip in the holder's space (InvariantAuditor)
				holder.set_meta("grip_local", (bf.xf as Transform3D).origin)
				holder.set_meta("grip_by", String(bf.get("by", "?")))
				holder.set_meta("weapon_length", float(bf.get("length", 0.0)))
				holder.set_meta("base_xf", holder.transform)
		else:
			var pp: Array = wspec.get("pos", [0, 0, 0])
			var rr: Array = wspec.get("rot", [0, 0, 0])
			holder.position = Vector3(pp[0], pp[1], pp[2])
			holder.rotation_degrees = Vector3(rr[0], rr[1], rr[2])
		for mi in holder.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		weapons.append(holder)


## The blade follows the fight, not the generic clip's wrist: on guard / alert / closing in it points at the one
## it faces (no one: forward and a little down) - rotated about the fist, at most 90 degrees from the hand's own
## angle, eased; in the wind-up and the strike the animation keeps most of it (the swing reads); in defeat none.
var _aim := {}                     # weapon holder id -> the eased correction (Quaternion)

func _aim_weapons(delta: float) -> void:
	if weapons.is_empty():
		return
	var mon := get_parent() as Node3D
	var tgt: Node3D = null
	if mon and mon.get("target_mage") != null and is_instance_valid(mon.get("target_mage")):
		tgt = mon.get("target_mage")
	# the strike keeps a little of the clip's swing, but the blade MEETS what it strikes (these clips were not
	# animated for a sword: left alone, a blade can trail behind the strike)
	var ms := String(mon.get("mstate")) if mon and mon.get("mstate") != null else state
	var wgt := 0.0 if (state in ["defeat", "dying"] or ms == "dying") else (0.85 if ms == "strike" else (0.5 if ms == "windup" else 1.0))
	var locked := ms in ["windup", "strike"]       # the attack's aim is locked at the wind-up: follow it through
	for w in weapons:
		if not is_instance_valid(w) or not w.has_meta("base_xf") or not w.is_inside_tree():
			continue
		w.transform = w.get_meta("base_xf")                     # the hand's own grip this frame
		var gt: Transform3D = w.global_transform
		var g: Vector3 = gt * (w.get_meta("grip_local") as Vector3)
		var tip: Vector3 = gt * (w.get_meta("tip_local") as Vector3)
		var cur := (tip - g).normalized()
		var want: Vector3
		if locked:
			var lf := mon.global_transform.basis.z if mon else global_transform.basis.z
			want = (Vector3(lf.x, 0, lf.z).normalized() + Vector3(0, -0.1, 0)).normalized()
		elif tgt:
			want = ((tgt.global_position + Vector3(0, 1.15, 0)) - g).normalized()
		else:
			var f := global_transform.basis.z
			want = (Vector3(f.x, 0, f.z).normalized() * 0.94 + Vector3(0, -0.34, 0)).normalized()
		# never aim a blade across its own wielder (an off hand beside the hip pointing at someone in front would
		# run the dagger through the chest): bend it outward, away from the body, until its path is clear
		if mon:
			var axis_p := mon.global_position
			var out := Vector3(g.x - axis_p.x, 0, g.z - axis_p.z)
			out = out.normalized() if out.length() > 0.01 else global_transform.basis.x
			var ln := g.distance_to(tip)
			for attempt in 4:
				var crosses := false
				for k in range(2, 9):
					var bp: Vector3 = g + want * ln * (k / 8.0)
					if Vector2(bp.x - axis_p.x, bp.z - axis_p.z).length() < 0.2 and bp.y > axis_p.y + 0.8 and bp.y < axis_p.y + 1.9:
						crosses = true
						break
				if not crosses:
					break
				want = (want + out * 0.6).normalized()
		# and never into the ground: lift the aim until the tip clears the terrain under it
		var w_area = get_tree().current_scene.get("world") if get_tree().current_scene else null
		if w_area and w_area.has_method("ground_at"):
			var ln2 := g.distance_to(tip)
			for lift in 4:
				var tp: Vector3 = g + want * ln2
				if tp.y > float(w_area.ground_at(tp.x, tp.z)) + 0.08:
					break
				want = (want + Vector3(0, 0.25, 0)).normalized()
		var ang := cur.angle_to(want)
		var axis := cur.cross(want)
		var q := Quaternion.IDENTITY
		if axis.length() > 1e-4 and ang > 0.01:
			# a strike may turn the blade fully (the generic clips' wrists were not animated for a sword); guards 90 max
			q = Quaternion(axis.normalized(), minf(ang, deg_to_rad(180.0 if locked else 90.0)) * wgt)
		var key := w.get_instance_id()
		var prev: Quaternion = _aim.get(key, Quaternion.IDENTITY)
		q = prev.slerp(q, 1.0 - exp(-10.0 * delta))
		_aim[key] = q
		var r := Basis(q)
		w.global_transform = Transform3D(r * gt.basis, g + r * (gt.origin - g))
		_constrain_blade(w, mon, g)


## Hard limits on the FINAL blade (after the clip and the aim, whatever they did): its tip never below the ground
## and its length never through the wielder's head or torso - rotated up / outward about the fist just enough.
func _constrain_blade(w: Node3D, mon: Node3D, g: Vector3) -> void:
	var w_area = get_tree().current_scene.get("world") if get_tree().current_scene else null
	for it in 10:
		var gt: Transform3D = w.global_transform
		var tip: Vector3 = gt * (w.get_meta("tip_local") as Vector3)
		var dir := tip - g
		var fix := Vector3.ZERO
		if w_area and w_area.has_method("ground_at") and tip.y < float(w_area.ground_at(tip.x, tip.z)) + 0.1:
			fix += Vector3.UP
		if mon:
			var ap := mon.global_position
			for k in range(2, 9):
				var bp := g.lerp(tip, k / 8.0)
				var off := Vector2(bp.x - ap.x, bp.z - ap.z)
				if off.length() < 0.24 and bp.y > ap.y + 0.8 and bp.y < ap.y + 1.95:
					var out := Vector3(g.x - ap.x, 0, g.z - ap.z)
					fix += (out.normalized() if out.length() > 0.02 else global_transform.basis.z)
					break
		if fix == Vector3.ZERO:
			return
		var want := (dir.normalized() + fix.normalized() * 0.6).normalized()
		var ax := dir.normalized().cross(want)
		if ax.length() < 1e-4:
			return
		var rb := Basis(ax.normalized(), dir.normalized().angle_to(want))
		w.global_transform = Transform3D(rb * gt.basis, g + rb * (gt.origin - g))


## A rival who yields lets the weapons fall: each becomes a prop lying on the ground where it dropped.
func drop_weapons() -> void:
	for w in weapons:
		if not is_instance_valid(w):
			continue
		var xf := w.global_transform
		var world := get_tree().current_scene
		w.get_parent().remove_child(w)
		world.add_child(w)
		w.global_transform = xf
		var gy := xf.origin.y - 1.0
		var ray := PhysicsRayQueryParameters3D.create(xf.origin + Vector3.UP * 0.2, xf.origin + Vector3.DOWN * 3.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			gy = (hit.position as Vector3).y
		var lie := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5)
		var tw := w.create_tween().set_parallel(true)
		tw.tween_property(w, "global_position", Vector3(xf.origin.x + randf_range(-0.3, 0.3), gy + 0.03, xf.origin.z + randf_range(-0.3, 0.3)), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(w, "quaternion", lie.get_rotation_quaternion(), 0.45)
	weapons.clear()


## The tip of the first weapon (sword trails, slash waves start there).
func weapon_tip() -> Vector3:
	if weapons.is_empty():
		return aim_point()
	var w := weapons[0]
	if w.has_meta("tip_local"):
		return w.global_transform * (w.get_meta("tip_local") as Vector3)      # the measured tip (Grip)
	var ln := float(spec.get("weapons", [{}])[0].get("length", 0.9))
	return w.global_transform * Vector3(0, ln, 0)


func clip_length(st: String) -> float:
	var c: Array = spec.get("clips", {}).get(st, [])
	if c.is_empty() or player == null or not player.has_animation(String(c[0])):
		return 0.0
	return player.get_animation(String(c[0])).length / maxf(float(c[1]), 0.05)


func _entered(s: String) -> void:
	if player == null:
		return
	var clips: Dictionary = spec.get("clips", {})
	var c: Array = clips.get(s, clips.get("idle", []))
	if c.is_empty() or not player.has_animation(String(c[0])):
		return
	var a := player.get_animation(String(c[0]))
	a.loop_mode = Animation.LOOP_LINEAR if (c.size() > 2 and bool(c[2])) else Animation.LOOP_NONE
	player.play(String(c[0]), 0.18, float(c[1]))


func aim_point() -> Vector3:
	return _pivot.global_position + Vector3(0, float(spec.get("aim_y", 1.0)), 0)


func mouth_point() -> Vector3:
	return mouth_glow.global_position if mouth_glow else aim_point()


func flash(strength := 1.0) -> void:
	_hurt = clampf(strength, 0.3, 1.0)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	state_t += delta
	_aim_weapons(delta)
	# banking: roll into the turn (yaw rate), like a flyer, never more than ~35 degrees
	var yaw := global_rotation.y
	var rate := angle_difference(_prev_yaw, yaw) / maxf(delta, 1e-4)
	_prev_yaw = yaw
	_bank = lerpf(_bank, clampf(-rate * 0.25 - move_speed * 0.0, -0.6, 0.6), 1.0 - exp(-4.0 * delta))
	var ground := bool(spec.get("ground", false))
	if ground:
		_bank = 0.0
	var bob := 0.12 * sin(_t * 3.1) if (state != "defeat" and not ground) else 0.0
	var rear := 0.0
	if state == "windup" and not ground:
		rear = -0.45 * clampf(state_t / 0.4, 0.0, 1.0)      # rears back, chest out, before it breathes / dives
	elif state == "strike" and not ground:
		rear = 0.25
	_pivot.position.y = lerpf(_pivot.position.y, hover + bob, 1.0 - exp(-5.0 * delta))
	_pivot.rotation = Vector3(lerpf(_pivot.rotation.x, rear + pitch, 1.0 - exp(-8.0 * delta)), 0, _bank)
	if mouth_glow:
		var want := 2.4 * clampf(state_t / 0.5, 0.0, 1.0) if state == "windup" else 0.0
		mouth_glow.light_energy = lerpf(mouth_glow.light_energy, want * float(RenderProfile.get_setting("magic_light_scale")), 1.0 - exp(-12.0 * delta))
	_hurt = maxf(0.0, _hurt - delta * 3.0)
	for nm in _mats:
		var m: StandardMaterial3D = _mats[nm]
		if _hurt > 0.0:
			m.emission_enabled = true
			m.emission = Color(1.0, 0.85, 0.6)
			m.emission_energy_multiplier = _hurt * 1.4
		elif m.emission == Color(1.0, 0.85, 0.6):
			var rc: Dictionary = spec.get("recolor", {})
			var restored := false
			for k in rc:
				if nm.begins_with(k) and (rc[k] as Array).size() > 3 and float(rc[k][3]) > 0.0:
					m.emission = Color(rc[k][0], rc[k][1], rc[k][2])
					m.emission_energy_multiplier = float(rc[k][3])
					restored = true
			if not restored:
				var own: Array = _own_emission.get(nm, [false, Color.BLACK, 1.0])
				m.emission_enabled = bool(own[0])
				m.emission = own[1]
				m.emission_energy_multiplier = float(own[2])


func collapse() -> void:
	play("defeat")
	hover = 0.0 if bool(spec.get("ground", false)) else -0.4
	await get_tree().create_timer(maxf(0.6, clip_length("defeat"))).timeout
