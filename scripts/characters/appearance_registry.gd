class_name AppearanceRegistry
extends RefCounted
## Level-based appearances (docs/APPEARANCES.md, data/appearances.json). Each mage has her own ordered stages; her
## OWN progression picks one: requirements {level: N} reached and {form: id} taken (the form she became in its
## transformation cinematic = progress.appearance - the established Level 10 behaviour, unchanged). The highest-order
## READY stage that qualifies wins; planned stages (models not made yet) are skipped, so a mage beyond the last
## available stage keeps the latest look she has (safe fallback). Missing files fall back the same way, ending at the
## first ready stage and finally the mage's old base avatar. Nothing here changes progress: a developer preview
## (preview()) overrides only what is shown, never what she has earned.

static var _data := {}
static var _preview := {}           # who -> stage id (developer preview, never saved)


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/appearances.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text()) if f else {}
	return _data


static func stages(who: String) -> Array:
	return data().get(who, {}).get("stages", [])


static func stage_by_id(who: String, id: String) -> Dictionary:
	for s in stages(who):
		if String(s.id) == id:
			return s
	for s in data().get(who, {}).get("archive", []):
		if String(s.id) == id:
			return s
	return {}


static func _ready_stage(s: Dictionary) -> bool:
	return String(s.get("status", "")) == "ready" and String(s.get("avatar", "")) != "" and ResourceLoader.exists(String(s.avatar))


static func _qualifies(who: String, s: Dictionary, level: int, form: String) -> bool:
	var req: Dictionary = s.get("requires", {})
	if req.has("level") and level < int(req.level):
		return false
	if req.has("form") and form != String(req.form):
		return false
	return true


## The stage she wears now, from her own progression (level + the form she has taken).
static func current(who: String) -> Dictionary:
	if _preview.has(who):
		var p := stage_by_id(who, String(_preview[who]))
		if not p.is_empty() and ResourceLoader.exists(String(p.get("avatar", ""))):
			return p
	var m := WorldState.mind(who)
	var level := m.level()
	var form := String(m.progress.get("appearance", ""))
	return pick(who, level, form)


## The stage for a given level and taken form (tests, the registry preview, save checks).
static func pick(who: String, level: int, form: String) -> Dictionary:
	var best := {}
	for s in stages(who):
		if not _ready_stage(s) or not _qualifies(who, s, level, form):
			continue
		if best.is_empty() or int(s.get("order", 0)) > int(best.get("order", 0)):
			best = s
	if best.is_empty():
		for s in stages(who):
			if _ready_stage(s):
				return s
	return best


static func avatar_for(who: String) -> String:
	var s := current(who)
	if not s.is_empty():
		return String(s.avatar)
	# no registry entry at all: the mage's own base avatar (data/mages.json), as before
	Progression.load_data()
	return String(Progression.mages.get(who, {}).get("base_avatar", "res://assets/characters/mika/Mika.vrm"))


## Per-stage overrides (face cfg, springs, light, motion profile) merged over the mage's own config.
static func profile(who: String) -> Dictionary:
	return current(who).get("profile", {})


## The stage that holds a given avatar file (so a swap - e.g. the transformation - knows its profile).
static func stage_for_avatar(who: String, path: String) -> Dictionary:
	for s in stages(who):
		if String(s.get("avatar", "")) == path:
			return s
	for s in data().get(who, {}).get("archive", []):
		if String(s.get("avatar", "")) == path:
			return s
	return {}


## Developer preview: show a stage (or an archived look) without touching progression. "" clears it.
static func preview(who: String, stage_id: String) -> bool:
	if stage_id == "":
		_preview.erase(who)
		return true
	var s := stage_by_id(who, stage_id)
	if s.is_empty() or not ResourceLoader.exists(String(s.get("avatar", ""))):
		return false
	_preview[who] = stage_id
	return true


static func previewing(who: String) -> String:
	return String(_preview.get(who, ""))


## For overlays / the bridge / tests: every stage with its state for this mage.
static func describe(who: String) -> Array:
	var cur := String(current(who).get("id", ""))
	return stages(who).map(func(s): return {"id": s.id, "name": s.name, "levels": s.get("levels", []), "status": s.get("status", ""),
		"available": _ready_stage(s), "current": String(s.id) == cur})
