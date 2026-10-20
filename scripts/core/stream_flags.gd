class_name StreamFlags
extends RefCounted
## What the stream build may do tonight (data/stream_flags.json, 2026-10-20 go live with fights off): one switch for
## everything fight related (monster spawns, hunts, camp encounters, territories, road ambushes, spars and duels) and
## one for transformations. Read once; a test can force either on with --fights / --transformations.

static var _d := {}


static func data() -> Dictionary:
	if _d.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/stream_flags.json")) if FileAccess.file_exists("res://data/stream_flags.json") else null
		_d = j if typeof(j) == TYPE_DICTIONARY else {"fights": true, "transformations": true}
		print("[streamflags] fights %s, transformations %s" % [str(fights()), str(transformations())])
	return _d


static func fights() -> bool:
	return RenderProfile.options.has("fights") or bool(data().get("fights", true))


static func transformations() -> bool:
	return RenderProfile.options.has("transformations") or bool(data().get("transformations", true))
