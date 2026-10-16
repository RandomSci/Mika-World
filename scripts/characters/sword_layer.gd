class_name SwordLayer
extends Node
## Optional magical-sword animation layer for a WorldCharacter (separate from casting/locomotion).
## * Own AnimationLibrary "sw" built from selected, measured Mixamo Great Sword clips (retargeted the
##   same way as the base clips; raw FBX files stay git-ignored).
## * Drawn stance swaps the locomotion blend-space clips; attacks use the character's one-shot slot.
## * An original procedural blade rides on the right hand; `set_element()` recolours it — the hook for
##   future elemental combinations (arcane / fire / frost / storm) with spells.
## Sheathing restores the exact original locomotion clips, so base movement/navigation is unchanged.

const DIR := "res://assets/animations/mixamo_sword/"
## role -> [file, loop]  (selection + reasons: docs/SWORD_ANIMATIONS.md)
const CLIPS := {
	"idle": ["great_sword_idle.fbx", true],
	"idle_alt": ["great_sword_idle_2.fbx", true],
	"walk": ["great_sword_walk.fbx", true],
	"run": ["great_sword_run.fbx", true],
	"draw": ["draw_a_great_sword_2.fbx", false],
	"slash": ["great_sword_slash.fbx", false],
	"attack": ["great_sword_attack.fbx", false],
	"slash_heavy": ["great_sword_slash_3.fbx", false],
	"block": ["great_sword_blocking.fbx", false],
	"power_up": ["great_sword_power_up.fbx", false],
	"sword_cast": ["great_sword_casting.fbx", false],
}
const COMBO := ["slash", "attack", "slash_heavy"]
const ELEMENTS := {"arcane": Color(0.35, 0.65, 1.0), "fire": Color(1.0, 0.45, 0.12), "frost": Color(0.6, 0.9, 1.0), "storm": Color(0.75, 0.55, 1.0)}

var character: WorldCharacter
var drawn := false
var element := "arcane"
var blade_root: Node3D
var blade_mat: ShaderMaterial
var blade_light: OmniLight3D
var available := false
var weapon_fx: Node3D
var _combo_i := 0
var _base_loco := {}


static func attach(c: WorldCharacter) -> SwordLayer:
	var s := SwordLayer.new()
	s.name = "SwordLayer"
	s.character = c
	c.add_child(s)
	return s


static var _lib_cache := {}


func _ready() -> void:
	var sig := character.skeleton_signature()
	if _lib_cache.has(sig):
		character.body_player.add_animation_library("sw", _lib_cache[sig])
		_finish_ready(_lib_cache[sig])
		return
	var lib := AnimationLibrary.new()
	var skel_path := String(character.avatar.get_path_to(character.skeleton))
	for role in CLIPS:
		var path: String = DIR + CLIPS[role][0]
		if not ResourceLoader.exists(path):
			push_warning("[sword] missing %s (run tools/setup_local_assets.sh); sword layer disabled" % path)
			return
		var src: Node = load(path).instantiate()
		var ap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
		var anim: Animation = ap.get_animation("mixamo_com").duplicate(true)
		src.free()
		character._retarget_paths(anim, skel_path, true)
		anim.loop_mode = Animation.LOOP_LINEAR if CLIPS[role][1] else Animation.LOOP_NONE
		lib.add_animation(role, anim)
	character.body_player.add_animation_library("sw", lib)
	_lib_cache[sig] = lib
	_finish_ready(lib)


func _finish_ready(lib: AnimationLibrary) -> void:
	var loco: AnimationNodeBlendSpace1D = (character.anim_tree.tree_root as AnimationNodeBlendTree).get_node("loco")
	for i in loco.get_blend_point_count():
		_base_loco[i] = (loco.get_blend_point_node(i) as AnimationNodeAnimation).animation
	_build_blade()
	available = true
	print("[sword] layer ready: %d clips" % lib.get_animation_list().size())


func _build_blade() -> void:
	blade_root = Node3D.new()
	blade_root.name = "MagicBlade"
	character.right_hand.add_child(blade_root)
	# Grip measured from the clips (anim_preview --gripcal): blade axis = left fist → right fist,
	# expressed in the RightHand bone frame; guard sits just beyond the right fist.
	var y_axis := GRIP_AXIS.normalized()
	var x_axis := Vector3(0, 0, 1).cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	blade_root.transform = Transform3D(Basis(x_axis, y_axis, z_axis), GRIP_PALM - y_axis * 0.07)
	blade_mat = ShaderMaterial.new()
	blade_mat.shader = load("res://shaders/magic/elemental_blade.gdshader")
	blade_mat.set_shader_parameter("noise_tex", Kit.noise())
	var blade := MeshInstance3D.new()
	blade.mesh = _blade_mesh(1.05, 0.065, 0.014)
	blade.material_override = blade_mat
	blade.position = Vector3(0, 0.16, 0)
	blade_root.add_child(blade)
	var metal := Kit.metal(Color(0.72, 0.58, 0.3), 0.3)
	var grip := Kit.metal(Color(0.12, 0.08, 0.07), 0.6)
	Kit.mesh_node(blade_root, Kit.box_mesh(Vector3(0.3, 0.035, 0.045), 0.008), metal, Kit.xf(Vector3(0, 0.15, 0)), false)
	Kit.mesh_node(blade_root, Kit.lathe([Vector2(0.018, -0.12), Vector2(0.02, 0.0), Vector2(0.018, 0.14)], 8), grip, Transform3D.IDENTITY, false)
	var pommel := SphereMesh.new()
	pommel.radius = 0.028
	pommel.height = 0.056
	Kit.mesh_node(blade_root, pommel, metal, Kit.xf(Vector3(0, -0.14, 0)), false)
	blade_light = Kit.omni(blade_root, Vector3(0, 0.6, 0), ELEMENTS[element], 0.0, 3.0)
	# a look can bring its own weapon (appearance profile "weapon": {"model": glb with the blade along +Y and the grip's
	# middle at the origin, "offset": [x, y, z], "scale": 1.0}); it replaces the procedural blade and hilt and, like
	# them, is only shown while the sword is drawn
	var wp: Dictionary = AppearanceRegistry.stage_for_avatar(character.character_id, character.avatar_path).get("profile", {}).get("weapon", {})
	if wp.has("model") and ResourceLoader.exists(String(wp.model)):
		for ch in blade_root.get_children():
			if ch is MeshInstance3D:
				ch.visible = false
		var w: Node3D = (load(String(wp.model)) as PackedScene).instantiate()
		var off: Array = wp.get("offset", [0, 0, 0])
		w.position = Vector3(off[0], off[1], off[2])
		w.scale = Vector3.ONE * float(wp.get("scale", 1.0))
		w.name = "LookWeapon"
		blade_root.add_child(w)
		# "fx": a LookFX kind that rides the weapon while it is drawn (e.g. "spear_wind": wind and leaves round the blade)
		if wp.has("fx"):
			var fc: Array = wp.get("fx_color", [0.75, 1.0, 0.85])
			weapon_fx = LookFX.make(String(wp.fx), Color(fc[0], fc[1], fc[2]), Color(fc[0], fc[1], fc[2]), 1.0)
			weapon_fx.position = Vector3(0, float(wp.get("fx_y", 0.6)), 0)
			w.add_child(weapon_fx)
			LookFX.set_on(weapon_fx, false)
	blade_root.visible = false
	set_element(element)


## Flattened diamond blade along +Y with a pointed tip; UV.x across, UV.y along.
func _blade_mesh(length: float, width: float, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 12
	var prev := []
	for r in rows + 1:
		var t := float(r) / rows
		var w := width * (1.0 - pow(t, 6.0)) * (1.0 - t * 0.25)
		var y := t * length
		var ring := [Vector3(-w, y, 0), Vector3(0, y, thick), Vector3(w, y, 0), Vector3(0, y, -thick)]
		var uvx := [0.0, 0.5, 1.0, 0.5]
		if r > 0:
			for k in 4:
				var k2 := (k + 1) % 4
				var a: Vector3 = prev[k]
				var b: Vector3 = prev[k2]
				var c2: Vector3 = ring[k2]
				var d: Vector3 = ring[k]
				for v in [[a, uvx[k], t - 1.0 / rows], [b, uvx[k2], t - 1.0 / rows], [c2, uvx[k2], t], [a, uvx[k], t - 1.0 / rows], [c2, uvx[k2], t], [d, uvx[k], t]]:
					st.set_uv(Vector2(v[1], v[2]))
					st.add_vertex(v[0])
		prev = ring
	st.generate_normals()
	return st.commit()


func set_element(e: String) -> bool:
	if not ELEMENTS.has(e):
		return false
	element = e
	if blade_mat:
		blade_mat.set_shader_parameter("element", ELEMENTS[e])
		blade_light.light_color = ELEMENTS[e]
	return true


func _set_loco(sword: bool) -> void:
	var loco: AnimationNodeBlendSpace1D = (character.anim_tree.tree_root as AnimationNodeBlendTree).get_node("loco")
	var sw := ["sw/idle", "sw/walk", "sw/run"]
	for i in loco.get_blend_point_count():
		(loco.get_blend_point_node(i) as AnimationNodeAnimation).animation = sw[i] if sword else _base_loco[i]


func _oneshot(role: String) -> void:
	(character.anim_tree.tree_root as AnimationNodeBlendTree).get_node("cast_anim").animation = "sw/" + role
	character.anim_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Public actions (also exposed through the AI bridge). Each returns {ok, detail}.
func draw() -> Dictionary:
	if not available:
		return {"ok": false, "detail": "sword layer unavailable (clips missing)"}
	if drawn or character.casting:
		return {"ok": false, "detail": "already drawn" if drawn else "busy casting"}
	drawn = true
	_oneshot("draw")
	await get_tree().create_timer(0.35).timeout
	blade_root.visible = true
	if weapon_fx:
		LookFX.set_on(weapon_fx, true)
	_set_loco(true)
	_glow(0.25)
	return {"ok": true, "detail": "sword drawn (%s)" % element}


func sheathe() -> Dictionary:
	if not drawn:
		return {"ok": false, "detail": "sword not drawn"}
	drawn = false
	blade_root.visible = false
	if weapon_fx:
		LookFX.set_on(weapon_fx, false)
	_set_loco(false)
	return {"ok": true, "detail": "sword sheathed"}


func attack() -> Dictionary:
	if not drawn or character.casting:
		return {"ok": false, "detail": "draw the sword first" if not drawn else "busy casting"}
	var role: String = COMBO[_combo_i % COMBO.size()]
	_combo_i += 1
	_oneshot(role)
	_glow(0.7)
	var len := character.body_player.get_animation("sw/" + role).length
	await get_tree().create_timer(len * 0.8).timeout
	_glow(0.25)
	return {"ok": true, "detail": "sword " + role}


func power_up(e := "") -> Dictionary:
	if not drawn:
		return {"ok": false, "detail": "draw the sword first"}
	if e != "" and not set_element(e):
		return {"ok": false, "detail": "unknown element '%s' (known: %s)" % [e, ", ".join(ELEMENTS.keys())]}
	_oneshot("power_up")
	var len := character.body_player.get_animation("sw/power_up").length
	var tw := create_tween()
	tw.tween_method(_glow, 0.25, 1.0, len * 0.7)
	await tw.finished
	return {"ok": true, "detail": "blade charged with %s" % element}


func _glow(v: float) -> void:
	if blade_mat:
		blade_mat.set_shader_parameter("charge", v)
		blade_light.light_energy = v * 1.4


const GRIP_AXIS := Vector3(0.890521, 0.389362, -0.235307)   # measured, 60 two-handed frames
const GRIP_PALM := Vector3(0.00097, 0.031329, -0.003339)
