class_name Ward
extends Node3D
## A defence that stays on its caster (V3 Part XIII, "defence and counterplay"): the next projectiles that
## reach her are stopped by it. Judged at the moment a bolt really crosses the ward (AttackHazard), never a
## dice roll. Two languages:
##   leaf    Mika's LEAF WARD: a ring of leaves orbits her and moves with her; it takes blows from any side
##           (two light bolts, or one heavy one) and scatters when spent
##   mirror  Luna's GILDED MIRROR: a hexagonal pane of dark glass with a gold rim held before her. It covers
##           only her FRONT (a bolt from behind still lands); one bolt - and once she has practised it
##           (Adept) the pane throws a light bolt back at whoever sent it
## Each absorbed bolt is real practice (a small mastery gain for the ward spell).

signal spent(ward: Ward, how: String)

const MIRROR_HALF_ANGLE := deg_to_rad(70.0)

var owner_mage: WorldCharacter
var who := ""
var kind := "leaf"
var spell_id := ""
var charges := 1
var charges_max := 1
var seconds := 4.0
var reflects := false
var done := false
var absorbed := 0
var reflected := 0
var log: Array = []
var _age := 0.0
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _motes: GPUParticles3D
var _light: OmniLight3D
var _flash := 0.0
var _rng := RandomNumberGenerator.new()


static func active_for(mage: Node) -> Ward:
	if mage == null or not is_instance_valid(mage) or not mage.is_inside_tree():
		return null
	for n in mage.get_tree().get_nodes_in_group("ward"):
		var w := n as Ward
		if w and w.owner_mage == mage and not w.done:
			return w
	return null


func setup(mage: WorldCharacter, p_kind: String, p_spell: String, p_charges: int, p_seconds: float, p_reflects: bool) -> void:
	owner_mage = mage
	who = mage.character_id
	kind = p_kind
	spell_id = p_spell
	charges = p_charges
	charges_max = p_charges
	seconds = p_seconds
	reflects = p_reflects
	_rng.seed = hash(who) + int(Time.get_ticks_msec())
	# one ward at a time: a new one replaces the old
	var old := Ward.active_for(mage)
	if old and old != self:
		old._spend("replaced")
	add_to_group("ward")
	global_position = mage.global_position
	match kind:
		"leaf":
			_build_leaf()
		"mirror":
			_build_mirror()
	log.append({"event": "up", "kind": kind, "charges": charges, "seconds": snappedf(seconds, 0.1), "reflects": reflects})
	if log.size() > 200:
		log.pop_front()
	if AudioDirector.instance:
		AudioDirector.instance.play3d("ward_%s_up" % kind, _centre(), "SFX", -6.0, "ward")


func _centre() -> Vector3:
	if owner_mage and is_instance_valid(owner_mage) and owner_mage.chest:
		return owner_mage.chest.global_position
	return global_position + Vector3(0, 1.2, 0)


func _fwd() -> Vector3:
	var f := -owner_mage.global_transform.basis.z
	return Vector3(f.x, 0, f.z).normalized()


## Can this ward stop something coming from `from`? The leaf ring covers every side; the mirror only her front.
func covers(from: Vector3) -> bool:
	if done or owner_mage == null or not is_instance_valid(owner_mage):
		return false
	if kind == "leaf":
		return true
	var c := _centre()
	var to := Vector3(from.x - c.x, 0, from.z - c.z)
	if to.length() < 0.05:
		return true
	return _fwd().dot(to.normalized()) >= cos(MIRROR_HALF_ANGLE)


## Does a bolt moving from `a` to `b` this frame cross the ward?
func intercepts(a: Vector3, b: Vector3) -> bool:
	if done or owner_mage == null or not is_instance_valid(owner_mage):
		return false
	var c := _centre()
	match kind:
		"leaf":
			return Geometry3D.get_closest_point_to_segment(c, a, b).distance_to(c) <= 0.95
		_:
			var n := _fwd()
			var pc := c + n * 0.55
			var da := (a - pc).dot(n)
			var db := (b - pc).dot(n)
			if da * db > 0.0 and absf(db) > 0.12:
				return false                     # the segment stays on one side of the pane
			var hit := b if absf(da - db) < 1e-5 else a + (b - a) * (da / (da - db))
			return (hit - pc).length() <= 0.7
	return false


func hit_point(a: Vector3, b: Vector3) -> Vector3:
	var c := _centre()
	if kind == "leaf":
		return Geometry3D.get_closest_point_to_segment(c, a, b)
	var n := _fwd()
	var pc := c + n * 0.55
	var da := (a - pc).dot(n)
	var db := (b - pc).dot(n)
	return b if absf(da - db) < 1e-5 else a + (b - a) * (da / (da - db))


## A bolt has crossed the ward: it is stopped ("absorbed") or, by a practised mirror, thrown back ("reflected").
func absorb(h: Node, at: Vector3) -> String:
	var heavy: bool = bool(h.get("heavy")) if h.get("heavy") != null else false
	var how := "absorbed"
	if reflects and kind == "mirror" and not heavy:
		how = "reflected"
		reflected += 1
	else:
		absorbed += 1
	charges -= 2 if heavy else 1
	_flash = 1.0
	var host := get_parent()
	match kind:
		"leaf":
			FX.burst(host, at, 26, 1.0, FX.pm_leaves("burst"), FX.leaf_mesh(0.07))
			FX.burst(host, at, 30, 0.5, FX.pm_motes("wind", "burst"), FX.mote_mesh(0.04, true))
			if _mesh:
				var tw := _mesh.create_tween()
				tw.tween_property(_mesh, "scale", Vector3.ONE * 1.25, 0.08)
				tw.tween_property(_mesh, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"mirror":
			FX.burst(host, at, 28, 0.7, FX.pm_motes("umbral", "burst"), FX.mote_mesh(0.045, true))
			ImpactFX.shockwave(host, at + Vector3(0, 0.25, 0), FX.palette("umbral")[0], 0.6)
	var flash := FX.light(FX.palette("wind" if kind == "leaf" else "umbral")[0], 2.0 * float(RenderProfile.get_setting("magic_light_scale")), 4.0)
	host.add_child(flash)
	flash.global_position = at
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 0.4)
	ft.tween_callback(flash.queue_free)
	if AudioDirector.instance:
		AudioDirector.instance.play3d("ward_%s_%s" % [kind, "reflect" if how == "reflected" else "absorb"], at, "SFX", -3.0, "ward")
	# real practice: a blow really stopped
	var m := MagicSystem.mastery(spell_id, who)
	WorldState.record_activity({"id": "ward:" + spell_id, "verb": "ward", "label": "%s stopped a blow" % MagicSystem.spell(spell_id).get("name", spell_id)},
		{"skills": {spell_id: 0.04 / (1.0 + m * 0.8)}, "knowledge": {"warded:" + spell_id: 1}}, who)
	log.append({"event": how, "heavy": heavy, "charges_left": charges, "at": [snappedf(at.x, 0.1), snappedf(at.y, 0.1), snappedf(at.z, 0.1)]})
	if log.size() > 200:
		log.pop_front()
	if charges <= 0:
		_spend("spent")
	return how


func _process(delta: float) -> void:
	if done:
		return
	if owner_mage == null or not is_instance_valid(owner_mage) or not owner_mage.visible:
		_spend("gone")
		return
	_age += delta
	_flash = maxf(0.0, _flash - delta * 3.0)
	global_position = owner_mage.global_position
	match kind:
		"leaf":
			if _mesh:
				_mesh.rotation.y += delta * 2.4
				_mesh.position.y = 1.15 + 0.05 * sin(_age * 3.0)
				_mesh.rotation.x = 0.08 * sin(_age * 1.7)
			if _light:
				_light.light_energy = (0.35 + 0.8 * _flash) * float(RenderProfile.get_setting("magic_light_scale"))
		"mirror":
			var c := _centre()
			var f := _fwd()
			var pc := c + f * 0.55
			if _mesh:
				_mesh.global_transform = Transform3D(Basis.looking_at(-f, Vector3.UP), pc)
				_mesh.rotate_object_local(Vector3.RIGHT, 0.04 * sin(_age * 2.2))
				_mat.set_shader_parameter("hit_flash", _flash)
				_mat.set_shader_parameter("reveal", clampf(_age / 0.18, 0.0, 1.0))
			if _motes:
				_motes.global_position = pc
			if _light:
				_light.global_position = pc + f * 0.2
				_light.light_energy = (0.3 + 1.0 * _flash) * float(RenderProfile.get_setting("magic_light_scale"))
	if _age >= seconds:
		_spend("expired")


func _spend(how: String) -> void:
	if done:
		return
	done = true
	remove_from_group("ward")
	var host := get_parent()
	var c := _centre()
	match kind:
		"leaf":
			if how == "spent":
				FX.burst(host, c, 40, 1.6, FX.pm_leaves("burst"), FX.leaf_mesh(0.07))
			else:
				var drift := FX.burst(host, c, 24, 2.2, FX.pm_leaves("trail"), FX.leaf_mesh(0.07))
				drift.explosiveness = 0.6
		"mirror":
			if how == "spent":
				FX.burst(host, c + _fwd() * 0.55, 36, 0.9, FX.pm_motes("umbral", "burst"), FX.mote_mesh(0.05, true))
	if _mesh:
		_mesh.visible = false
	if _motes:
		_motes.emitting = false
	if _light:
		_light.light_energy = 0.0
	log.append({"event": how, "age": snappedf(_age, 0.1), "absorbed": absorbed, "reflected": reflected})
	if log.size() > 200:
		log.pop_front()
	spent.emit(self, how)
	get_tree().create_timer(1.4).timeout.connect(queue_free)


# ------------------------------------------------------------------ visuals
## A ring of leaf cards (the kit's leaf atlas, our own geometry) tilted round her chest; it spins as a whole.
func _build_leaf() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 18
	for i in n:
		var ang := TAU * i / n + _rng.randf_range(-0.1, 0.1)
		var r := 0.78 + _rng.randf_range(-0.05, 0.05)
		var c := Vector3(cos(ang) * r, _rng.randf_range(-0.18, 0.22), sin(ang) * r)
		var tangent := Vector3(-sin(ang), 0, cos(ang))
		var out := Vector3(cos(ang), 0, sin(ang))
		var tilt := _rng.randf_range(0.5, 1.0)
		var up := (Vector3.UP * tilt + out * (1.0 - tilt) * 0.6).normalized() * _rng.randf_range(0.16, 0.22)
		var right := tangent * _rng.randf_range(0.1, 0.14)
		var spr: Rect2 = [FoliageBuilder.SPR_ROUND, FoliageBuilder.SPR_HEART, FoliageBuilder.SPR_THIN][i % 3]
		FoliageBuilder._card(st, c, right, up, spr, (out * 0.3 + Vector3.UP).normalized())
	st.index()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = NatureKit.tex(FoliageBuilder.LEAF_TEX)
	m.albedo_color = Color(0.9, 1.0, 0.8)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.6, 0.25)
	m.emission_energy_multiplier = 0.9
	m.roughness = 0.9
	m.backlight_enabled = true
	m.backlight = Color(0.55, 0.8, 0.35)
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.position.y = 1.15
	_mesh.scale = Vector3.ONE * 0.2
	add_child(_mesh)
	var tw := _mesh.create_tween()
	tw.tween_property(_mesh, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motes = FX.particles(30, 1.2, FX.pm_motes("wind", "swirl"), FX.mote_mesh(0.045), true)
	_motes.emitting = true
	_motes.position.y = 1.0
	_motes.scale = Vector3.ONE * 2.2
	add_child(_motes)
	_light = FX.light(FX.palette("wind")[0], 0.35, 2.6)
	_light.position.y = 1.2
	add_child(_light)


## The hexagonal pane before her (the gilded_mirror shader), gold motes along its rim.
func _build_mirror() -> void:
	var pal := FX.palette("umbral")
	_mesh = FX.quad("res://shaders/magic/gilded_mirror.gdshader", 0.98, {"gold": pal[0], "violet": pal[1], "intensity": 1.0, "hit_flash": 0.0, "reveal": 0.0}, false)
	_mat = _mesh.material_override
	add_child(_mesh)
	_mesh.top_level = true
	_motes = FX.particles(30, 0.8, FX.pm_motes("umbral", "swirl"), FX.mote_mesh(0.04), false)
	_motes.emitting = true
	_motes.top_level = true
	add_child(_motes)
	_light = FX.light(pal[0], 0.3, 2.5)
	_light.top_level = true
	add_child(_light)
