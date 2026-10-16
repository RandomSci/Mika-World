class_name WeaponArsenal
extends RefCounted
## Her weapons are permanent: each is unlocked forever the first time she reaches its form (data/
## transformation_sequences.json "weapons": Mika rapier L20, staff L30, scepter L40, spear L50; Luna glaive L20,
## staff L30, trident L40) and kept in her saved mind (progress.weapons), so restarts and the broadcast cycle keep
## them. By default she holds her current form's weapon; she can summon any earlier unlocked one (progress.weapon_choice)
## for spells, fights or to show viewers - it appears with a burst of her element (SwordLayer.summon).


static func table(who: String) -> Dictionary:
	return TransformationSequence.load_data().get("weapons", {}).get(who, {})


static func unlocked(who: String) -> Array:
	return (WorldState.mind(who).progress.get("weapons", []) as Array).duplicate()


static func level_of(who: String, id: String) -> int:
	var tb := table(who)
	for lv in tb:
		if String(tb[lv].id) == id:
			return int(lv)
	return -1


## Unlocks the weapon of form `level` (if it has one). Returns its id, or "" (none / already had it).
static func unlock(who: String, level: int) -> String:
	var tb := table(who)
	if not tb.has(str(level)):
		return ""
	var id := String(tb[str(level)].id)
	var m := WorldState.mind(who)
	var have: Array = m.progress.get("weapons", [])
	if have.has(id):
		return ""
	have.append(id)
	m.progress["weapons"] = have
	WorldState.record_activity({"id": "weapon:" + id, "verb": "unlock", "label": "Unlocked %s" % tb[str(level)].name}, {"knowledge": {"weapon:" + id: 1}}, who)
	return id


## Every weapon of a form she already wears (saves from before the arsenal existed).
static func sync(who: String) -> Array:
	var cur := AppearanceRegistry.current(who)
	var lvl := int(cur.get("order", 0))
	var got := []
	for lv in table(who):
		if int(lv) <= lvl:
			var id := unlock(who, int(lv))
			if id != "":
				got.append(id)
	return got


## Her current weapon: the one she chose (if unlocked), else the weapon of the highest form she has reached.
static func current(who: String) -> String:
	var have := unlocked(who)
	var choice := String(WorldState.mind(who).progress.get("weapon_choice", ""))
	if choice != "" and have.has(choice):
		return choice
	var best := ""
	var bl := -1
	for id in have:
		var l := level_of(who, String(id))
		if l > bl:
			bl = l
			best = String(id)
	return best


## The weapon's model and effect, from the appearance stage of its form (profile.weapon).
static func model_for(who: String, id: String) -> Dictionary:
	var lvl := level_of(who, id)
	if lvl < 0:
		return {}
	for s in AppearanceRegistry.stages(who):
		if int(s.get("order", -1)) == lvl:
			return s.get("profile", {}).get("weapon", {})
	return {}


static func choose(who: String, id: String) -> bool:
	if id != "" and not unlocked(who).has(id):
		return false
	WorldState.mind(who).progress["weapon_choice"] = id
	return true


static func describe(who: String) -> Dictionary:
	var tb := table(who)
	var out := []
	for lv in tb:
		out.append({"level": int(lv), "id": tb[lv].id, "name": tb[lv].name, "unlocked": unlocked(who).has(tb[lv].id)})
	return {"current": current(who), "weapons": out}
