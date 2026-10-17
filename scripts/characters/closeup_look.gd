class_name CloseupLook
extends Node3D
## Day 3: how a face looks up close. Only while a close-up is live (the approved emotional moments, the stills):
##   * a soft key light from beside the lens and a little above, and a rim light behind the head in her colour - small
##     ranges, no shadows, so the world's lighting is untouched beyond her head and shoulders
##   * the face skin's MToon shade brought back from almost flat (-0.80) to a soft gradient, so the face has shape
##   * the eye highlights lifted (emission), so the eyes catch the light
##   * expressions a touch stronger (FaceController.closeup_boost)
## Everything is put back exactly when the close-up ends. The VRM files are never modified.

const RIM := {"mika": Color(0.74, 0.8, 1.0), "luna": Color(1.0, 0.9, 0.74)}
## white hair blooms under a strong rim: per character (key, rim) energies
const ENERGY := {"mika": [0.55, 0.45], "luna": [0.55, 0.55]}
const FACE_SHADE := -0.5          # (the medium-shot conversion uses about -0.80: flat at close range)
const HIGHLIGHT_EMISSION := 0.55

var c: WorldCharacter
var key: SpotLight3D
var rim: OmniLight3D
var lens := Vector3.ZERO           # where the camera is (the key sits beside it)
var _saved: Array = []             # [material, param, value]
var _head := -1


static func enable(ch: WorldCharacter, camera_pos: Vector3) -> CloseupLook:
	var cl: CloseupLook = ch.get_node_or_null("CloseupLook")
	if cl == null:
		cl = CloseupLook.new()
		cl.name = "CloseupLook"
		cl.c = ch
		ch.add_child(cl)
		cl._build()
	cl.lens = camera_pos
	return cl


static func disable(ch: WorldCharacter) -> void:
	var cl: CloseupLook = ch.get_node_or_null("CloseupLook")
	if cl:
		cl._restore()
		cl.queue_free()


func _build() -> void:
	_head = c.skeleton.find_bone("Head") if c.skeleton else -1
	key = SpotLight3D.new()
	key.light_color = Color(1.0, 0.98, 0.96)
	key.light_energy = float(ENERGY.get(c.character_id, [0.8, 0.8])[0])
	key.spot_range = 2.6
	key.spot_angle = 24.0
	key.spot_angle_attenuation = 1.6
	key.shadow_enabled = false
	key.light_specular = 0.15
	add_child(key)
	rim = OmniLight3D.new()
	rim.light_color = RIM.get(c.character_id, Color(0.9, 0.9, 1.0))
	rim.light_energy = float(ENERGY.get(c.character_id, [0.8, 0.8])[1])
	rim.omni_range = 0.95
	rim.omni_attenuation = 1.4
	rim.shadow_enabled = false
	rim.light_specular = 0.0
	add_child(rim)
	# the face skin and the eye highlights (this avatar's own material instances)
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si) as ShaderMaterial
			if mat == null:
				continue
			var rn := String(mat.resource_name)
			if rn.contains("_Face_00_SKIN"):
				_tweak(mat, "_ShadeShift", FACE_SHADE)
				_tweak(mat, "_ReceiveShadowRate", 0.25)      # (hair and leaf shadows broke the face into patches)
			elif rn.contains("EyeHighlight"):
				_tweak(mat, "_EmissionColor", Color(1, 1, 1, 1))
				_tweak(mat, "_EmissionMultiplier", HIGHLIGHT_EMISSION)
	if c.face:
		c.face.closeup_boost = 1.22


func _tweak(mat: ShaderMaterial, param: String, v) -> void:
	_saved.append([mat, param, mat.get_shader_parameter(param)])
	mat.set_shader_parameter(param, v)


func _restore() -> void:
	for s in _saved:
		if is_instance_valid(s[0]):
			(s[0] as ShaderMaterial).set_shader_parameter(String(s[1]), s[2])
	_saved.clear()
	if c and c.face:
		c.face.closeup_boost = 1.0


func _process(_delta: float) -> void:
	if c == null or c.skeleton == null or _head < 0:
		return
	var head: Vector3 = c.skeleton.global_transform * c.skeleton.get_bone_global_pose(_head).origin + Vector3(0, 0.06, 0)
	var to_lens := lens - head
	to_lens.y = 0.0
	to_lens = to_lens.normalized() if to_lens.length() > 0.05 else -c.global_transform.basis.z
	var side := Vector3(-to_lens.z, 0, to_lens.x)
	# key: 35 degrees off the lens axis, a little above, 0.9 m out; rim: behind and above the head, away from the lens
	var kp := head + (to_lens * 0.82 + side * 0.55).normalized() * 0.9 + Vector3(0, 0.32, 0)
	key.global_position = kp
	key.look_at(head, Vector3.UP)
	rim.global_position = head - to_lens * 0.42 + side * -0.12 + Vector3(0, 0.22, 0)
