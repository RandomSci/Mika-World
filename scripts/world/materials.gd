class_name SanctuaryMaterials
extends RefCounted
## Builds the shared PBR materials once (photogrammetry textures from Poly Haven / ambientCG).

const PH := "res://assets/polyhaven/textures/"
const MOSS := "res://assets/ambientcg/Moss002/Moss002_1K-JPG_"

var noise_tex: NoiseTexture2D
var stone: ShaderMaterial        # cut stone: columns, arch, walls, altar
var stone_slab: ShaderMaterial   # dais slabs: same stone, cleaner, less moss
var rune_floor: ShaderMaterial
var terrain: ShaderMaterial
var grass: ShaderMaterial
var gold: StandardMaterial3D
var crystal: StandardMaterial3D


func _init() -> void:
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.seamless = true
	noise_tex.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.012
	fn.fractal_octaves = 5
	noise_tex.noise = fn

	stone = _stone_material("mossy_rock", "2k", 0.38, 0.4)
	stone_slab = _stone_material("mossy_rock", "2k", 0.3, 0.12)
	stone_slab.set_shader_parameter("stone_tint", Color(1.0, 0.98, 0.95))
	stone_slab.set_shader_parameter("tint_variation", 0.24)

	rune_floor = ShaderMaterial.new()
	rune_floor.shader = load("res://shaders/rune_floor.gdshader")
	var f := PH + "monastery_stone_floor/monastery_stone_floor_"
	rune_floor.set_shader_parameter("floor_albedo", load(f + "diff_2k.jpg"))
	rune_floor.set_shader_parameter("floor_normal", load(f + "nor_gl_2k.jpg"))
	rune_floor.set_shader_parameter("floor_rough", load(f + "rough_2k.jpg"))
	rune_floor.set_shader_parameter("floor_ao", load(f + "ao_2k.jpg"))
	rune_floor.set_shader_parameter("moss_albedo", load(MOSS + "Color.jpg"))
	rune_floor.set_shader_parameter("breakup_noise", noise_tex)

	terrain = ShaderMaterial.new()
	terrain.shader = load("res://shaders/terrain_blend.gdshader")
	var g := PH + "leafy_grass/leafy_grass_"
	var l := PH + "forrest_ground_01/forrest_ground_01_"
	var p := PH + "stony_dirt_path/stony_dirt_path_"
	terrain.set_shader_parameter("grass_albedo", load(g + "diff_2k.jpg"))
	terrain.set_shader_parameter("grass_normal", load(g + "nor_gl_2k.jpg"))
	terrain.set_shader_parameter("grass_rough", load(g + "rough_2k.jpg"))
	terrain.set_shader_parameter("grass_height", load(g + "disp_2k.png"))
	terrain.set_shader_parameter("grass2_albedo", load(PH + "sparse_grass/sparse_grass_diff_1k.jpg"))
	terrain.set_shader_parameter("leaves_albedo", load(l + "diff_1k.jpg"))
	terrain.set_shader_parameter("leaves_normal", load(l + "nor_gl_1k.jpg"))
	terrain.set_shader_parameter("leaves_rough", load(l + "rough_1k.jpg"))
	terrain.set_shader_parameter("leaves_height", load(l + "disp_1k.png"))
	terrain.set_shader_parameter("path_albedo", load(p + "diff_1k.jpg"))
	terrain.set_shader_parameter("path_normal", load(p + "nor_gl_1k.jpg"))
	terrain.set_shader_parameter("path_rough", load(p + "rough_1k.jpg"))
	terrain.set_shader_parameter("path_height", load(p + "disp_1k.png"))
	terrain.set_shader_parameter("breakup_noise", noise_tex)

	grass = ShaderMaterial.new()
	grass.shader = load("res://shaders/grass_blades.gdshader")
	grass.set_shader_parameter("breakup_noise", noise_tex)

	gold = StandardMaterial3D.new()
	gold.albedo_color = Color(0.83, 0.64, 0.33)
	gold.metallic = 1.0
	gold.roughness = 0.32
	gold.roughness_texture = load(PH + "mossy_rock/mossy_rock_rough_2k.jpg")
	gold.uv1_triplanar = true
	gold.uv1_world_triplanar = true
	gold.uv1_scale = Vector3.ONE * 1.5

	crystal = StandardMaterial3D.new()
	crystal.albedo_color = Color(0.55, 0.75, 1.0, 0.55)
	crystal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crystal.metallic_specular = 0.9
	crystal.roughness = 0.05
	crystal.emission_enabled = true
	crystal.emission = Color(0.35, 0.6, 1.0)
	crystal.emission_energy_multiplier = 3.0
	crystal.rim_enabled = true
	crystal.rim = 0.8
	crystal.rim_tint = 0.6


func _stone_material(tex: String, res: String, tiling: float, moss: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/stone_triplanar.gdshader")
	var b := PH + tex + "/" + tex + "_"
	m.set_shader_parameter("stone_albedo", load(b + "diff_%s.jpg" % res))
	m.set_shader_parameter("stone_normal", load(b + "nor_gl_%s.jpg" % res))
	m.set_shader_parameter("stone_rough", load(b + "rough_%s.jpg" % res))
	m.set_shader_parameter("stone_ao", load(b + "ao_%s.jpg" % res))
	m.set_shader_parameter("moss_albedo", load(MOSS + "Color.jpg"))
	m.set_shader_parameter("moss_normal", load(MOSS + "NormalGL.jpg"))
	m.set_shader_parameter("breakup_noise", noise_tex)
	m.set_shader_parameter("tiling", tiling)
	m.set_shader_parameter("moss_amount", moss)
	return m


## Every material that should pick up the spell's magical bounce light.
func magic_receivers() -> Array[ShaderMaterial]:
	return [stone, stone_slab]
