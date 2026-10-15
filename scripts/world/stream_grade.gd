class_name StreamGrade
extends Node
## One consistent look over every area (Part 5 look pass): a warm, gently saturated anime palette, soft fog that
## starts further out, and bloom that never blows out (bright spell cores are capped). The areas, the day cycle and
## the weather keep setting their own values (the fog goes through the weather's own factor, fog_factor()); this applies its grade ON TOP of whatever they set last, without ever
## compounding (a value it wrote itself is left alone until someone else changes it). --no-grade turns it off.

const SATURATION := 1.07          # x the area's own
const CONTRAST := 1.02
const FOG := 0.72                 # x the area's fog density (the haze starts further away)
const VOL_FOG := 0.8
const GLOW_CAP := 3.2             # HDR luminance that still blooms (spell cores are far brighter)
const GLOW_MAX := 0.6             # glow intensity ceiling

var main: Node
var _mine := {}                   # env instance id -> {property: value this wrote}
var _lut: GradientTexture1D


func setup(m: Node) -> void:
	main = m
	process_priority = 1000       # after the day cycle, weather and the areas
	_lut = _warm_curve()


## Per-channel curves (Environment.adjustment_color_correction, a 1D texture: R, G and B each through their own
## channel): shadows a touch warm, highlights creamy, blues held slightly back.
static func _warm_curve() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.012, 0.008, 0.02), Color(0.262, 0.243, 0.232), Color(0.515, 0.497, 0.475),
		Color(0.765, 0.752, 0.722), Color(1.0, 0.99, 0.95)])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	t.use_hdr = false
	return t


func _process(_d: float) -> void:
	var a = main.world if main else null
	if a == null or not ("env" in a) or a.env == null:
		return
	var env: Environment = a.env
	var mine: Dictionary = _mine.get_or_add(env.get_instance_id(), {})
	_scale(env, mine, "adjustment_saturation", SATURATION)
	_scale(env, mine, "adjustment_contrast", CONTRAST)
	if env.volumetric_fog_enabled:
		_scale(env, mine, "volumetric_fog_density", VOL_FOG)
	env.adjustment_enabled = true
	if env.adjustment_color_correction != _lut:
		env.adjustment_color_correction = _lut
	env.glow_hdr_luminance_cap = GLOW_CAP
	if env.glow_intensity > GLOW_MAX:
		env.glow_intensity = GLOW_MAX


## The fog factor the weather rides on (it owns fog_density's per-frame rewrite; scaling it here as well would
## compound). 1.0 with --no-grade.
static func fog_factor() -> float:
	return 1.0 if RenderProfile.options.has("no-grade") else FOG


func _scale(env: Environment, mine: Dictionary, prop: String, k: float) -> void:
	var cur: float = env.get(prop)
	if mine.has(prop) and is_equal_approx(cur, float(mine[prop])):
		return                    # still the value this wrote: nobody changed it since
	var v := cur * k
	env.set(prop, v)
	mine[prop] = env.get(prop)
