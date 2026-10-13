class_name HeadPosture
extends SkeletonModifier3D
## Emotional head carriage (Milestone K, from the lab's posture layer): a small head / neck tilt (roll) and
## nod (pitch) on top of the animation and the look-at, read from FaceController.posture each frame, plus short
## nods (`nod()`, e.g. while listening). Spring-smoothed; never more than ~12 degrees.

var face: FaceController
var _roll := 0.0
var _pitch := 0.0
var _nod_t := -1.0
var _nod_amp := 0.0
var _head := -1
var _neck := -1


func _ready() -> void:
	var sk := get_skeleton()
	if sk:
		_head = sk.find_bone("Head")
		_neck = sk.find_bone("Neck")


func nod(amp := 0.12) -> void:
	_nod_t = 0.0
	_nod_amp = amp


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _head < 0:
		return
	var p: Dictionary = face.posture if face else {}
	var k := 1.0 - exp(-delta * 5.0)
	_roll = lerpf(_roll, clampf(float(p.get("roll", 0.0)), -0.2, 0.2), k)
	_pitch = lerpf(_pitch, clampf(float(p.get("pitch", 0.0)) + 0.1 * float(p.get("gaze_down", 0.0)) - 0.06 * float(p.get("gaze_up", 0.0)), -0.15, 0.18), k)
	var nod_v := 0.0
	if _nod_t >= 0.0:
		_nod_t += delta
		nod_v = _nod_amp * sin(clampf(_nod_t / 0.45, 0.0, 1.0) * PI)
		if _nod_t > 0.45:
			_nod_t = -1.0
	var q := Quaternion(Vector3(0, 0, 1), _roll * 0.65) * Quaternion(Vector3(1, 0, 0), (_pitch + nod_v) * 0.65)
	sk.set_bone_pose_rotation(_head, sk.get_bone_pose_rotation(_head) * q)
	if _neck >= 0:
		var q2 := Quaternion(Vector3(0, 0, 1), _roll * 0.35) * Quaternion(Vector3(1, 0, 0), (_pitch + nod_v) * 0.35)
		sk.set_bone_pose_rotation(_neck, sk.get_bone_pose_rotation(_neck) * q2)
