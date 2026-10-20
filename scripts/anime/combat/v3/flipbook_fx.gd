class_name FlipbookFX
extends Node3D
## One video flipbook effect (Selwyn's FX_Video_Test_v1, 2026-10-20, now the main look of spells; particles are extra
## layers): a camera facing card playing an 8x8 sheet (shaders/magic/flipbook_fx), following a point (her hand, the
## other girl), with one OmniLight3D in the effect's own colour whose strength follows the frame's measured brightness
## (assets/vfx/flipbook/flipbook_light.json), so the ground and the girls are lit by it.
##   FlipbookFX.play(host, "mika_petal_burst", at_fn, {size, f0, f1, dur, ...})
## opts: size (m, 2 to 4), f0 f1 (the frames to play), dur (s), fade_in fade_out (s), intensity, black_cut, upright
## (a pillar: turns round the vertical only, its bottom edge on `at`), roll (radians in the card's plane), roll_fn
## (Callable -> roll, read every frame), light (energy at the brightest frame), light_range, hold_end (s to stay on f1).

const SHEETS := {
	"mika_petal_vortex": "res://assets/vfx/flipbook/mika_petal_vortex_8x8.webp",
	"mika_petal_burst": "res://assets/vfx/flipbook/mika_petal_burst_8x8.webp",
	"luna_crescent_slash": "res://assets/vfx/flipbook/luna_crescent_slash_8x8.webp",
	"luna_moon_pillar": "res://assets/vfx/flipbook/luna_moon_pillar_8x8.webp",
	# FX_Cinematic_v1 (Selwyn, 20 October)
	"fx_impact_starburst": "res://assets/vfx/flipbook/fx_impact_starburst_8x8.webp",
	"mika_halo_sigil": "res://assets/vfx/flipbook/mika_halo_sigil_8x8.webp",
	"luna_halo_sigil": "res://assets/vfx/flipbook/luna_halo_sigil_8x8.webp",
	"fx_blade_ring": "res://assets/vfx/flipbook/fx_blade_ring_8x8.webp",
	"fx_ghost_slash": "res://assets/vfx/flipbook/fx_ghost_slash_8x8.webp",
	"mika_petal_rain": "res://assets/vfx/flipbook/mika_petal_rain_8x8.webp",
}
static var _light_data := {}
static var _tex := {}
static var on := true                       # (--no-fx-cards renders the particle look alone, for the before side)

var fx := ""
var card: MeshInstance3D
var mat: ShaderMaterial
var light: OmniLight3D
var at_fn: Callable
var o := {}
var t := 0.0
var _frames: Array = []
var _peak := 1.0
var stopped := false


static func enabled() -> bool:
	return on and not RenderProfile.options.has("no-fx-cards")


static func play(host: Node, name: String, at: Callable, opts := {}) -> FlipbookFX:
	if not enabled() or not SHEETS.has(name):
		return null
	var f := FlipbookFX.new()
	f.fx = name
	f.name = "FX_" + name
	f.at_fn = at
	f.o = opts
	f.top_level = true
	host.add_child(f)
	f._build()
	return f


static func _light_of(name: String) -> Dictionary:
	if _light_data.is_empty():
		var fa := FileAccess.open("res://assets/vfx/flipbook/flipbook_light.json", FileAccess.READ)
		if fa:
			_light_data = JSON.parse_string(fa.get_as_text())
	return _light_data.get(name, {})


func _build() -> void:
	if not _tex.has(fx):
		_tex[fx] = load(SHEETS[fx])
	var size := float(o.get("size", 3.0))
	card = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	if bool(o.get("upright", false)):
		q.center_offset = Vector3(0, size * 0.5 - float(o.get("sink", 0.12)) * size, 0)
	card.mesh = q
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/magic/flipbook_fx.gdshader")
	mat.set_shader_parameter("sheet", _tex[fx])
	mat.set_shader_parameter("intensity", float(o.get("intensity", 2.2)))
	mat.set_shader_parameter("black_cut", float(o.get("black_cut", 0.14)))
	mat.set_shader_parameter("upright", 2.0 if bool(o.get("flat", false)) else (1.0 if bool(o.get("upright", false)) else 0.0))
	mat.set_shader_parameter("roll", float(o.get("roll", 0.0)))
	mat.set_shader_parameter("fade", 0.0)
	mat.set_shader_parameter("top_fade", float(o.get("top_fade", 0.0)))
	mat.set_shader_parameter("near_fade", float(o.get("near", 0.0 if bool(o.get("flat", false)) else size * 0.9)))
	mat.set_shader_parameter("soft_depth", float(o.get("soft_depth", 0.02 if bool(o.get("flat", false)) else 0.6)))
	mat.set_shader_parameter("edge_mask", float(o.get("edge_mask", 0.47)))
	card.material_override = mat
	# (a card is drawn after the bodies' transparent pass order does not matter for additive light)
	card.extra_cull_margin = size
	add_child(card)
	var ld := _light_of(fx)
	_frames = ld.get("frames", [])
	_peak = maxf(float(ld.get("peak_lum", 0.4)), 0.05)
	light = OmniLight3D.new()
	light.omni_range = float(o.get("light_range", size * 1.6))
	light.omni_attenuation = 1.4
	light.light_energy = 0.0
	light.light_specular = 0.2
	light.shadow_enabled = false
	add_child(light)
	_place()


func _place() -> void:
	var p: Vector3 = at_fn.call()
	if p.is_finite():
		global_position = p
		if bool(o.get("flat", false)):
			# lying on the ground, turning slowly (the card's +Z up, so its face looks at the sky)
			global_basis = Basis(Vector3.UP, t * float(o.get("turn", 0.25))) * Basis(Vector3.RIGHT, -PI * 0.5)
		light.global_position = p + Vector3.UP * (float(o.get("size", 3.0)) * 0.35 if bool(o.get("upright", false)) else 0.0)


## Ends early: fades out over `dur` from where it is.
func stop(dur := 0.15) -> void:
	if stopped:
		return
	stopped = true
	o.fade_out = dur
	o.dur = t + dur
	o.hold_end = 0.0


func _process(delta: float) -> void:
	t += delta
	_place()
	var dur := maxf(float(o.get("dur", 2.0)), 0.05)
	var u := clampf(t / dur, 0.0, 1.0)
	var f0 := float(o.get("f0", 0.0))
	var f1 := float(o.get("f1", 63.0))
	var fr := lerpf(f0, f1, u) if not stopped else float(mat.get_shader_parameter("frame"))
	mat.set_shader_parameter("frame", fr)
	if o.has("roll_fn"):
		mat.set_shader_parameter("roll", float((o.roll_fn as Callable).call()))
	var fi := float(o.get("fade_in", 0.08))
	var fo := float(o.get("fade_out", 0.25))
	var hold := float(o.get("hold_end", 0.0))
	var fade := clampf(t / maxf(fi, 0.001), 0.0, 1.0) * clampf((dur + hold - t) / maxf(fo, 0.001), 0.0, 1.0)
	mat.set_shader_parameter("fade", fade)
	# her light: the frame's brightness against the sheet's brightest, in the frame's own colour
	if not _frames.is_empty():
		var fd: Dictionary = _frames[clampi(int(fr), 0, _frames.size() - 1)]
		var rgb: Array = fd.get("rgb", [1, 0.6, 0.8])
		var col := Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
		var mx := maxf(col.r, maxf(col.g, col.b))
		if mx > 0.01:
			light.light_color = Color(col.r / mx, col.g / mx, col.b / mx)
		light.light_energy = float(o.get("light", 3.0)) * clampf(float(fd.get("lum", 0.0)) / _peak, 0.0, 1.0) * fade
	if t >= dur + hold:
		queue_free()
