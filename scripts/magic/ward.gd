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
##   grove   THE GILDED GROVE (a combination, V3 Part 62-63): a Leaf Ward and a Gilded Mirror raised by the two
##           mages within MERGE_DIST of each other become one dome over both - every side covered for both,
##           their charges pooled (+1), the mirror's throw-back kept. It lasts while they stay together.

signal spent(ward: Ward, how: String)

const MIRROR_HALF_ANGLE := deg_to_rad(70.0)
const MERGE_DIST := 3.2           # the two wards meet if the mages stand this close
const PART_DIST := 4.6            # and the grove comes apart if they step this far apart

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
var partner: WorldCharacter = null    # grove: the other mage under the dome
var spells := {}                      # grove: who -> her own ward spell (each block is practice for its own spell)


static func active_for(mage: Node) -> Ward:
	if mage == null or not is_instance_valid(mage) or not mage.is_inside_tree():
		return null
	for n in mage.get_tree().get_nodes_in_group("ward"):
		var w := n as Ward
		if w and (w.owner_mage == mage or w.partner == mage) and not w.done:
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
	_try_merge.call_deferred()


## A leaf ward and a mirror up at once, the two mages close together: they become the Gilded Grove.
func _try_merge() -> void:
	if done or not (kind in ["leaf", "mirror"]) or not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("ward"):
		var o := n as Ward
		if o == null or o == self or o.done or o.kind == kind or not (o.kind in ["leaf", "mirror"]):
			continue
		if o.owner_mage == null or not is_instance_valid(o.owner_mage) or o.owner_mage == owner_mage:
			continue
		if o.owner_mage.global_position.distance_to(owner_mage.global_position) > MERGE_DIST:
			continue
		var g := Ward.new()
		get_parent().add_child(g)
		g.setup_grove(o, self)
		return


func setup_grove(first: Ward, second: Ward) -> void:
	owner_mage = second.owner_mage
	partner = first.owner_mage
	who = owner_mage.character_id
	kind = "grove"
	spell_id = second.spell_id
	spells = {first.who: first.spell_id, second.who: second.spell_id}
	charges = maxi(first.charges, 0) + maxi(second.charges, 0) + 1
	charges_max = charges
	seconds = maxf(first.seconds, second.seconds) + 3.0     # the merged dome is a renewed, stronger shield
	reflects = true            # the combination's gift: under the grove even an unpractised mirror throws light bolts back
	_rng.seed = hash(who) + int(Time.get_ticks_msec())
	first._spend("merged")
	second._spend("merged")
	add_to_group("ward")
	global_position = _ground_mid()
	_build_grove()
	log.append({"event": "up", "kind": kind, "charges": charges, "seconds": snappedf(seconds, 0.1), "from": [first.kind, second.kind]})
	if AudioDirector.instance:
		AudioDirector.instance.play3d("ward_leaf_up", _centre(), "SFX", -4.0, "ward")
		AudioDirector.instance.play3d("ward_mirror_up", _centre(), "SFX", -4.0, "ward")
	for w in spells:
		var first_time: bool = not WorldState.mind(String(w)).knowledge.has("fusion:gilded_grove")
		WorldState.record_activity({"id": "fusion:gilded_grove", "verb": "discover" if first_time else "ward", "label": "the Gilded Grove: two wards became one"},
			{"knowledge": {"fusion:gilded_grove": 1}}, String(w))


func _ground_mid() -> Vector3:
	return (owner_mage.global_position + partner.global_position) * 0.5


func _radius() -> float:
	if partner == null or not is_instance_valid(partner):
		return 1.2
	return Vector2(owner_mage.global_position.x - partner.global_position.x, owner_mage.global_position.z - partner.global_position.z).length() * 0.5 + 1.15


func _centre() -> Vector3:
	if kind == "grove" and owner_mage and partner and is_instance_valid(owner_mage) and is_instance_valid(partner):
		return _ground_mid() + Vector3(0, 0.9, 0)
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
	if kind == "leaf" or kind == "grove":
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
		"grove":
			# the dome's shell: a bolt from outside that reaches it (both mages are inside)
			# (moving inward: a bolt the grove has just thrown back is on its way out)
			return a.distance_to(c) > _radius() - 0.15 and (b - a).dot(c - a) > 0.0 and Geometry3D.get_closest_point_to_segment(c, a, b).distance_to(c) <= _radius()
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
	if kind == "grove":
		var hits := Geometry3D.segment_intersects_sphere(a, b, c, _radius())
		return hits[0] if not hits.is_empty() else Geometry3D.get_closest_point_to_segment(c, a, b)
	var n := _fwd()
	var pc := c + n * 0.55
	var da := (a - pc).dot(n)
	var db := (b - pc).dot(n)
	return b if absf(da - db) < 1e-5 else a + (b - a) * (da / (da - db))


## A bolt has crossed the ward: it is stopped ("absorbed") or, by a practised mirror, thrown back ("reflected").
func absorb(h: Node, at: Vector3) -> String:
	var heavy: bool = bool(h.get("heavy")) if h.get("heavy") != null else false
	var how := "absorbed"
	if reflects and kind in ["mirror", "grove"] and not heavy:
		how = "reflected"
		reflected += 1
	else:
		absorbed += 1
	charges -= 2 if heavy else 1
	_flash = 1.0
	var from: Vector3 = at - ((h.get("dir") as Vector3) if h.get("dir") is Vector3 else Vector3.ZERO)
	for m in _holders():
		if m.body_language:
			m.body_language.barrier_impact(from, heavy or charges <= 0)
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
		"grove":
			FX.burst(host, at, 22, 1.0, FX.pm_leaves("burst"), FX.leaf_mesh(0.07))
			FX.burst(host, at, 24, 0.6, FX.pm_motes("umbral", "burst"), FX.mote_mesh(0.045, true))
			ImpactFX.shockwave(host, at, Color(1.0, 0.85, 0.45), 0.7)
	var flash := FX.light(FX.palette("wind" if kind == "leaf" else "umbral")[0] if kind != "grove" else Color(1.0, 0.85, 0.5), 2.0 * float(RenderProfile.get_setting("magic_light_scale")), 4.0)
	host.add_child(flash)
	flash.global_position = at
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 0.4)
	ft.tween_callback(flash.queue_free)
	if AudioDirector.instance:
		var snd_kind := kind if kind != "grove" else ("mirror" if how == "reflected" else "leaf")
		AudioDirector.instance.play3d("ward_%s_%s" % [snd_kind, "reflect" if how == "reflected" else "absorb"], at, "SFX", -3.0, "ward")
	# real practice: a blow really stopped (under the grove, each mage's own ward spell)
	var practice: Dictionary = spells if kind == "grove" else {who: spell_id}
	for pw in practice:
		var sid := String(practice[pw])
		var m := MagicSystem.mastery(sid, String(pw))
		WorldState.record_activity({"id": "ward:" + sid, "verb": "ward", "label": "%s stopped a blow" % MagicSystem.spell(sid).get("name", sid)},
			{"skills": {sid: 0.04 / (1.0 + m * 0.8)}, "knowledge": {"warded:" + sid: 1}}, String(pw))
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
		_spend("gone:owner %s" % ("freed" if owner_mage == null or not is_instance_valid(owner_mage) else "hidden"))
		return
	_age += delta
	_flash = maxf(0.0, _flash - delta * 3.0)
	# the body holds it: arms up, leaning in, straining more as the charges run out (BodyLanguage)
	for m in _holders():
		if m.body_language:
			m.body_language.hold_barrier(kind, 1.0 - float(charges) / float(maxi(charges_max, 1)) * 0.85)
	if kind == "grove":
		if partner == null or not is_instance_valid(partner) or not partner.visible:
			_spend("gone:partner %s" % ("freed" if partner == null or not is_instance_valid(partner) else "hidden"))
			return
		if owner_mage.global_position.distance_to(partner.global_position) > PART_DIST:
			_spend("parted")
			return
		global_position = _ground_mid()
		var rr := _radius()
		if _mesh:
			_mesh.scale = _mesh.scale.lerp(Vector3(rr, rr * 0.9, rr), 1.0 - exp(-6.0 * delta))
			_mat.set_shader_parameter("hit_flash", _flash)
			_mat.set_shader_parameter("reveal", clampf(_age / 0.5, 0.0, 1.0))
			_mat.set_shader_parameter("t", _age)
		if _light:
			_light.light_energy = (0.5 + 1.2 * _flash) * float(RenderProfile.get_setting("magic_light_scale"))
		if _age >= seconds:
			_spend("expired")
		return
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


func _holders() -> Array:
	var out := []
	for m in [owner_mage, partner]:
		if m != null and is_instance_valid(m):
			out.append(m)
	return out


func _spend(how: String) -> void:
	if done:
		return
	for m in _holders():
		if m.body_language and how != "merged":
			m.body_language.barrier_released(how == "spent")
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
		"grove":
			FX.burst(host, c, 40, 1.8, FX.pm_leaves("burst"), FX.leaf_mesh(0.07))
			FX.burst(host, c, 30, 0.9, FX.pm_motes("umbral", "burst"), FX.mote_mesh(0.05, true))
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


## The Gilded Grove: a dome of gold light over both, its shell bright at the edges (fresnel), leaves of Mika's
## ward drifting up round its foot and the dusk motes of Luna's mirror turning in it.
const GROVE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float hit_flash = 0.0;
uniform float reveal = 0.0;
uniform float t = 0.0;
varying vec3 lp;
varying float cap;
void vertex() { lp = VERTEX; cap = step(NORMAL.y, -0.9); }
void fragment() {
	if (cap > 0.5) { discard; }          // the hemisphere's flat bottom: no milky floor over their feet
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	float band = 0.5 + 0.5 * sin(lp.y * 18.0 - t * 2.4);
	float hex = smoothstep(0.95, 1.0, abs(sin(lp.x * 9.0 + lp.z * 5.0)) * abs(sin(lp.z * 9.0 - lp.x * 5.0)));
	float rim = smoothstep(0.08, 0.0, lp.y) * smoothstep(0.85, 1.0, length(lp.xz));   // where the shell meets the ground
	vec3 gold = vec3(1.0, 0.8, 0.42);
	vec3 green = vec3(0.6, 0.95, 0.55);
	vec3 col = mix(green, gold, clamp(lp.y + 0.2, 0.0, 1.0));
	float a = (fres * (0.5 + 0.25 * band) + hex * 0.12 + rim * 0.6 + hit_flash * 0.7) * step(lp.y, reveal * 1.05);
	ALBEDO = col * a * 0.85;
}
"""

func _build_grove() -> void:
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 1.0
	sm.is_hemisphere = true
	sm.radial_segments = 48
	sm.rings = 18
	_mesh.mesh = sm
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = GROVE_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mesh.material_override = _mat
	_mesh.scale = Vector3.ONE * 0.3
	add_child(_mesh)
	_motes = FX.particles(48, 1.8, FX.pm_leaves("lift"), FX.leaf_mesh(0.08), true)
	_motes.emitting = true
	add_child(_motes)
	var dusk := FX.particles(40, 2.2, FX.pm_motes("umbral", "swirl"), FX.mote_mesh(0.05), true)
	dusk.emitting = true
	dusk.position = Vector3(0, 0.9, 0)
	add_child(dusk)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.85, 0.55)
	_light.omni_range = 5.0
	_light.position = Vector3(0, 1.4, 0)
	add_child(_light)

