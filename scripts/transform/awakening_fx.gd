class_name AwakeningFX
extends Node3D
## Visual layers of the first-time Level 10 awakening (Milestone J), driven by the sequence clock:
##   ambient   - stage 1: motes drift in from the surroundings toward her
##   pillars   - stage 2: three original "orbit frames" (vertical rings with bead nodes) rise from the ground
##               around her and turn, tightening as the power builds
##   cocoon    - stage 3: ribbons of light wrap her from the feet up (hiding the outfit change), then
##               unravel from the head down so the new outfit is revealed progressively; petals/motes are
##               shed at the unravelling line
##   orbit     - stage 4: the first Aether Orbit assembles: arc segments and bead nodes fly in from
##               scattered positions and lock into a ring around her, with a pulse when it closes
## All geometry is original (rings, beads, ribbons). Colours come from data/transformations.json.

var mage: WorldCharacter
var col := Color.WHITE
var acc := Color.WHITE
var petals := false
var _cocoon: MeshInstance3D
var _cocoon_mat: ShaderMaterial
var _ribbons: MeshInstance3D
var _ribbon_mat: ShaderMaterial
var _frames: Array[Node3D] = []
var _orbit: Node3D
var _segments: Array = []          # [{node, from: Transform3D, to: Transform3D, delay}]
var _ambient: GPUParticles3D
var _shed: GPUParticles3D
var _orbit_light: OmniLight3D
var _locked := false
var _light_scale := 1.0
var swapped_at := -1.0             # sequence time when the outfit really changed (set by the director)


func build(c: WorldCharacter, p_col: Color, p_acc: Color, p_petals: bool) -> void:
	mage = c
	col = p_col
	acc = p_acc
	petals = p_petals
	_light_scale = float(RenderProfile.get_setting("magic_light_scale"))
	# stage 1 ambient: motes converging from a wide radius
	var pm := FX.pm_motes("self", "gather")
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 5.5
	pm.radial_accel_min = -3.2
	pm.radial_accel_max = -2.2
	pm.gravity = Vector3(0, 0.15, 0)
	pm.color = col.lerp(Color.WHITE, 0.3)
	_ambient = FX.particles(90, 2.4, pm, FX.mote_mesh(0.035))
	_ambient.emitting = false
	_ambient.position = Vector3(0, 1.0, 0)
	add_child(_ambient)
	# stage 2: three orbit frames
	for i in 3:
		var f := Node3D.new()
		add_child(f)
		var ring := _torus(0.95 + i * 0.12, 0.012, col if i != 1 else acc)
		f.add_child(ring)
		for k in 6:
			var bead := _bead(0.03, acc if i != 1 else col)
			var a := TAU * k / 6.0
			bead.position = Vector3(cos(a), sin(a), 0) * (0.95 + i * 0.12)
			f.add_child(bead)
		f.rotation = Vector3(0, TAU * i / 3.0, 0)
		f.position.y = -1.6
		f.visible = false
		_frames.append(f)
	# stage 3: the cocoon (a closed cylinder of ribbons around her body)
	_cocoon = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.95
	cm.radial_segments = 40
	cm.rings = 20
	_cocoon.mesh = cm
	_cocoon_mat = ShaderMaterial.new()
	_cocoon_mat.shader = load("res://shaders/cocoon.gdshader")
	_cocoon_mat.set_shader_parameter("color", Color(col, 1.0))
	_cocoon_mat.set_shader_parameter("accent", Color(acc, 1.0))
	_cocoon_mat.set_shader_parameter("height", 1.95)
	_cocoon_mat.set_shader_parameter("cover", 0.0)
	_cocoon_mat.set_shader_parameter("reveal_line", 2.2)
	_cocoon_mat.set_shader_parameter("energy", 1.15)
	_cocoon_mat.set_shader_parameter("offset", 0.975)
	_cocoon.material_override = _cocoon_mat
	_cocoon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cocoon.visible = false
	add_child(_cocoon)
	# the ribbons: eight thin helical strips of light (four each way) around her body
	_ribbons = MeshInstance3D.new()
	_ribbons.mesh = _helix_mesh()
	_ribbon_mat = ShaderMaterial.new()
	_ribbon_mat.shader = load("res://shaders/ribbon_light.gdshader")
	_ribbon_mat.set_shader_parameter("color", Color(col, 1.0))
	_ribbon_mat.set_shader_parameter("accent", Color(acc, 1.0))
	_ribbon_mat.set_shader_parameter("height", 1.95)
	_ribbon_mat.set_shader_parameter("cover", 0.0)
	_ribbon_mat.set_shader_parameter("reveal_line", 2.3)
	_ribbons.material_override = _ribbon_mat
	_ribbons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbons.visible = false
	add_child(_ribbons)
	var spm := FX.pm_motes("self", "burst")
	spm.color = col.lerp(Color.WHITE, 0.2)
	spm.gravity = Vector3(0, -0.6 if petals else 0.4, 0)
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	spm.emission_ring_axis = Vector3.UP
	spm.emission_ring_radius = 0.42
	spm.emission_ring_inner_radius = 0.3
	spm.emission_ring_height = 0.05
	_shed = FX.particles(70, 1.6, spm, FX.mote_mesh(0.05 if petals else 0.035))
	_shed.emitting = false
	add_child(_shed)
	# stage 4: the orbit: 8 arc segments + 8 beads, scattered then assembled
	_orbit = Node3D.new()
	add_child(_orbit)
	_orbit.visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c.character_id)
	for k in 8:
		var a := TAU * k / 8.0
		var seg := _arc(0.9, a + 0.08, a + TAU / 8.0 - 0.08, col if k % 2 == 0 else acc)
		_orbit.add_child(seg)
		var scatter := Transform3D(Basis.from_euler(Vector3(rng.randf_range(-2, 2), rng.randf_range(-3, 3), rng.randf_range(-2, 2))),
			Vector3(cos(a), rng.randf_range(-0.4, 1.4), sin(a)) * rng.randf_range(2.2, 3.4))
		_segments.append({"node": seg, "from": scatter, "to": Transform3D.IDENTITY, "delay": k * 0.06})
		var bead := _bead(0.032, acc if k % 2 == 0 else col)
		_orbit.add_child(bead)
		var bt := Transform3D(Basis.IDENTITY, Vector3(cos(a), 0, sin(a)) * 0.9)
		_segments.append({"node": bead, "from": Transform3D(Basis.IDENTITY, bt.origin * 3.2 + Vector3(0, rng.randf_range(0.5, 2.0), 0)), "to": bt, "delay": 0.25 + k * 0.05})
	_orbit_light = FX.light(col, 0.0, 5.0)
	_orbit_light.position = Vector3(0, 2.6, 0.4)          # above her, never on her body (no washed-out outfit)
	add_child(_orbit_light)


## Eight helical ribbon strips following her silhouette (wider at the skirt, narrower at the shoulders).
func _helix_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 1.95
	var steps := 90
	for i in 8:
		var dir := 1.0 if i < 4 else -1.0
		var phase := TAU * float(i % 4) / 4.0 + (0.4 if dir < 0.0 else 0.0)
		var turns := 2.6
		var w := 0.075
		var prev := []
		for k in steps + 1:
			var u := float(k) / steps
			var y := u * h
			var r := lerpf(0.46, 0.27, smoothstep(0.25, 0.85, u)) + 0.04 * sin(u * PI * 2.0)
			var a := phase + dir * turns * TAU * u
			var p := Vector3(sin(a) * r, y, cos(a) * r)
			var cur := [p + Vector3(0, -w, 0), p + Vector3(0, w, 0), u]
			if not prev.is_empty():
				for v in [[prev[0], prev[2], 0.0], [prev[1], prev[2], 1.0], [cur[1], u, 1.0], [prev[0], prev[2], 0.0], [cur[1], u, 1.0], [cur[0], u, 0.0]]:
					st.set_uv(Vector2(float(v[1]) * turns, float(v[2])))
					st.add_vertex(v[0])
			prev = cur
	return st.commit()


func _torus(r: float, thick: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - thick
	tm.outer_radius = r + thick
	tm.rings = 64
	tm.ring_segments = 6
	mi.mesh = tm
	mi.rotation.x = PI * 0.5          # vertical ring (faces sideways)
	mi.material_override = _glow(c, 2.2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _bead(r: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _glow(c, 3.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A flat arc band (part of the orbit ring), built as a strip mesh.
func _arc(r: float, a0: float, a1: float, c: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	for i in n:
		var u0 := lerpf(a0, a1, float(i) / n)
		var u1 := lerpf(a0, a1, float(i + 1) / n)
		var p := [Vector3(cos(u0) * (r - 0.03), 0, sin(u0) * (r - 0.03)), Vector3(cos(u0) * (r + 0.03), 0, sin(u0) * (r + 0.03)),
			Vector3(cos(u1) * (r + 0.03), 0, sin(u1) * (r + 0.03)), Vector3(cos(u1) * (r - 0.03), 0, sin(u1) * (r - 0.03))]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.add_vertex(p[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _glow(c, 2.4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Drive every layer from the sequence time `t` and the stage table `st` (seconds):
## {awaken, build, cover, swap, reveal_end, orbit, orbit_lock, pose, end}
func update(t: float, st: Dictionary, delta: float) -> Dictionary:
	var out := {}
	global_position = mage.global_position
	# stage 1: ambient motes gather
	_ambient.emitting = t >= float(st.awaken) and t < float(st.cover)
	# stage 2: orbit frames rise and turn, tightening
	var rise := smoothstep(float(st.build), float(st.build) + 1.2, t)
	var gone := smoothstep(float(st.cover) + 0.3, float(st.swap), t)
	for i in _frames.size():
		var f := _frames[i]
		f.visible = rise > 0.0 and gone < 1.0
		f.position.y = lerpf(-1.6, 1.0, rise)
		var tight := lerpf(1.25, 0.75, smoothstep(float(st.build), float(st.swap), t)) * (1.0 - gone * 0.6)
		f.scale = Vector3.ONE * tight
		f.rotation.y += delta * (0.8 + i * 0.5 + 2.5 * smoothstep(float(st.build), float(st.swap), t))
	# stage 3: cocoon wraps up (cover), holds through the swap, then unravels head -> feet (reveal)
	var cover := smoothstep(float(st.cover), float(st.swap) - 0.15, t)
	var r0 := maxf(float(st.swap), swapped_at if swapped_at >= 0.0 else t) + 0.15
	var reveal := smoothstep(r0, maxf(float(st.reveal_end), r0 + 1.2), t) if swapped_at >= 0.0 else 0.0
	_cocoon.visible = cover > 0.0 and reveal < 1.0
	_ribbons.visible = cover > 0.0 and reveal < 1.0
	_ribbons.global_position = mage.global_position - Vector3(0, 0.03, 0)
	_ribbons.rotation.y += delta * 2.2
	_ribbon_mat.set_shader_parameter("cover", cover)
	_cocoon.global_position = mage.global_position - Vector3(0, 0.03, 0) + Vector3(0, 0.975, 0)
	_cocoon_mat.set_shader_parameter("cover", cover)
	# sealed (nearly opaque) only around the outfit change itself
	# the veil holds until the outfit has REALLY changed (a slow frame can delay the swap), then opens
	var open_from := (swapped_at if swapped_at >= 0.0 else maxf(t, float(st.swap))) + 0.35
	var seal := smoothstep(float(st.swap) - 0.6, float(st.swap) - 0.15, t) * (1.0 - smoothstep(open_from, open_from + 0.4, t))
	_cocoon_mat.set_shader_parameter("seal", seal)
	out["seal"] = seal
	# the reveal line sweeps from above her head down past her feet (shader heights: 0 = cocoon bottom)
	var line := lerpf(2.05, -0.1, reveal)
	_cocoon_mat.set_shader_parameter("reveal_line", line)
	_ribbon_mat.set_shader_parameter("reveal_line", line)
	_shed.emitting = reveal > 0.02 and reveal < 0.98
	_shed.global_position = mage.global_position + Vector3(0, clampf(line, 0.05, 1.9), 0)
	out["cover"] = cover
	out["reveal"] = reveal
	# stage 4: the orbit assembles
	var o0 := float(st.orbit)
	_orbit.visible = t >= o0
	_orbit.global_position = mage.global_position + Vector3(0, 1.0, 0)
	if t >= o0:
		for s in _segments:
			var k: float = clampf((t - o0 - float(s.delay)) / maxf(float(st.orbit_lock) - o0 - 0.4, 0.2), 0.0, 1.0)
			k = 1.0 - pow(1.0 - k, 3.0)
			var a: Transform3D = s.from
			var b: Transform3D = s.to
			(s.node as Node3D).transform = a.interpolate_with(b, k)
		_orbit.rotation.y += delta * (0.6 if t > float(st.orbit_lock) else 1.6)
		_orbit.rotation.z = 0.18 * sin(t * 0.7)
	if t >= float(st.orbit_lock) and not _locked:
		_locked = true
		out["locked"] = true
		FX.burst(get_parent(), mage.global_position + Vector3(0, 1.0, 0), 40, 1.0, FX.pm_motes("self", "burst"), FX.mote_mesh(0.04))
	var lk := 1.0 - clampf(absf(t - float(st.orbit_lock)) / 0.6, 0.0, 1.0)
	_orbit_light.light_energy = (0.2 * float(_orbit.visible) + 0.7 * lk) * _light_scale
	return out


## After the sequence the orbit stays as her permanent emblem only while a surge lasts; here it fades out.
func fade_out(seconds := 0.8) -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.001, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
