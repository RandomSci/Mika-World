extends Node3D

# Mika's Arcane Sanctuary: standalone Godot 4 visual prototype.
# All geometry is procedural and built at runtime. No external assets needed.

var camera: Camera3D
var camera_yaw := 0.65
var camera_pitch := -0.24
var camera_distance := 18.0
var dragging := false
var time_passed := 0.0
var pulse := 0.0
var orb: Node3D
var orbiters: Array[Node3D] = []
var fireflies: Array[Node3D] = []
var lantern_lights: Array[OmniLight3D] = []
var avatar_proxy: Node3D
var avatar_installed := false
var rings: Array[Node3D] = []
var blue_glow: StandardMaterial3D
var purple_glow: StandardMaterial3D
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 120210
	_build_environment()
	_build_terrain()
	_build_ceremonial_circle()
	_build_pillars_and_gate()
	_build_trees()
	_build_crystals()
	_build_fireflies()
	_build_avatar()
	_build_camera()
	_build_hud()
	print("Mika World Godot prototype loaded. SPACE: cast | Left drag: orbit | Scroll: zoom")

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var gradient := ProceduralSkyMaterial.new()
	gradient.sky_top_color = Color("080e24")
	gradient.sky_horizon_color = Color("39305b")
	gradient.ground_bottom_color = Color("0a1620")
	gradient.ground_horizon_color = Color("211d3c")
	sky.sky_material = gradient
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8195c5")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-53, -31, 0)
	moon.light_color = Color("a8c1ff")
	moon.light_energy = 0.52
	moon.shadow_enabled = false
	add_child(moon)

	blue_glow = _mat(Color("6fe8ff"), 2.2, true)
	purple_glow = _mat(Color("b968ff"), 2.0, true)

func _mat(color: Color, emission_energy: float = 0.0, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.72
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _mesh(mesh: Mesh, material: Material, position: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var object := MeshInstance3D.new()
	object.mesh = mesh
	object.material_override = material
	object.position = position
	(parent if parent != null else self).add_child(object)
	return object

func _box(size: Vector3, material: Material, position: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(mesh, material, position, parent)

func _ball(radius: float, material: Material, position: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 8
	return _mesh(mesh, material, position, parent)

func _column(radius: float, height: float, material: Material, position: Vector3, parent: Node3D = null, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	return _mesh(mesh, material, position, parent)

func _build_terrain() -> void:
	var ground := PlaneMesh.new()
	ground.size = Vector2(110, 110)
	_mesh(ground, _mat(Color("0e2028")), Vector3.ZERO)
	var plinth := _column(7.5, 0.6, _mat(Color("34364a")), Vector3(0, 0.25, 0))
	plinth.mesh.material = _mat(Color("34364a"))
	_column(6.65, 0.08, _mat(Color("16162b")), Vector3(0, 0.59, 0))

	# Quiet broken stone pathway toward the torii arch.
	var stone_mat := _mat(Color("3d4454"))
	for n in range(16):
		var z := -8.5 - float(n) * 1.85
		for side in range(2):
			var offset := -0.75 if side == 0 else 0.75
			var slab := _box(Vector3(1.3, 0.11, 1.55), stone_mat, Vector3(offset + rng.randf_range(-0.07, 0.07), 0.08, z))
			slab.rotation.y = rng.randf_range(-0.05, 0.05)

func _build_ceremonial_circle() -> void:
	var silver := _mat(Color("9afaff"), 2.8, true)
	var lilac := _mat(Color("ba96ff"), 1.6, true)
	for r in [2.05, 3.5, 4.45, 5.65, 6.3]:
		_add_ring(float(r), 0.025 if r < 5.0 else 0.04, 0.642, silver)
	for j in range(12):
		var angle := float(j) * TAU / 12.0
		_add_line(Vector3(cos(angle) * 3.5, 0.648, sin(angle) * 3.5), Vector3(cos(angle) * 4.45, 0.648, sin(angle) * 4.45), 0.028, silver)
	for j in range(6):
		var angle := float(j) * TAU / 6.0
		_add_line(Vector3(cos(angle) * 3.48, 0.650, sin(angle) * 3.48), Vector3(cos(angle + TAU / 3.0) * 3.48, 0.650, sin(angle + TAU / 3.0) * 3.48), 0.026, lilac)
	for j in range(40):
		var angle := float(j) * TAU / 40.0
		var inner := Vector3(cos(angle) * 4.82, 0.657, sin(angle) * 4.82)
		var outer := Vector3(cos(angle) * 5.28, 0.657, sin(angle) * 5.28)
		_add_line(inner, outer, 0.027, silver)
		if j % 2 == 0:
			var v := Vector3(cos(angle + 0.042) * 5.16, 0.658, sin(angle + 0.042) * 5.16)
			_add_line(outer, v, 0.025, silver)
	# Decorative rotating triangles suspended above the center.
	for radius in [1.35, 2.75]:
		var ring := Node3D.new()
		ring.position.y = 2.0 + radius * 0.2
		add_child(ring)
		for j in range(3):
			var a := float(j) * TAU / 3.0
			var b := float(j + 1) * TAU / 3.0
			_add_line(Vector3(cos(a) * radius, 0, sin(a) * radius), Vector3(cos(b) * radius, 0, sin(b) * radius), 0.018, lilac, ring)
		ring.visible = false
		rings.append(ring)

func _add_line(a: Vector3, b: Vector3, thickness: float, material: Material, parent: Node3D = null) -> void:
	var d := b - a
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, thickness, d.length())
	var line := _mesh(mesh, material, (a + b) * 0.5, parent)
	line.look_at_from_position(line.position, b, Vector3.UP)

func _add_ring(radius: float, thickness: float, y: float, material: Material, center: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	for i in range(97):
		var a := TAU * float(i) / 96.0
		for side in [-1.0, 1.0]:
			var rr: float = radius + thickness * float(side)
			vertices.append(Vector3(cos(a) * rr + center.x, y + center.y, sin(a) * rr + center.z))
	var indices := PackedInt32Array()
	for i in range(96):
		var base := i * 2
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh(mesh, material, Vector3.ZERO)

func _build_pillars_and_gate() -> void:
	var basalt := _mat(Color("343149"))
	var dark_wood := _mat(Color("33243f"))
	var gold := _mat(Color("f2bd76"), 1.4)
	for i in range(10):
		var a := float(i) * TAU / 10.0
		var x := cos(a) * 9.5
		var z := sin(a) * 9.5
		_column(0.50, 3.3, basalt, Vector3(x, 1.65, z))
		_column(0.59, 0.17, _mat(Color("48425d")), Vector3(x, 3.35, z))
		_ball(0.17, gold, Vector3(x, 3.58, z))
		var light := OmniLight3D.new()
		light.light_color = Color("ffb46b")
		light.light_energy = 0.48
		light.omni_range = 4.8
		light.position = Vector3(x, 3.6, z)
		add_child(light)
		lantern_lights.append(light)
	# Two archways along a stone path, referencing Japanese fantasy architecture.
	for z in [-9.1, -17.0]:
		for x in [-3.2, 3.2]:
			_box(Vector3(0.45, 5.8, 0.5), dark_wood, Vector3(x, 2.9, z))
		_box(Vector3(7.4, 0.48, 0.65), dark_wood, Vector3(0, 5.8, z))
		_box(Vector3(8.1, 0.26, 1.25), _mat(Color("5c385b")), Vector3(0, 6.16, z))
		for x in [-2.1, 2.1]:
			_box(Vector3(0.12, 1.6, 0.16), _mat(Color("845e87")), Vector3(x, 4.95, z))
	# Stone pedestal and luminous spellbook, off to the right of the circle.
	_column(1.25, 2.25, basalt, Vector3(9.5, 1.12, 2.5))
	_box(Vector3(2.5, 0.23, 2.1), _mat(Color("625873")), Vector3(9.5, 2.33, 2.5))
	_box(Vector3(0.92, 0.11, 0.66), purple_glow, Vector3(9.5, 2.57, 2.5))

func _build_trees() -> void:
	var bark := _mat(Color("322939"))
	var pines := [_mat(Color("162e35")), _mat(Color("234341")), _mat(Color("343654"))]
	var blossoms := [_mat(Color("925986")), _mat(Color("b575a1")), _mat(Color("775a9b"))]
	for i in range(38):
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(18.0, 48.0)
		var x := cos(a) * r
		var z := sin(a) * r
		var h := rng.randf_range(4.0, 9.0)
		_column(0.33, h, bark, Vector3(x, h * 0.5, z))
		if i % 3 == 0:
			for b in range(4):
				var offset := Vector3(rng.randf_range(-2.0, 2.0), h - 0.25 + rng.randf_range(-0.7, 1.1), rng.randf_range(-2.0, 2.0))
				_ball(rng.randf_range(1.6, 2.65), blossoms[i % 3], Vector3(x, 0, z) + offset)
		else:
			for b in range(3):
				_column(2.15 - float(b) * 0.28, 3.0, pines[(i + b) % 3], Vector3(x, h - 1.0 + float(b) * 0.9, z), self, 0.08)

func _build_crystals() -> void:
	for i in range(14):
		var a := float(i) * TAU / 14.0 + 0.2
		var r := rng.randf_range(12.2, 17.5)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		var material := blue_glow if i % 3 == 0 else purple_glow
		var crystal := _column(0.25 + rng.randf_range(0.0, 0.15), rng.randf_range(1.2, 2.2), material, pos + Vector3(0, 0.8, 0), self, 0.0)
		crystal.rotation.z = rng.randf_range(-0.4, 0.4)
		crystal.rotation.x = rng.randf_range(-0.25, 0.25)

func _build_fireflies() -> void:
	var warm := _mat(Color("d0a6ff"), 2.1, true)
	var cold := _mat(Color("a7fdff"), 2.7, true)
	for i in range(100):
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(1.5, 26.0)
		var pos := Vector3(cos(a) * r, rng.randf_range(1.25, 8.5), sin(a) * r)
		var firefly := _ball(rng.randf_range(0.035, 0.09), warm if i % 2 == 0 else cold, pos)
		fireflies.append(firefly)
	orb = Node3D.new()
	orb.position = Vector3(0, 2.5, 0)
	add_child(orb)
	_ball(0.46, _mat(Color("85efff"), 3.8, true), Vector3.ZERO, orb)
	_ball(0.63, _mat(Color(0.32, 0.65, 0.93, 0.16), 1.1, true), Vector3.ZERO, orb)
	for i in range(8):
		var particle := _ball(0.095, purple_glow, Vector3.ZERO, orb)
		orbiters.append(particle)

func _build_avatar() -> void:
	# The real VRM is NOT packaged. Godot imports GLB scenes after the editor scans it.
	if ResourceLoader.exists("res://mika.glb"):
		var avatar_scene := load("res://mika.glb") as PackedScene
		if avatar_scene != null:
			var instance := avatar_scene.instantiate() as Node3D
			if instance != null:
				instance.name = "ActualMika"
				instance.position = Vector3(0, 0.70, 3.2)
				instance.rotation.y = PI
				add_child(instance)
				avatar_installed = true
				return
	# Stand-in character is intentionally identifiable as a prototype.
	avatar_proxy = Node3D.new()
	avatar_proxy.name = "TemporaryAvatarStandIn"
	avatar_proxy.position = Vector3(0, 0.70, 3.2)
	add_child(avatar_proxy)
	var skin := _mat(Color("ffe2d1"))
	var hair := _mat(Color("d8b9f4"))
	var shirt := _mat(Color("e5d9ff"))
	var skirt := _mat(Color("342d5c"))
	_ball(0.36, skin, Vector3(0, 1.52, 0), avatar_proxy)
	_ball(0.42, hair, Vector3(0, 1.75, -0.08), avatar_proxy)
	_ball(0.27, hair, Vector3(-0.22, 1.42, -0.22), avatar_proxy)
	_ball(0.27, hair, Vector3(0.22, 1.42, -0.22), avatar_proxy)
	_box(Vector3(0.62, 0.73, 0.37), shirt, Vector3(0, 0.95, 0), avatar_proxy)
	_column(0.45, 0.42, skirt, Vector3(0, 0.62, 0), avatar_proxy, 0.31)
	for x in [-0.18, 0.18]:
		_column(0.09, 0.58, skin, Vector3(x, 0.25, 0), avatar_proxy)
		var arm := _column(0.10, 0.65, skin, Vector3(x * 2.3, 0.93, 0), avatar_proxy)
		arm.rotation.z = -0.2 if x < 0 else 0.2
	for x in [-0.19, 0.19]:
		var ear := _column(0.13, 0.65, hair, Vector3(x, 2.20, -0.04), avatar_proxy, 0.01)
		ear.rotation.z = -0.1 if x < 0 else 0.1

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "CinematicOrbitCamera"
	camera.fov = 61.0
	camera.current = true
	add_child(camera)
	_update_camera()

func _update_camera() -> void:
	var focus := Vector3(0, 1.9, 0)
	var dir := Vector3(sin(camera_yaw) * cos(camera_pitch), -sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch))
	camera.position = focus + dir * camera_distance
	camera.look_at(focus, Vector3.UP)

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var title := Label.new()
	title.position = Vector2(22, 18)
	title.text = "MIKA WORLD  /  ARCANE SANCTUARY"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("f4deff"))
	hud.add_child(title)
	var instructions := Label.new()
	instructions.position = Vector2(22, 52)
	instructions.text = "LEFT DRAG: ORBIT   •   SCROLL: ZOOM   •   SPACE: CAST   •   R: RESET"
	instructions.add_theme_font_size_override("font_size", 12)
	instructions.add_theme_color_override("font_color", Color("d4bfe5"))
	hud.add_child(instructions)
	var notice := Label.new()
	notice.position = Vector2(22, 78)
	notice.text = "PROCEDURAL TEST AVATAR  |  Put an imported mika.glb in this project to use Mika" if not avatar_installed else "MIKA AVATAR LOADED FROM mika.glb"
	notice.add_theme_font_size_override("font_size", 11)
	notice.add_theme_color_override("font_color", Color("d3c1e3"))
	hud.add_child(notice)

func _process(delta: float) -> void:
	time_passed += delta
	if pulse > 0.0:
		pulse = max(0.0, pulse - delta)
	orb.position = Vector3(0, 2.5 + sin(time_passed * 1.4) * 0.25, 0)
	var swell := 1.0 + sin(time_passed * 2.2) * 0.11 + pulse * 0.5
	orb.scale = Vector3.ONE * swell
	for i in range(orbiters.size()):
		var a := time_passed * (1.8 if i % 2 == 0 else -1.3) + TAU * float(i) / float(orbiters.size())
		var r := 1.2 + 0.6 * pulse
		orbiters[i].position = Vector3(cos(a) * r, sin(a * 1.6) * 0.42, sin(a) * r)
	for i in range(fireflies.size()):
		var f := fireflies[i]
		f.position.y += sin(time_passed * 0.8 + float(i) * 2.31) * delta * 0.12
	for i in range(rings.size()):
		rings[i].visible = pulse > 0.0
		rings[i].rotation.y += delta * (0.4 if i % 2 == 0 else -0.3)
	for i in range(lantern_lights.size()):
		lantern_lights[i].light_energy = 0.45 + 0.08 * sin(time_passed * 1.8 + float(i) * 1.3)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = max(4.5, camera_distance - 1.3)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = min(42.0, camera_distance + 1.3)
			_update_camera()
	elif event is InputEventMouseMotion and dragging:
		camera_yaw -= event.relative.x * 0.007
		camera_pitch = clamp(camera_pitch + event.relative.y * 0.005, -0.70, 0.72)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			pulse = 2.0
		elif event.keycode == KEY_R:
			camera_yaw = 0.65
			camera_pitch = -0.24
			camera_distance = 18.0
			_update_camera()
		elif event.keycode == KEY_M and avatar_proxy != null:
			avatar_proxy.visible = not avatar_proxy.visible
