class_name PortalFX
extends Node3D
## Region-specific travel effect around the traveller, played as the travel mask closes (departure) and
## again when the next area appears (arrival). Cheap: shared FX materials, two quads and one particle
## system, ~1.6 s, frees itself. Visual identities (original):
##   arcane_sanctuary    - concentric blue rune circles turning in opposite directions
##   enchanted_forest    - green leaf motes spiralling up through wind arcs
##   fantasy_village     - warm lantern-gold motes rising, a soft hearth ring
##   crystal_caverns     - violet crystalline facets (hexagonal sigil) and sharp shards
##   celestial_highlands - star points and a pale five-pointed celestial sign
##   grand_academy       - refined golden geometry (square-in-octagon sigils)

const STYLES := {
	"arcane_sanctuary": {"color": Color(0.42, 0.66, 1.0), "accent": Color(0.74, 0.46, 1.0), "sides": [8, 12], "shader": "sigil", "motes": "arcane"},
	"enchanted_forest": {"color": Color(0.45, 0.95, 0.5), "accent": Color(0.85, 1.0, 0.6), "sides": [3, 5], "shader": "wind_arcs", "motes": "wind"},
	"fantasy_village": {"color": Color(1.0, 0.75, 0.4), "accent": Color(1.0, 0.9, 0.6), "sides": [6, 6], "shader": "water_rings", "motes": "fire"},
	"crystal_caverns": {"color": Color(0.7, 0.45, 1.0), "accent": Color(0.55, 0.85, 1.0), "sides": [6, 6], "shader": "sigil", "motes": "arcane"},
	"celestial_highlands": {"color": Color(0.92, 0.95, 1.0), "accent": Color(1.0, 0.92, 0.6), "sides": [5, 10], "shader": "sigil", "motes": "self"},
	"grand_academy": {"color": Color(1.0, 0.82, 0.4), "accent": Color(1.0, 0.95, 0.75), "sides": [4, 8], "shader": "sigil", "motes": "self"},
}

var region := "arcane_sanctuary"
var t := 0.0
var life := 1.6
var arriving := false
var _rings: Array[MeshInstance3D] = []
var _light: OmniLight3D


static func play(parent: Node, at: Vector3, p_region: String, p_arriving: bool) -> PortalFX:
	var fx := PortalFX.new()
	fx.region = p_region if STYLES.has(p_region) else "arcane_sanctuary"
	fx.arriving = p_arriving
	parent.add_child(fx)
	fx.global_position = at
	fx._build()
	MagicEvents.emit_phase(null, "portal", "arrive" if p_arriving else "depart", fx.region, at)
	return fx


func _build() -> void:
	var st: Dictionary = STYLES[region]
	var sh: String = st.shader
	for i in 2:
		var params := {"color": st.color if i == 0 else st.accent, "intensity": 0.0, "draw_progress": 0.0}
		match sh:
			"sigil":
				params["sides"] = st.sides[i]
				params["spin"] = 0.6 if i == 0 else -0.9
				params["seed"] = 7.0 + i
			"wind_arcs":
				params["arcs"] = 3 + i
				params["spin"] = 2.0 + i
			"water_rings":
				params["rings"] = 3 + i
		var q := FX.quad("res://shaders/magic/%s.gdshader" % sh, 2.6 - 0.8 * i, params)
		q.position.y = 0.05 + i * 1.0
		add_child(q)
		_rings.append(q)
	var motes := FX.particles(70, 1.2, FX.pm_motes(st.motes, "rise"), FX.mote_mesh(0.06))
	motes.position.y = 0.05
	add_child(motes)
	motes.emitting = true
	_light = FX.light(st.color, 0.0, 5.0)
	_light.position.y = 1.2
	add_child(_light)


func _process(delta: float) -> void:
	t += delta
	var k := clampf(t / 0.45, 0.0, 1.0)
	var fade := 1.0 - clampf((t - life + 0.5) / 0.5, 0.0, 1.0)
	for i in _rings.size():
		var m: ShaderMaterial = _rings[i].material_override
		m.set_shader_parameter("draw_progress", smoothstep(0.0, 1.0, k))
		m.set_shader_parameter("intensity", 2.2 * k * fade)
		_rings[i].position.y = 0.05 + (1.0 + 0.5 * k) * i * (1.0 if arriving else 1.2)
	_light.light_energy = 2.0 * k * fade * float(RenderProfile.get_setting("magic_light_scale"))
	if t > life:
		queue_free()
