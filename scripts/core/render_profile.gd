extends Node
## Global render-quality profile + command-line options.
##
## Usage (user args go after `--`):
##   godot --path . -- --profile=cinematic|live|ultra --night --tour --bench=20
##        --bridge-port=47651 --no-bridge --mock-commands=res://tests/mock_commands.json
##
## CINEMATIC       : best quality this Intel iGPU handles interactively.
## LIVE_OPTIMIZED  : attractive but light; meant to run beside OBS + the live Three.js stream.
## ULTRA           : CINEMATIC plus SDFGI / higher shadow + volumetric quality for stronger GPUs.

signal profile_changed(profile: String)

const CINEMATIC := "CINEMATIC"
const LIVE_OPTIMIZED := "LIVE_OPTIMIZED"
const ULTRA := "ULTRA"

var profile := CINEMATIC
var night := false
var tour := false
var bench_seconds := 0.0
var bridge_port := 47651
var bridge_enabled := true
var mock_commands := ""
var shots_dir := "res://screenshots"
var options := {}

const SETTINGS := {
	CINEMATIC: {
		"scale_3d": 1.0, "fsr": false, "taa": true, "fxaa": false, "msaa": Viewport.MSAA_DISABLED,
		"ssao": true, "ssil": true, "ssr": true, "sdfgi": false, "glow": true,
		"volumetric_fog": true, "fog_density": 0.0035, "shadow_size": 4096, "shadow_distance": 45.0,
		"foliage_density": 1.0, "magic_shadows": true, "max_fps": 60, "lod_threshold": 1.0,
	},
	LIVE_OPTIMIZED: {
		"scale_3d": 0.75, "fsr": true, "taa": false, "fxaa": true, "msaa": Viewport.MSAA_DISABLED,
		"ssao": true, "ssil": false, "ssr": false, "sdfgi": false, "glow": true,
		"volumetric_fog": false, "fog_density": 0.0, "shadow_size": 2048, "shadow_distance": 40.0,
		"foliage_density": 0.55, "magic_shadows": false, "max_fps": 30, "lod_threshold": 2.0,
	},
	ULTRA: {
		"scale_3d": 1.0, "fsr": false, "taa": true, "fxaa": false, "msaa": Viewport.MSAA_2X,
		"ssao": true, "ssil": true, "ssr": true, "sdfgi": true, "glow": true,
		"volumetric_fog": true, "fog_density": 0.004, "shadow_size": 8192, "shadow_distance": 110.0,
		"foliage_density": 1.4, "magic_shadows": true, "max_fps": 0, "lod_threshold": 0.5,
	},
}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		options[kv[0]] = kv[1] if kv.size() > 1 else "true"
	match String(options.get("profile", "cinematic")).to_lower():
		"live", "live_optimized", "live-optimized": profile = LIVE_OPTIMIZED
		"ultra": profile = ULTRA
		_: profile = CINEMATIC
	night = options.has("night")
	tour = options.has("tour")
	bench_seconds = float(options.get("bench", "0"))
	bridge_port = int(options.get("bridge-port", "47651"))
	bridge_enabled = not options.has("no-bridge")
	mock_commands = String(options.get("mock-commands", ""))
	shots_dir = String(options.get("shots-dir", "res://screenshots"))


func get_setting(key: String) -> Variant:
	if key == "scale_3d" and options.has("scale"):
		return float(options["scale"])
	return SETTINGS[profile][key]


func is_compatibility_renderer() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


func set_profile(p: String) -> void:
	profile = p
	apply_to_viewport(get_viewport())
	profile_changed.emit(profile)


func cycle_profile() -> void:
	var order := [CINEMATIC, LIVE_OPTIMIZED, ULTRA]
	set_profile(order[(order.find(profile) + 1) % order.size()])


func apply_to_viewport(vp: Viewport) -> void:
	var s: Dictionary = SETTINGS[profile]
	vp.scaling_3d_scale = get_setting("scale_3d")
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s.fsr else Viewport.SCALING_3D_MODE_BILINEAR
	vp.use_taa = s.taa and not is_compatibility_renderer()
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if s.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.msaa_3d = s.msaa
	vp.mesh_lod_threshold = s.lod_threshold
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X
	RenderingServer.directional_shadow_atlas_set_size(s.shadow_size, true)
	Engine.max_fps = s.max_fps


func apply_to_environment(env: Environment) -> void:
	var s: Dictionary = SETTINGS[profile]
	var compat := is_compatibility_renderer()
	env.ssao_enabled = s.ssao and not compat
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssil_enabled = s.ssil and not compat
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.ssr_enabled = s.ssr and not compat
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.sdfgi_enabled = s.sdfgi and not compat
	env.glow_enabled = s.glow
	env.volumetric_fog_enabled = s.volumetric_fog and not compat
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = s.fog_density
	RenderingServer.environment_set_ssao_quality(
		RenderingServer.ENV_SSAO_QUALITY_HIGH if profile == ULTRA else (RenderingServer.ENV_SSAO_QUALITY_MEDIUM if profile == CINEMATIC else RenderingServer.ENV_SSAO_QUALITY_LOW),
		profile != ULTRA, 0.5, 2, 50, 300)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_LOW if profile != ULTRA else RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 2, 50, 300)
	RenderingServer.environment_set_volumetric_fog_volume_size(64 if profile == CINEMATIC else 128, 64 if profile == CINEMATIC else 128)
