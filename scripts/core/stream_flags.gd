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
		print("[streamflags] fights %s, transformations %s, open areas %s" % [str(fights()), str(transformations()),
			str((_d.get("regions", {}) as Dictionary).keys().filter(func(a): return bool(_d.regions[a]))) if _d.get("regions") is Dictionary else "all"])
	return _d


static func fights() -> bool:
	return RenderProfile.options.has("fights") or bool(data().get("fights", true))


## Lantern Lake as a place they walk to (its "regions" entry).
static func lake() -> bool:
	return area_allowed("lantern_lake")


## May they be in this area tonight ("regions": only areas listed true; no "regions" at all: every area, as before the
## go live build). A closed area is never offered to their minds, never travelled to (journeys, walk-in gates, the
## show's or a viewer's request, the bridge) and never loaded, not even at boot. A test opens all with --all-areas.
static func area_allowed(area: String) -> bool:
	if RenderProfile.options.has("all-areas") or area == "":
		return true
	var r = data().get("regions", null)
	if not (r is Dictionary):
		return area != "lantern_lake" or bool(data().get("lake", true))
	return bool((r as Dictionary).get(area, false))


## Every area on a route open (a journey may not pass through a closed one either).
static func route_allowed(path: Array) -> bool:
	return path.all(func(a): return area_allowed(String(a)))


static func transformations() -> bool:
	return RenderProfile.options.has("transformations") or bool(data().get("transformations", true))
