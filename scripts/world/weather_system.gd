class_name WeatherSystem
extends Node
## Weather (V3 Part 4: "an unexpected storm", "listening to rain beneath shelter"). One sky for the world, kept in
## WorldState.weather (persists): clear, overcast, rain or storm, each lasting world hours, chosen by the region's own
## leanings (the mountains brew storms, the forests get their showers, nothing falls in a cave). It is SHOWN on top
## of the area's own hour-by-hour light: the sun dims and the haze thickens under cloud, rain falls round the camera
## (streaks that keep vertical), the rain is heard - on leaves, or muffled on a roof when you stand under one - and in
## a storm lightning flashes and thunder follows a few seconds later, as far off as the flash was.

const KINDS := {
	"clear": {"cloud": 0.0, "rain": 0.0},
	"overcast": {"cloud": 0.55, "rain": 0.0},
	"rain": {"cloud": 0.75, "rain": 0.6},
	"storm": {"cloud": 0.95, "rain": 1.0},
}
const REGION_BIAS := {    # weights for the next weather, by region (WorldState.areas[..].region)
	"default": {"clear": 5.0, "overcast": 2.5, "rain": 1.6, "storm": 0.4},
	"celestial_highlands": {"clear": 4.0, "overcast": 2.5, "rain": 1.5, "storm": 1.2},
	"enchanted_forest": {"clear": 4.0, "overcast": 2.5, "rain": 2.2, "storm": 0.5},
}

var main: Node
var enabled := true
var cloud := 0.0                  # shown amount (eases toward the target)
var rain := 0.0
var _rain_fx: GPUParticles3D
var _rain_mat: StandardMaterial3D
var _rain_player: AudioStreamPlayer
var _roof_player: AudioStreamPlayer
var _splash: GPUParticles3D
var _cover: GPUParticlesCollisionHeightField3D
var _trunks: Array = []           # big trees of the current area: [pos, radius] (their trunk colliders)
var _trunks_of: Object = null
var _flash: DirectionalLight3D
var _next_flash := 0.0
var _written := {}                # env/sun property -> value this system last wrote (to tell the area's own updates)
var _base := {}                   # property -> the area's own value under the weather
var log: Array = []


func setup(m: Node) -> void:
	main = m
	if RenderProfile.options.has("no-weather"):
		enabled = false
	if WorldState.weather.is_empty():
		WorldState.weather = {"kind": "clear", "until": WorldState.world_min + 120.0}
	_build_rain()
	_rain_player = _loop("res://assets/audio/synth/amb_rain_light.ogg")
	_roof_player = _loop("res://assets/audio/synth/amb_rain_roof.ogg")


func _loop(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		var st := (load(path) as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		st.loop = true
		p.stream = st
	p.bus = "Ambience" if AudioServer.get_bus_index("Ambience") != -1 else "Master"
	p.volume_db = -80.0
	add_child(p)
	return p


func _build_rain() -> void:
	_rain_fx = GPUParticles3D.new()
	_rain_fx.name = "Rain"
	_rain_fx.amount = 6000
	_rain_fx.lifetime = 1.4
	_rain_fx.visibility_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 40, 50))
	_rain_fx.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 22)
	pm.direction = Vector3(0.08, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 13.0
	pm.initial_velocity_max = 16.0
	pm.gravity = Vector3(0, -4, 0)
	_rain_fx.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.7)
	# a soft streak: transparent at the ends and the edges, so drops read as motion, not as white sticks
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 16
	gt.height = 64
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.albedo_texture = gt
	_rain_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA   # no streaks smeared across the lens
	_rain_mat.distance_fade_min_distance = 0.6
	_rain_mat.distance_fade_max_distance = 3.0
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_mat.billboard_keep_scale = true
	_rain_mat.albedo_color = Color(0.75, 0.8, 0.88, 0.0)
	_rain_mat.disable_receive_shadows = true
	q.material = _rain_mat
	_rain_fx.draw_pass_1 = q
	_rain_fx.emitting = false
	# drops stop on whatever is above the ground (roofs, canopies, her hood) and burst into a tiny splash
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.collision_use_scale = false
	_rain_fx.collision_base_size = 0.02
	pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	pm.sub_emitter_amount_at_collision = 1
	add_child(_rain_fx)
	_splash = GPUParticles3D.new()
	_splash.name = "RainSplash"
	_splash.amount = 2400
	_splash.lifetime = 0.22
	_splash.emitting = false
	_splash.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var sp := ParticleProcessMaterial.new()
	sp.direction = Vector3(0, 1, 0)
	sp.spread = 70.0
	sp.initial_velocity_min = 0.6
	sp.initial_velocity_max = 1.3
	sp.gravity = Vector3(0, -9.8, 0)
	sp.scale_min = 0.6
	sp.scale_max = 1.0
	_splash.process_material = sp
	var sq := QuadMesh.new()
	sq.size = Vector2(0.03, 0.03)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.albedo_color = Color(0.8, 0.85, 0.92, 0.35)
	sm.albedo_texture = gt
	sq.material = sm
	_splash.draw_pass_1 = sq
	add_child(_splash)
	_rain_fx.sub_emitter = _rain_fx.get_path_to(_splash)
	# the height of whatever is overhead, around the camera (rendered from above when the camera moves)
	_cover = GPUParticlesCollisionHeightField3D.new()
	_cover.name = "RainCover"
	_cover.size = Vector3(48, 40, 48)
	_cover.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_cover.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_cover.follow_camera_enabled = true
	_cover.visible = false
	add_child(_cover)


## The region's sky: no weather inside, under rock or between walls.
func sheltered_area() -> bool:
	var a: Dictionary = WorldState.areas.get(main.streaming.current_id, {})
	return bool(a.get("interior", false)) or main.world is CaveArea


func kind() -> String:
	return String(WorldState.weather.get("kind", "clear"))


func raining() -> bool:
	return rain > 0.25 and not sheltered_area()


## Next weather when this spell of it is over (weighted by the region's leanings; a storm passes into rain).
func _advance() -> void:
	var wtr: Dictionary = WorldState.weather
	if WorldState.world_min < float(wtr.get("until", 0.0)):
		return
	var region := String(WorldState.areas.get(main.streaming.current_id, {}).get("region", "default"))
	var bias: Dictionary = REGION_BIAS.get(region, REGION_BIAS.default)
	var prev := kind()
	var nk := prev
	if prev == "storm":
		nk = "rain"
	else:
		var total := 0.0
		for k in bias:
			total += float(bias[k]) * (0.4 if k == prev else 1.0)
		var r := randf() * total
		for k in bias:
			r -= float(bias[k]) * (0.4 if k == prev else 1.0)
			if r <= 0.0:
				nk = String(k)
				break
	var hours := randf_range(1.0, 4.0) if nk in ["rain", "storm"] else randf_range(2.0, 7.0)
	set_weather(nk, hours)


func set_weather(k: String, hours := 2.0) -> void:
	WorldState.weather = {"kind": k, "until": WorldState.world_min + hours * 60.0, "since": WorldState.clock_text()}
	log.append({"kind": k, "clock": WorldState.clock_text(), "hours": snappedf(hours, 0.1)})
	if log.size() > 40:
		log.pop_front()
	WorldState._dirty = true


func _process(delta: float) -> void:
	if main == null or main.get("world") == null or not is_instance_valid(main.world):
		return
	if enabled:
		_advance()
	var k: Dictionary = KINDS.get(kind(), KINDS.clear)
	var inside := sheltered_area()
	var tc := 0.0 if (inside or not enabled) else float(k.cloud)
	var tr := 0.0 if (inside or not enabled) else float(k.rain)
	cloud = move_toward(cloud, tc, delta * 0.05)          # weather comes and goes over ~20 s of screen time
	var was := rain
	rain = move_toward(rain, tr, delta * 0.06)
	if was < 0.3 and rain >= 0.3:
		_first_drops()
	_apply_light()
	_apply_rain(delta)
	_lightning(delta)


## Dim the area's own light by the cloud (the area keeps setting its hour's light; this rides on top of it).
func _apply_light() -> void:
	var w = main.world
	var env: Environment = w.get("env")
	var sun: DirectionalLight3D = w.get("sun")
	if env == null:
		return
	_mod(env, "fog_density", 1.0 + cloud * 2.2 + rain * 1.5)
	_mod(env, "background_energy_multiplier", 1.0 - cloud * 0.45)
	_mod(env, "ambient_light_energy", 1.0 - cloud * 0.08)   # overcast: the sky's light stays, the sun goes
	if sun:
		_mod(sun, "light_energy", 1.0 - cloud * 0.72)
		_mod(sun, "shadow_opacity", 1.0 - cloud * 0.7)     # and its shadows go soft and faint


func _mod(obj: Object, prop: String, factor: float) -> void:
	var key := "%d:%s" % [obj.get_instance_id(), prop]
	var cur: float = obj.get(prop)
	if not _written.has(key) or absf(cur - float(_written[key])) > 0.0001:
		_base[key] = cur                                  # the area set a new value: that is the base now
	var v := float(_base[key]) * factor
	obj.set(prop, v)
	_written[key] = v


func _apply_rain(_delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var on := rain > 0.02
	_rain_fx.emitting = on
	_splash.emitting = on
	_cover.visible = on
	if cam and on:
		_rain_fx.global_position = cam.global_position + Vector3(0, 11.0, 0) - cam.global_transform.basis.z * 6.0
	_rain_fx.amount_ratio = clampf(rain, 0.05, 1.0)
	_rain_mat.albedo_color.a = 0.16 + rain * 0.14
	# heard: on the leaves, or muffled when the camera / Mika stands under a roof
	var under := _under_roof()
	var loud := linear_to_db(maxf(rain, 0.0001)) - 4.0
	_rain_player.volume_db = -80.0 if rain < 0.02 else (loud - (14.0 if under else 0.0))
	_roof_player.volume_db = -80.0 if rain < 0.02 or not under else loud + 2.0
	for p in [_rain_player, _roof_player]:
		if (p as AudioStreamPlayer).volume_db > -79.0 and not (p as AudioStreamPlayer).playing and (p as AudioStreamPlayer).stream:
			(p as AudioStreamPlayer).play()
		elif (p as AudioStreamPlayer).volume_db <= -79.0 and (p as AudioStreamPlayer).playing:
			(p as AudioStreamPlayer).stop()


func _under_roof() -> bool:
	var m: Node3D = main.characters.get("mika")
	if m == null or not m.is_inside_tree():
		return false
	return covered(m.global_position, [m.get_rid()])


## Something solid overhead at p (a roof, an arch, a rock shelf).
func covered(p: Vector3, exclude := []) -> bool:
	var vp := get_viewport()
	if vp == null or vp.world_3d == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.8, 0), p + Vector3(0, 9.0, 0), 1 | 4 | HouseBuilder.ROOF_LAYER)
	q.exclude = exclude
	return not vp.world_3d.direct_space_state.intersect_ray(q).is_empty()


## Is a person standing out of the rain here: under something solid, or close in under a big tree.
func sheltered_at(p: Vector3) -> bool:
	if sheltered_area() or covered(p):
		return true
	for t in _big_trees():
		if Vector2(p.x - t[0].x, p.z - t[0].z).length() < float(t[1]) + 1.4:
			return true
	return false


func _big_trees() -> Array:
	var w = main.world
	if w != _trunks_of:
		_trunks_of = w
		_trunks = []
		if w != null:
			for b in (w as Node).find_children("TreeTrunks*", "StaticBody3D", true, false):
				for cs in (b as Node).get_children():
					if cs is CollisionShape3D and (cs as CollisionShape3D).shape is CylinderShape3D:
						var r := ((cs as CollisionShape3D).shape as CylinderShape3D).radius
						if r >= 0.3:
							var h := ((cs as CollisionShape3D).shape as CylinderShape3D).height
							_trunks.append([(cs as Node3D).global_position - Vector3(0, h * 0.5 - 0.2, 0), r])
	return _trunks


## Places to wait out the rain near p, nearest first: a doorstep or stall under its eaves, the lee of a big tree.
## [{pos, face (a point to look out at), kind: "eaves" | "tree"}], all on the walkable navmesh.
func shelter_spots(p: Vector3, radius := 35.0) -> Array:
	var out := []
	var w = main.world
	if w == null:
		return out
	var nav_map: RID = (w as Node3D).get_world_3d().navigation_map
	var anchors: Dictionary = w.get("anchors") if w.get("anchors") != null else {}
	for k in anchors:
		var ks := String(k)
		if not (ks.begins_with("home:") or ks.begins_with("stall:") or ks.begins_with("library") or ks.begins_with("quarters")):
			continue
		var a: Dictionary = anchors[k]
		var ap: Vector3 = a.pos
		if ap.distance_to(p) > radius:
			continue
		# step in toward the wall until the eaves are overhead
		var out_dir := Vector3(sin(float(a.get("yaw", 0.0))), 0, cos(float(a.get("yaw", 0.0))))
		for step in [0.0, 0.35, 0.7, -0.35]:
			var c: Vector3 = ap - out_dir * float(step)
			if covered(c):
				var snapped := NavigationServer3D.map_get_closest_point(nav_map, c)
				if snapped.distance_to(c) < 0.6:
					out.append({"pos": snapped, "face": snapped + out_dir * 6.0, "kind": "eaves", "label": ks})
				break
	for t in _big_trees():
		var tp: Vector3 = t[0]
		if tp.distance_to(p) > radius:
			continue
		var away := Vector3(p.x - tp.x, 0, p.z - tp.z)
		away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
		var c2: Vector3 = tp + away * (float(t[1]) + 0.75)
		var sn := NavigationServer3D.map_get_closest_point(nav_map, c2)
		if Vector2(sn.x - tp.x, sn.z - tp.z).length() < float(t[1]) + 1.4 and absf(sn.y - c2.y) < 1.5:
			out.append({"pos": sn, "face": sn + away * 6.0, "kind": "tree", "label": "the big tree"})
	out.sort_custom(func(a, b): return (a.pos as Vector3).distance_to(p) < (b.pos as Vector3).distance_to(p))
	return out


## A storm: lightning now and then; the thunder follows as many seconds later as it is far (sound ~ 340 m/s).
func _lightning(delta: float) -> void:
	_next_flash -= delta
	if kind() != "storm" or rain < 0.6 or sheltered_area():
		return
	if _next_flash > 0.0:
		return
	_next_flash = randf_range(7.0, 22.0)
	var dist := randf_range(300.0, 2600.0)
	if _flash == null:
		_flash = DirectionalLight3D.new()
		_flash.light_color = Color(0.82, 0.86, 1.0)
		_flash.shadow_enabled = false
		add_child(_flash)
	_flash.rotation_degrees = Vector3(randf_range(-70, -40), randf_range(0, 360), 0)
	var peak := clampf(2600.0 / dist, 0.6, 4.0)
	var tw := create_tween()
	_flash.light_energy = 0.0
	tw.tween_property(_flash, "light_energy", peak, 0.04)
	tw.tween_property(_flash, "light_energy", peak * 0.2, 0.08)
	tw.tween_property(_flash, "light_energy", peak * 0.9, 0.05)
	tw.tween_property(_flash, "light_energy", 0.0, 0.35)
	var clip := "res://assets/audio/synth/%s.ogg" % ("thunder_near_%d" % (randi() % 2 + 1) if dist < 1100.0 else "thunder_far_1")
	get_tree().create_timer(dist / 340.0).timeout.connect(func():
		if ResourceLoader.exists(clip):
			var p := AudioStreamPlayer.new()
			p.stream = load(clip)
			p.bus = "Ambience" if AudioServer.get_bus_index("Ambience") != -1 else "Master"
			p.volume_db = lerpf(-2.0, -12.0, clampf(dist / 2600.0, 0.0, 1.0))
			add_child(p)
			p.play()
			p.finished.connect(p.queue_free))
	log.append({"lightning": int(dist), "clock": WorldState.clock_text()})


## The first drops: one of them says so (now and then, not every shower).
func _first_drops() -> void:
	if randf() > 0.6 or main.get("voice") == null:
		return
	var who := "mika" if randf() < 0.6 or not main.characters.has("luna") else "luna"
	var c: Node3D = main.characters.get(who)
	if c == null or not c.visible:
		return
	var lines := {"mika": ["Oh - it's starting to rain!", "Rain! Of course it's raining.", "Feel that? Rain."],
		"luna": ["Rain. We should find some cover.", "Here it comes.", "The sky's opening up."]}
	var pool: Array = lines[who]
	main.voice.say(who, String(pool[randi() % pool.size()]), {"max_wait": 2.0, "mood": "surprised" if who == "mika" else "neutral"})
	if c.get("face") and c.face:
		c.face.pulse("surprised", 0.5, 0.6)
	if c.has_method("look_head_at"):
		c.look_head_at(c.global_position + Vector3(0, 6.0, 0) - c.global_transform.basis.z * 2.0)
		get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(c): c.look_head_at(null))


func describe() -> Dictionary:
	return {"kind": kind(), "cloud": snappedf(cloud, 0.01), "rain": snappedf(rain, 0.01), "until": WorldState.weather.get("until", 0), "sheltered": sheltered_area()}
