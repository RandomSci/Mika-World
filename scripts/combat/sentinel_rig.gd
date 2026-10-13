class_name SentinelRig
extends CreatureBody
## The Hollow Sentinel's body: rigid rune-stones on joints (assets/creatures/sentinel/hollow_sentinel.glb).
## Animation = authored key poses per state, blended with critically-damped springs so the stone has
## weight (it accelerates and settles), plus procedural layers: breathing, a heavy alternating gait with
## real footfalls (signal -> dust + thud), torso sway. Joint rotations are Euler degrees (X pitch: negative
## swings a limb forward / up toward the creature's facing +Z; Z roll: positive tilts left side up).

const GLB := "res://assets/creatures/sentinel/hollow_sentinel.glb"
const JOINTS := ["Hips", "Torso", "Head", "Shoulder_L", "Shoulder_R", "Elbow_L", "Elbow_R", "Fist_L", "Fist_R",
	"Hip_L", "Hip_R", "Knee_L", "Knee_R"]

## Key poses (only joints that differ from rest are listed). "drop" lowers the hips (m).
const POSES := {
	"idle": {"Torso": Vector3(8, 0, 0), "Head": Vector3(-6, 0, 0), "Shoulder_L": Vector3(-6, 0, 8), "Shoulder_R": Vector3(-6, 0, -8),
		"Elbow_L": Vector3(-18, 0, 0), "Elbow_R": Vector3(-18, 0, 0), "Knee_L": Vector3(6, 0, 0), "Knee_R": Vector3(6, 0, 0), "Hip_L": Vector3(-4, 0, 0), "Hip_R": Vector3(-4, 0, 0)},
	"alert": {"Torso": Vector3(-10, 0, 0), "Head": Vector3(-14, 0, 0), "Shoulder_L": Vector3(-30, 0, 40), "Shoulder_R": Vector3(-30, 0, -40),
		"Elbow_L": Vector3(-50, 0, 0), "Elbow_R": Vector3(-50, 0, 0), "Knee_L": Vector3(14, 0, 0), "Knee_R": Vector3(14, 0, 0), "Hip_L": Vector3(-10, 0, 0), "Hip_R": Vector3(-10, 0, 0), "drop": 0.06},
	# both fists raised overhead, chest arched back, weight on the back foot
	"windup_slam": {"Torso": Vector3(-22, 0, 0), "Head": Vector3(-10, 0, 0), "Shoulder_L": Vector3(-165, 0, 12), "Shoulder_R": Vector3(-165, 0, -12),
		"Elbow_L": Vector3(-35, 0, 0), "Elbow_R": Vector3(-35, 0, 0), "Hip_L": Vector3(-20, 0, 0), "Hip_R": Vector3(10, 0, 0), "Knee_L": Vector3(20, 0, 0), "Knee_R": Vector3(8, 0, 0)},
	# fists driven into the ground in front of it, torso folded forward, knees bent
	"strike_slam": {"Torso": Vector3(38, 0, 0), "Head": Vector3(-25, 0, 0), "Shoulder_L": Vector3(-70, 0, 10), "Shoulder_R": Vector3(-70, 0, -10),
		"Elbow_L": Vector3(-8, 0, 0), "Elbow_R": Vector3(-8, 0, 0), "Hip_L": Vector3(-38, 0, 0), "Hip_R": Vector3(-20, 0, 0), "Knee_L": Vector3(48, 0, 0), "Knee_R": Vector3(32, 0, 0), "drop": 0.28},
	# stuck in the follow-through: a clear window to strike back
	"recover": {"Torso": Vector3(30, 0, 0), "Head": Vector3(-18, 0, 0), "Shoulder_L": Vector3(-60, 0, 12), "Shoulder_R": Vector3(-60, 0, -12),
		"Elbow_L": Vector3(-12, 0, 0), "Elbow_R": Vector3(-12, 0, 0), "Hip_L": Vector3(-30, 0, 0), "Hip_R": Vector3(-16, 0, 0), "Knee_L": Vector3(40, 0, 0), "Knee_R": Vector3(26, 0, 0), "drop": 0.22},
	# a backhand: torso wound to its right, right arm cocked back
	"windup_sweep": {"Torso": Vector3(0, -40, 0), "Head": Vector3(-8, 30, 0), "Shoulder_R": Vector3(10, 0, -75), "Elbow_R": Vector3(-30, 0, 0),
		"Shoulder_L": Vector3(-20, 0, 25), "Elbow_L": Vector3(-40, 0, 0), "Knee_L": Vector3(14, 0, 0), "Knee_R": Vector3(14, 0, 0), "drop": 0.05},
	"strike_sweep": {"Torso": Vector3(4, 45, 0), "Head": Vector3(-8, -25, 0), "Shoulder_R": Vector3(-80, 0, -60), "Elbow_R": Vector3(-10, 0, 0),
		"Shoulder_L": Vector3(-10, 0, 30), "Elbow_L": Vector3(-30, 0, 0), "Knee_L": Vector3(18, 0, 0), "Knee_R": Vector3(10, 0, 0), "drop": 0.08},
	"hit": {"Torso": Vector3(-16, 0, 6), "Head": Vector3(-20, 0, -8), "Shoulder_L": Vector3(-20, 0, 30), "Shoulder_R": Vector3(-20, 0, -30),
		"Elbow_L": Vector3(-30, 0, 0), "Elbow_R": Vector3(-30, 0, 0), "Knee_L": Vector3(10, 0, 0), "Knee_R": Vector3(4, 0, 0)},
	"defeat": {"Torso": Vector3(55, 0, 10), "Head": Vector3(20, 0, 0), "Shoulder_L": Vector3(-10, 0, 20), "Shoulder_R": Vector3(-10, 0, -20),
		"Hip_L": Vector3(-70, 0, 0), "Hip_R": Vector3(-70, 0, 0), "Knee_L": Vector3(95, 0, 0), "Knee_R": Vector3(95, 0, 0), "drop": 0.55},
}
## How quickly each state's pose is reached (spring frequency): slams are fast, recovery is slow.
const STIFF := {"idle": 5.0, "move": 6.0, "alert": 9.0, "windup_slam": 4.2, "strike_slam": 26.0, "recover": 3.0,
	"windup_sweep": 6.0, "strike_sweep": 24.0, "hit": 18.0, "defeat": 3.5}

var _j := {}                       # joint -> Node3D
var _rest := {}                    # joint -> Vector3 rest position (hips drop)
var _rot := {}                     # joint -> current Vector3 (deg)
var _vel := {}                     # joint -> spring velocity
var _drop := 0.0
var _drop_v := 0.0
var _gait := 0.0
var _last_foot := 0
var _stone: ShaderMaterial
var _hurt := 0.0
var _t := 0.0


func build(eye: Color) -> void:
	glow_color = eye
	var scene: PackedScene = load(GLB)
	var model := scene.instantiate()
	add_child(model)
	_stone = ShaderMaterial.new()
	_stone.shader = load("res://shaders/creature_stone.gdshader")
	var glow := _glow_material(eye, 3.0)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_override = glow if "Glow" in String(m.name) else _stone
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if "Glow" in String(m.name) else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for j in JOINTS:
		var n := model.find_child(j, true, false) as Node3D
		if n:
			_j[j] = n
			_rest[j] = n.position
			_rot[j] = Vector3.ZERO
			_vel[j] = Vector3.ZERO
	# the heart crystal casts a little light on the chest stones
	var l := FX.light(eye, 0.9 * float(RenderProfile.get_setting("magic_light_scale")), 3.5)
	l.position = Vector3(0, 1.5, 0.55)
	add_child(l)


func aim_point() -> Vector3:
	var t: Node3D = _j.get("Torso")
	return t.global_position + t.global_basis * Vector3(0, 0.55, 0.3) if t else global_position + Vector3(0, 1.6, 0)


func flash(strength := 1.0) -> void:
	_hurt = clampf(strength, 0.3, 1.0)


func _target_pose() -> Dictionary:
	var key := state
	if state == "move":
		key = "idle"
	return POSES.get(key, POSES.idle)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	state_t += delta
	var pose: Dictionary = _target_pose()
	var w: float = STIFF.get(state, 6.0)
	# procedural layers on top of the key pose
	var extra := {}
	var walking := state == "move" and move_speed > 0.15
	if walking:
		_gait += delta * clampf(move_speed, 0.4, 3.0) * 2.4
		var s := sin(_gait)
		extra = {"Hip_L": Vector3(-26 * s, 0, 0), "Hip_R": Vector3(26 * s, 0, 0),
			"Knee_L": Vector3(maxf(0.0, 34 * sin(_gait + 1.2)), 0, 0), "Knee_R": Vector3(maxf(0.0, -34 * sin(_gait + 1.2)), 0, 0),
			"Shoulder_L": Vector3(18 * s, 0, 0), "Shoulder_R": Vector3(-18 * s, 0, 0),
			"Torso": Vector3(4, 6 * s, -4 * s)}
		var foot := 1 if s > 0.0 else -1
		if foot != _last_foot:
			_last_foot = foot
			var side := 1.0 if foot > 0 else -1.0
			footfall.emit(global_position + global_basis * Vector3(side * 0.24, 0, 0.1), clampf(move_speed / 2.0, 0.4, 1.0))
	elif state in ["idle", "alert"]:
		var b := sin(_t * (1.3 if state == "idle" else 2.6))
		extra = {"Torso": Vector3(2.5 * b, 0, 0), "Shoulder_L": Vector3(0, 0, 3 * b), "Shoulder_R": Vector3(0, 0, -3 * b), "Head": Vector3(-1.5 * b, 0, 0)}
	elif state == "windup_slam":
		# a tremble that grows as the blow gathers (readable telegraph)
		var k := clampf(state_t / 1.0, 0.0, 1.0)
		extra = {"Torso": Vector3(randf_range(-1.5, 1.5) * k, 0, randf_range(-1.5, 1.5) * k)}
	for j in _j:
		var target: Vector3 = (pose.get(j, Vector3.ZERO) as Vector3) + (extra.get(j, Vector3.ZERO) as Vector3)
		# critically damped spring toward the target pose: weight without overshoot
		var x: Vector3 = _rot[j]
		var v: Vector3 = _vel[j]
		var a := (target - x) * w * w - v * 2.0 * w
		v += a * delta
		x += v * delta
		_rot[j] = x
		_vel[j] = v
		(_j[j] as Node3D).rotation_degrees = x
	var dtarget := float(pose.get("drop", 0.0)) + (0.035 * absf(sin(_gait)) if walking else 0.0)
	var da := (dtarget - _drop) * w * w - _drop_v * 2.0 * w
	_drop_v += da * delta
	_drop += _drop_v * delta
	if _j.has("Hips"):
		(_j.Hips as Node3D).position = (_rest.Hips as Vector3) - Vector3(0, _drop, 0)
	_hurt = maxf(0.0, _hurt - delta * 3.0)
	if _stone:
		_stone.set_shader_parameter("hurt", _hurt)
	_update_glow(delta, 3.0 if state != "defeat" else 0.2)


## Defeat: it folds to its knees, then the stones lose their binding light and tumble apart (rigid pieces,
## no gore), dissolving into motes. Returns after the pieces have fallen.
func collapse() -> void:
	play("defeat")
	await get_tree().create_timer(1.1).timeout
	if not is_inside_tree():
		return
	glow_level = 0.0
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if "Glow" in String(m.name):
			m.visible = false
			continue
		var start := m.global_transform
		var tw := create_tween().set_parallel(true)
		var drop := m.global_position.y - (global_position.y + randf_range(0.05, 0.25))
		var fling := Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		var spin := randf_range(-0.6, 0.6)
		var axis := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		if axis == Vector3.ZERO:
			axis = Vector3.RIGHT
		tw.tween_method(func(k: float):
			if is_instance_valid(m):
				var p := start.origin + fling * k - Vector3(0, drop * k * k, 0)
				m.global_transform = Transform3D(start.basis.rotated(axis, k * spin), p), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD)
	await get_tree().create_timer(0.6).timeout
