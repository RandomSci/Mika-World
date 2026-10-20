class_name DayNightCycle
extends Node
## The night LOOK follows the game clock (Day 2; before, it was only a profile flag or the N key, so a "night" by
## the clock could look like day). Dusk 18:00-20:00 and dawn 05:00-07:00 (WorldState.daylight) blend smoothly:
##   sky       the area's day panorama crossfades into its starry night panorama (day_night_blend.gdshader)
##   light     sun colour / energy / angle, ambient, exposure, fog, colour grade - read from the area's OWN day and
##             night settings (its set_night(false/true)) and interpolated, so every area keeps its look
##   lights    lanterns, window glows, night-only nodes fade in from early dusk; day-only nodes go at mid-dusk
##   flags     WorldState.night (gameplay: creatures, fireflies, stargazing, music) turns at the dusk midpoint
## The N key / RenderProfile night / the bridge's "night" request are TEST OVERRIDES only (override = 0 or 1);
## `clear_override()` hands it back to the clock.

const ENV_PROPS := ["background_energy_multiplier", "ambient_light_energy", "ambient_light_sky_contribution", "ambient_light_color",
	"tonemap_exposure", "fog_light_color", "fog_density", "fog_height_density", "fog_sky_affect", "fog_sun_scatter",
	"adjustment_saturation", "adjustment_contrast", "volumetric_fog_albedo", "volumetric_fog_density"]
const BLEND := preload("res://shaders/sky/day_night_blend.gdshader")
const STEP_S := 0.0                # every frame (2026-10-19: steps of 0.2 s, and a second cycle writing the sun every
                                   # 0.5 s, made the sun and the light jump - Selwyn: "every transition smooth")

static var instance: DayNightCycle

var main: Node
var area: Node
var override := -1               # -1 the clock decides; 0 forced day; 1 forced night (tests, the N key)
var k := -1.0                    # the applied night amount 0..1
var _day := {}
var _night := {}
var _blend_sky: Sky
var _blend_mat: ShaderMaterial
var _night_mix_mat: ShaderMaterial    # a shader night sky that blends the day panorama in itself
var _sky_k := -1.0
var _acc := 0.0
var _lights := {}                # Light3D -> base energy (night-only nodes)


func setup(m: Node) -> void:
	main = m
	instance = self
	name = "DayNightCycle"


static func clock_k() -> float:
	return 1.0 - WorldState.daylight()


func target_k() -> float:
	return float(override) if override >= 0 else clock_k()


func set_override(night: bool) -> void:
	override = 1 if night else 0


func clear_override() -> void:
	override = -1


func _process(delta: float) -> void:
	if get_tree().get_first_node_in_group("env_owner") != null:
		return                                    # (a scene owns the look now - the lake dance's night stage)
	_acc += delta
	if _acc < STEP_S:
		return
	var dt := _acc
	_acc = 0.0
	var w = main.get("world")
	if w == null or not is_instance_valid(w) or w.get("env") == null or w.get("sun") == null:
		return
	if w != area:
		_capture(w)
	var t := target_k()
	# the clock moves slowly (dusk ~4 real minutes); a jump (a test setting the time, an override, a load) eases over ~3 s
	var nk: float = t if k < 0.0 else move_toward(k, t, maxf(dt / 3.0, 0.0005))
	apply(nk)                          # every frame: the sun and moon move continuously with the clock


## Reads the area's own day and night settings once (its set_night does the work), then blends between them.
func _capture(w: Node) -> void:
	area = w
	_lights.clear()
	var was: bool = bool(w.get("night"))
	w.set_night(false)
	_day = _read(w)
	w.set_night(true)
	_night = _read(w)
	w.set_night(was)
	_blend_sky = null
	_blend_mat = null
	_night_mix_mat = null
	var ds: Sky = _day.get("sky")
	var ns: Sky = _night.get("sky")
	# a night sky that is its own shader (Starfall's Milky Way) crossfades the day panorama itself (uniform mixk)
	if ds and ns and ds != ns and ds.sky_material is PanoramaSkyMaterial and ns.sky_material is ShaderMaterial:
		var sm := ns.sky_material as ShaderMaterial
		for u in sm.shader.get_shader_uniform_list():
			if String(u.name) == "mixk":
				_night_mix_mat = sm
				sm.set_shader_parameter("day_pano", (ds.sky_material as PanoramaSkyMaterial).panorama)
				sm.set_shader_parameter("day_energy", (ds.sky_material as PanoramaSkyMaterial).energy_multiplier)
	if ds and ns and ds != ns and ds.sky_material is PanoramaSkyMaterial and ns.sky_material is PanoramaSkyMaterial:
		_blend_mat = ShaderMaterial.new()
		_blend_mat.shader = BLEND
		_blend_mat.set_shader_parameter("day_pano", (ds.sky_material as PanoramaSkyMaterial).panorama)
		_blend_mat.set_shader_parameter("night_pano", (ns.sky_material as PanoramaSkyMaterial).panorama)
		_blend_mat.set_shader_parameter("day_energy", (ds.sky_material as PanoramaSkyMaterial).energy_multiplier)
		_blend_mat.set_shader_parameter("night_energy", (ns.sky_material as PanoramaSkyMaterial).energy_multiplier)
		_blend_sky = Sky.new()
		_blend_sky.sky_material = _blend_mat
		_blend_sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL      # the sky's lighting re-filters over a few frames, no pop
		_blend_sky.radiance_size = ds.radiance_size
	k = -1.0
	_sky_k = -1.0


func _read(w: Node) -> Dictionary:
	var env: Environment = w.env
	var sun: DirectionalLight3D = w.sun
	var d := {"sky": env.sky, "sun_color": sun.light_color, "sun_energy": sun.light_energy if sun.visible else 0.0,
		"sun_q": sun.global_transform.basis.get_rotation_quaternion() if sun.is_inside_tree() else Quaternion.from_euler(sun.rotation)}
	for p in ENV_PROPS:
		d[p] = env.get(p)
	return d


func _lerp(a, b, t: float):
	if a is Color:
		return (a as Color).lerp(b, t)
	if a is float or a is int:
		return lerpf(float(a), float(b), t)
	return b if t >= 0.5 else a


func apply(nk: float) -> void:
	k = clampf(nk, 0.0, 1.0)
	var w: Node = area
	if w == null or not is_instance_valid(w) or _day.is_empty():
		return
	# gameplay night flag and the area's discrete switches at the dusk midpoint (with a little hysteresis)
	var want := WorldState.night
	if k >= 0.55:
		want = true
	elif k <= 0.45:
		want = false
	if want != WorldState.night or bool(w.get("night")) != want:
		WorldState.night = want
		w.set_night(want)                      # (its nodes, fireflies, shafts, expansion; the light is blended below)
	var env: Environment = w.env
	var sun: DirectionalLight3D = w.sun
	var e := smoothstep(0.0, 1.0, k)
	for p in ENV_PROPS:
		if _day.has(p) and _night.has(p) and _day[p] != null and _night[p] != null:
			env.set(p, _lerp(_day[p], _night[p], e))
	sun.light_color = (_day.sun_color as Color).lerp(_night.sun_color, e)
	sun.light_energy = lerpf(float(_day.sun_energy), float(_night.sun_energy), e)
	if sun.is_inside_tree():
		if override >= 0 or RenderProfile.options.has("fixed-sun"):
			# a test override: the area's own day / night sun
			var q: Quaternion = (_day.sun_q as Quaternion).slerp(_night.sun_q, e)
			sun.global_transform = Transform3D(Basis(q), sun.global_transform.origin)
		else:
			_sky_bodies(sun)
	sun.visible = sun.light_energy > 0.001
	# the sky
	if k <= 0.002:
		env.sky = _day.sky
		_sky_k = 0.0
	elif k >= 0.998:
		env.sky = _night.sky
		if _night_mix_mat and _sky_k != 1.0:
			_night_mix_mat.set_shader_parameter("mixk", 1.0)
		_sky_k = 1.0
	elif _night_mix_mat:
		if env.sky != _night.sky:
			env.sky = _night.sky
		if absf(k - _sky_k) > 0.006:
			_night_mix_mat.set_shader_parameter("mixk", k)
			_sky_k = k
	elif _blend_sky:
		if env.sky != _blend_sky:
			env.sky = _blend_sky
		if absf(k - _sky_k) > 0.006:          # (each change re-filters the sky's radiance: not every frame)
			_blend_mat.set_shader_parameter("mixk", k)
			_sky_k = k
	else:
		env.sky = _night.sky if k >= 0.5 else _day.sky
	# lanterns and night-only nodes: lit from early dusk, brightening into the night
	var r := smoothstep(0.25, 0.8, k)
	var nodes: Array = w.get_tree().get_nodes_in_group("night_lights_" + str(w.get_instance_id()))
	var extra = w.get("_night_nodes")
	if extra is Array:
		nodes.append_array(extra)
	for n in nodes:
		if not is_instance_valid(n):
			continue
		(n as Node3D).visible = k >= 0.25
		for l in ([n] if n is Light3D else []) + (n as Node).find_children("*", "Light3D", true, false):
			if not _lights.has(l):
				_lights[l] = (l as Light3D).light_energy
			(l as Light3D).light_energy = float(_lights[l]) * r
	for n in w.get_tree().get_nodes_in_group("day_only_" + str(w.get_instance_id())):
		(n as Node3D).visible = k < 0.5
	if w.has_method("night_blend"):
		w.night_blend(k)


## The sun and the moon cross the sky with the clock, every frame: the sun rises in the east at 06:00, stands at
## ~58 deg at noon and sets in the west at 18:00; the moon rises at 18:00 and sets at 06:00 on the same arc. The one
## directional light follows whichever is higher; its energy fades to nothing as a body nears the horizon (so the
## hand-over at dusk / dawn happens in the dark, no visible jump); a low sun is warmer.
func _sky_bodies(sun: DirectionalLight3D) -> void:
	var h := WorldState.hour_f()
	var ts := (h - 6.0) / 12.0                         # 0..1 over the day
	var tm := fposmod(h - 18.0, 24.0) / 12.0           # 0..1 over the night
	var sun_el := 58.0 * sin(PI * ts)
	var moon_el := 46.0 * sin(PI * tm)
	var use_sun := sun_el >= moon_el
	var el := sun_el if use_sun else moon_el
	var az := lerpf(-100.0, 100.0, clampf(ts if use_sun else tm, 0.0, 1.0)) + (0.0 if use_sun else 180.0)
	sun.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-maxf(el, 2.0)), deg_to_rad(az), 0.0)), sun.global_transform.origin)
	var horizon := smoothstep(-1.0, 14.0, el)            # nothing at the horizon, full from ~14 deg
	if use_sun:
		# sunlight only (the area's day sun), warmer when low
		var low := 1.0 - smoothstep(8.0, 35.0, el)
		sun.light_color = (_day.sun_color as Color).lerp(Color(1.0, 0.68, 0.45), low * 0.7)
		sun.light_energy = float(_day.sun_energy) * horizon
	else:
		# moonlight only (the area's night sun)
		sun.light_color = _night.sun_color
		sun.light_energy = float(_night.sun_energy) * horizon


func describe() -> Dictionary:
	return {"k": snappedf(k, 0.01), "target": snappedf(target_k(), 0.01), "override": override, "night_flag": WorldState.night,
		"clock": WorldState.clock_text(), "blend_sky": _blend_sky != null}
