class_name BodyMoves
extends RefCounted
## The fight's body motion (2026-10-20, Selwyn: "Mixamo is real suit mocap with true depth, so it becomes the core
## fighting body motion (strikes, guards, dodges, hits, knockdowns). Our AI video clips stay only for hand signs,
## gestures and ultimate poses"). The suit mocap found on the laptop, by deck name: the Quaternius UAL fight set
## ("ualf:Sword_Dash", CC0, one-handed sword: Mika's rapier), the Mixamo great sword pack ("sword:great_sword_slash_2",
## two hands: Luna's glaive), the Mixamo casts and falls ("mixamo:standing_1h_magic_attack_03").
## assets/animations/body_moves.json (tools/qa/body_moves.py from move_measure's dump): per clip its category (sword,
## melee, magic, defend, dodge, hit, knockdown, locomotion), weapon, tags, length, the contact times of each blow (the
## weapon hand's speed peaks), the hand's reach at each, the clip's own travel and how low her hips go.

const PATH := "res://assets/animations/body_moves.json"
static var _db := {}


static func all() -> Dictionary:
	if _db.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_db = j if typeof(j) == TYPE_DICTIONARY else {"_none": {}}
	return _db


static func has(clip: String) -> bool:
	return all().has(clip)


static func entry(clip: String) -> Dictionary:
	return all().get(clip, {})


## The clip time of its i-th blow (the last one if i is past the end), or -1.
static func hit_t(clip: String, i := 0) -> float:
	var h: Array = entry(clip).get("hits", [])
	if h.is_empty():
		return -1.0
	return float(h[clampi(i, 0, h.size() - 1)])


static func of(category: String, weapon := "") -> Array:
	var out := []
	for k in all():
		var e: Dictionary = all()[k]
		if String(e.get("category", "")) == category and (weapon == "" or String(e.get("weapon", "")) in [weapon, ""]):
			out.append(k)
	return out
