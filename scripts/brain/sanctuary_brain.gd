class_name SanctuaryBrain
extends Node
## Mika's deterministic planner for her home region, built on multi-stage ACTIVITIES instead of short
## one-shot actions. Every decision is generated from the real world and executed through the same
## systems a player or the AI bridge would use; outcomes come back from the engine and feed the next choice.
##
## Activities (options are generated, never a fixed list):
##   research    - pick an unread book (any order), walk / travel to it, really read its pages
##   magic       - practise a castable spell on a fitting reactive target; several attempts while improving;
##                 experiments prefer reactions she has never observed; stops on success, fatigue or failure
##   investigate - follow a story lead from StoryManager (wake the gate sign, the pond, the Heartstone...)
##   explore     - visit the least-recently seen sub-area, look around at its points of interest
##   rest        - sit and meditate (longer when more tired), watch the pond
##   alchemy     - brew the known recipe, or experiment when curious and the recipe is unknown
##   converse    - approach a visiting traveller she has not spoken to this visit
##   journal     - write an entry from verified events
##   attune      - attune to the ritual circle / the Heartstone, offered only once she has read the text that
##                 describes it (the interactable's lore_id); an open trial for it adds a pull
## Utility = base + needs (energy, curiosity, mastery drive, social) + story pull + novelty
##           - repetition (same kind / same target recently) - travel + small jitter.
## An optional curiosity model (CuriosityModule) may only add a bonus to one of the currently valid options.
## Private reasoning (scores, choices) is never spoken: it is a developer-HUD thought and a bridge event.

signal thought(text: String, sub_area: String)
signal decided(decision: Dictionary)

const REGION := "arcane_sanctuary"

var main: Node
var me: WorldCharacter            # the mage this planner instance drives
var mika: WorldCharacter:         # compatibility alias (older callers read brain.mika)
	get: return me
var agent_id := "mika"
var mind: MageMind                # HER knowledge, inventory, skills and trials (never another mage's)
var profile := {}                 # data/mages.json entry: activities, temperament, voice, signature spell
var threat: Monster = null        # a creature attacking her right now (set by the spawner)
var hold := false                 # another mage asked to talk: finish nothing new until released
var explore_map: ExplorationMap   # her own spatial curiosity (coverage, candidates)
var last_roam := {}               # the most recent roam (for tests / the developer overlay)
var _celebrate_until := 0.0       # a recent level-up makes a special performance tempting
var _mark_t := 0.0
var _speak_lines := {}
var enabled := false
var busy := false
var needs := {"energy": 0.85, "curiosity": 0.7, "mastery": 0.6, "social": 0.4}
var last_decision := {}
var history: Array = []
var current := {}              # the running activity {kind, label, key, stage, started}
var rng := RandomNumberGenerator.new()
var _recent_kinds: Array[String] = []
var _recent_targets: Array[String] = []
var _failures := {}            # option key -> decisions left to avoid
var _interrupt := ""
var _cancel := false
var _listened_this_rain := ""      # the area where she already sat out this shower
var _speak_cd := 0.0
var _talked_this_visit := {}
var curiosity_bonus := {}      # option key -> bonus from the curiosity module (one decision only)
var resume_key := ""            # relaunch: what she was doing when the game stopped (favoured once, if still on offer)
var lost := false                   # Day 3: she took a wrong turn on a wander (the discovery rate rises while lost)
var viewer_request := {}            # spell id -> {target, t}: a viewer suggestion, kept until chosen or 4 minutes old
const VIEWER_REQUEST_S := 240.0


static func sub_area(world: Node, pos: Vector3) -> String:
	if world == null:
		return ""
	if world.has_method("sub_area_at"):
		return world.sub_area_at(pos)
	if world.get("area_id") == "arcane_library":
		return "ancient_spell_library"
	return ""


func setup(m: Node, who := "mika") -> void:
	main = m
	agent_id = who
	me = main.characters[who]
	mind = WorldState.mind(who)
	Progression.load_data()
	profile = Progression.mages.get(who, {})
	rng.seed = 2026 + hash(who) % 1000
	if not RenderProfile.options.has("fixed-seed"):
		rng.randomize()               # (Day 2: a fixed seed replayed the same day after every restart)
	# her recent activities survive a restart (Day 2: the memory used to start empty every launch)
	for k in mind.knowledge.get("recent_kinds", []):
		_recent_kinds.append(String(k))
	for k in mind.knowledge.get("recent_targets", []):
		_recent_targets.append(String(k))
	explore_map = ExplorationMap.new(main, me, mind, profile.get("explore_taste", {}))
	if main.progression:
		main.progression.leveled.connect(func(w, _l): if w == agent_id: _celebrate_until = Time.get_unix_time_from_system() + 900.0)


func _voice() -> String:
	return String(profile.get("voice", agent_id))


## Where she stands to use `it`: its approach point, a little further back for a wide gown (Luna's hem overlapped
## the spell altar's base standing at the plain approach point; motion_profiles.json "stand_off", metres).
func _stand_at(it) -> Vector3:
	var p: Vector3 = it.approach_point()
	var off := float(me.motion.get("stand_off", 0.0)) if me.get("motion") is Dictionary else 0.0
	if off <= 0.0:
		return p
	var away := Vector3(p.x - it.global_position.x, 0, p.z - it.global_position.z)
	if away.length() < 0.05:
		return p
	var map: RID = me.get_world_3d().navigation_map
	return NavigationServer3D.map_get_closest_point(map, p + away.normalized() * off)


## Night, and she lives at home (Levels 1-9) in the sanctuary with Starfall Hill: the hill is where the night is spent.
func _night_home() -> bool:
	return mind.level() <= 9 and WorldState.daylight() < 0.2 and StarfallPlace.instance != null and is_instance_valid(StarfallPlace.instance) \
		and main.streaming.current_id == "sanctuary"


func _allowed(kind: String) -> bool:
	return (profile.get("activities", []) as Array).is_empty() or (profile.activities as Array).has(kind)


func is_lead() -> bool:
	return agent_id == "mika"


## The followed mage: the only one allowed to cause an area change (travel).
func is_foreground() -> bool:
	return main.sim_mode(agent_id) == "foreground" if main.has_method("sim_mode") else is_lead()


func set_enabled(v: bool) -> void:
	enabled = v
	_cancel = not v
	if not v and main.book_reader.reading():
		main.book_reader.stop()
	if v and not busy:
		_loop()


func interrupt(reason: String) -> void:
	_interrupt = reason


func status() -> Dictionary:
	var n := {}
	for k in needs:
		n[k] = snappedf(needs[k], 0.01)
	return {"enabled": enabled, "busy": busy, "needs": n, "current": current, "last_decision": last_decision,
		"recent": history.slice(maxi(0, history.size() - 8))}


func _in_region() -> bool:
	return WorldState.areas.get(main.streaming.current_id, {}).get("region", "") == REGION


# ------------------------------------------------------------------ option generation
func options() -> Array:
	var out := []
	var here: String = main.streaming.current_id
	# research: books with unread (visible) pages
	for bid in BookLibrary.data().books:
		var b := BookLibrary.book(bid)
		var visible := (b.pages as Array).filter(func(pg): return not pg.has("requires_knowledge") or mind.knowledge.has(pg.requires_knowledge))
		var unread := visible.size() - BookLibrary.pages_read(bid, agent_id).filter(func(i): return i < visible.size()).size()
		if unread <= 0:
			continue
		var loc := _book_location(bid)
		if loc.is_empty():
			continue
		# only books she has actually seen (or already started) - no knowledge of what she never noticed - or one a
		# story lead sends her to find (Day 2: the daybook says the sign "can only be woken": she goes to the library
		# to find out how; without this the story stalled before Level 10, the library book never noticed)
		var lead_book: bool = main.story.next_leads().any(func(l): return String(l.get("book", "")) == bid)
		if not lead_book and not mind.knowledge.has("noticed:" + String(loc.interactable)) and BookLibrary.pages_read(bid, agent_id).is_empty():
			continue
		if not is_foreground() and loc.area != here:
			continue          # only the followed mage may cause an area change
		if main.book_reader.reading() and main.book_reader.current.get("reader", "") != agent_id:
			continue          # one reader at a time (the lectern book is a single physical object)
		out.append({"kind": "research", "key": "research:" + bid, "book": bid, "interactable": loc.interactable, "area": loc.area,
			"label": "read %s" % b.title, "unread": unread})
	# magic: castable spells x fitting reactive targets in this area
	if here == "sanctuary":
		var reactives: Dictionary = main.magic.reactives()
		for s in main.magic.known_spells(agent_id):
			if not s.castable or s.id == "elemental_charge":
				continue
			var spell := MagicSystem.spell(s.id)
			var best_t := ""
			var best_novel := false
			var best_rank := -1
			for rid in reactives:
				var r: ReactiveElement = reactives[rid]
				if r is Monster:
					continue          # creatures are hunted (their own option), not practice targets
				var kinds: Array = spell.get("target_kinds", ["*"])
				if not kinds.has("*") and not kinds.has(r.kind):
					continue
				if mind.knowledge.has("noeffect:%s:%s" % [s.id, r.kind]) and not _advances_trial(rid):
					continue          # she has seen this spell do nothing to this kind of object
				var novel: bool = not mind.knowledge.keys().any(func(k): return String(k).begins_with("reaction:%s:%s:" % [s.id, r.kind]))
				var rank := (2 if _advances_trial(rid) else 0) + (1 if novel else 0)
				if best_t == "" or rank > best_rank or (rank == best_rank and rng.randf() < 0.3):
					best_t = rid
					best_novel = novel
					best_rank = rank
			# a viewer asked for this spell on a particular object: offer exactly that (if it is a valid target)
			var asked: String = viewer_request.get(s.id, {}).get("target", "")
			if asked != "" and reactives.has(asked):
				var ak: Array = spell.get("target_kinds", ["*"])
				if ak.has("*") or ak.has((reactives[asked] as ReactiveElement).kind):
					best_t = asked
					best_novel = not mind.knowledge.keys().any(func(k): return String(k).begins_with("reaction:%s:%s:" % [s.id, (reactives[asked] as ReactiveElement).kind]))
			if best_t != "":
				out.append({"kind": "magic", "key": "magic:%s:%s" % [s.id, best_t], "spell": s.id, "target": best_t, "novel": best_novel,
					"mastery": s.mastery, "trial": _advances_trial(best_t), "label": "%s %s at %s" % ["experiment with" if best_novel else "practise", s.name, reactives[best_t].label]})
	# story leads (reading leads are covered by research options, with a story bonus) - the story is Mika's
	for l in (main.story.next_leads() if _allowed("investigate") else []):
		if l.activity == "research":
			continue
		if not main.magic.can_cast(String(l.get("spell", "")), agent_id).ok:
			continue
		out.append({"kind": "investigate", "key": "investigate:%s:%s" % [l.target, l.spell], "target": l.target, "spell": l.spell, "label": l.lead})
	# Day 3 discoveries: the find she just noticed (hers), the one the other mage noticed (go and see), past finds here
	var dd = main.get("discoveries")
	if dd and not dd.live.is_empty() and String(dd.live.area) == here and is_instance_valid(dd.live.get("it")) and me.visible:
		if String(dd.live.who) == agent_id:
			out.append({"kind": "discover", "key": "discover:%d" % int(dd.live.seq), "interactable": (dd.live.it as Interactable).id,
				"label": "look at %s" % String(dd.live.find.label)})
		elif me.global_position.distance_to(dd.live.pos) < 35.0:
			out.append({"kind": "join_find", "key": "join_find:%d" % int(dd.live.seq), "pos": dd.live.pos,
				"label": "go and see what %s found" % MagicSystem.display_name(String(dd.live.who))})
	if dd and me.visible:
		for it in dd.revisits():
			out.append({"kind": "revisit", "key": "revisit:" + (it as Interactable).id, "interactable": (it as Interactable).id, "label": (it as Interactable).label.to_lower()})
	# wander off the paths (and now and then get a little lost): where finds are most likely
	if main.world and me.visible and is_lead() and threat == null:
		out.append({"kind": "wander", "key": "wander:" + here, "label": "wander off the path"})
	# explore
	for sid in WorldState.sanctuary.sub_areas:
		if sid == "ancient_spell_library":
			continue
		out.append({"kind": "explore", "key": "explore:" + sid, "sub_area": sid, "label": "explore the %s" % WorldState.sanctuary.sub_areas[sid].name})
	# roam: somewhere she has NOT been that she can see from here (spatial curiosity, real navmesh)
	if main.world and me.visible:
		for c in explore_map.candidates(2):
			out.append({"kind": "roam", "key": "roam:" + ExplorationMap.cell_key(c.pos), "pos": c.pos, "cand": c, "label": "look at %s" % c.describe})
	# perform: a leisure option (casual) or, now and then, a special performance (celebration / evening)
	# (Mika's own choice only: Luna dances when asked - the show, a viewer - or as Mika's partner. Her solo dances out of
	# nowhere, filmed since every dance in view is, looked random on stream, 2026-10-17)
	if main.performance and _allowed("perform") and is_lead() and me.visible and threat == null and not main.performance.busy():
		var cd: Dictionary = PerformanceController.load_cfg().cooldown_s
		var last := float(mind.music.get("last_unix", 0))
		var now_u := Time.get_unix_time_from_system()
		if now_u - last > float(cd.casual) and not MusicLibrary.eligible(agent_id, "casual").is_empty():
			out.append({"kind": "perform", "key": "perform:casual", "mode": "casual", "label": "dance to some music for a bit"})
		var last_sp := float(mind.music.get("last_special_unix", 0))
		if now_u - last_sp > float(cd.special) and (now_u < _celebrate_until or WorldState.night) and not MusicLibrary.eligible(agent_id, "special").is_empty():
			out.append({"kind": "perform", "key": "perform:special", "mode": "special", "label": "give a little performance in the circle" + (" to celebrate" if now_u < _celebrate_until else "")})
	# gather: plants she has noticed that are there to pick
	for g in get_tree().get_nodes_in_group("gatherable"):
		if (g as GatherNode).available() and mind.knowledge.has("noticed:gather:" + String(g.gid)):
			out.append({"kind": "gather", "key": "gather:" + String(g.gid), "node": g, "item": String(g.def.get("item", g.kind)),
				"label": "pick the %s" % String(g.label()).to_lower()})
	# rest
	var rest_labels := {"garden_meditate": "meditate on the Still Stone", "watchpoint_rest": "rest on the watchpoint bench", "pond_reflect": "watch the pond"}
	for seat in rest_labels:
		# only where the seat really is (2026-10-18 live: the show's "quiet outside" failed twice, "no garden_meditate here")
		if main.world and main.world.interactables.has(seat):
			out.append({"kind": "rest", "key": "rest:" + seat, "interactable": seat, "label": rest_labels[seat]})
	# alchemy
	if main.world is Sanctuary and main.world.alchemy and main.world.alchemy.bowl_state == "empty":
		var knows: bool = mind.knowledge.has("recipe:luminous_draught")
		if knows or not mind.knowledge.has("alchemy:ember_salt_fizz"):
			out.append({"kind": "alchemy", "key": "alchemy", "label": "brew a Luminous Draught" if knows else "experiment at the alchemy table"})
	# converse (the travellers' memories are about Mika in this slice)
	for nid in (main.npcs.present if _allowed("converse") else {}):
		var npc = main.npcs.present[nid]
		if is_instance_valid(npc) and npc.state == "idle" and not _talked_this_visit.has(nid + str(main.dialogue.state_of(nid).visits)):
			out.append({"kind": "converse", "key": "converse:" + nid, "npc": nid, "label": "talk with %s" % main.dialogue.travellers[nid].name})
	# the people who live here: someone she can see, at their place, with something she has not heard from them yet
	if _allowed("chat") and main.get("town"):
		for rid in main.town.residents:
			var rr = main.town.residents[rid]
			if not is_instance_valid(rr) or not rr.visible or rr.state == "walking" or rr.state == "inside":
				continue
			if me.global_position.distance_to(rr.global_position) > 35.0:
				continue
			var fresh: Array = (rr.data.get("talk", []) as Array).filter(func(tp): return not mind.knowledge.has("talked:%s:%s" % [rid, tp.id]))
			if fresh.is_empty():
				continue
			out.append({"kind": "chat", "key": "chat:" + String(rid), "resident": String(rid), "topic": fresh[0],
				"first": not mind.knowledge.has("met_resident:" + String(rid)), "label": "talk with %s (%s)" % [String(rr.data.get("name", rid)), String(rr.data.get("role", ""))]})
	# rain: get out of it (a doorstep under the eaves, the lee of a big tree), then sit and listen to it a while
	var wx = main.get("weather")
	if wx != null and wx.rain > 0.35 and me.visible and threat == null:
		if wx.sheltered_at(me.global_position):
			if _listened_this_rain != here:
				out.append({"kind": "listen_rain", "key": "listen_rain", "label": "sit and listen to the rain"})
		else:
			var spots: Array = wx.shelter_spots(me.global_position)
			if not spots.is_empty():
				out.append({"kind": "shelter", "key": "shelter", "spot": spots[0],
					"label": "get out of the rain (%s)" % String(spots[0].label).replace("_", " ")})
	elif wx != null and wx.rain < 0.1:
		_listened_this_rain = ""
	# places only Rising Air reaches (the Mentor's Tower crown and its bells): once she knows why to go up there
	if main.world and main.world.has_method("rise_spots") and me.visible and threat == null and main.magic.can_cast("rising_air", agent_id).ok:
		for rs in main.world.rise_spots():
			if not mind.knowledge.has(String(rs.clue)) or mind.knowledge.has(String(rs.done)):
				continue
			if String(rs.purpose) == "crown" and not (WorldState.night or WorldState.daylight() < 0.15):
				continue          # the bells only move in the night wind (the founders' notes say so)
			if int(mind.knowledge.get("ascended:" + String(rs.key), -1)) == WorldState.day():
				continue          # once a night is enough
			out.append({"kind": "ascend", "key": "ascend:" + String(rs.key), "spot": rs, "label": "rise up to %s" % String(rs.label)})
	# expeditions: a clue she has really read becomes a reason to set out (data/expeditions.json)
	if _allowed("expedition") and is_lead() and main.get("journeys") and not main.journeys.active() and mind.vigor > 0.6:
		var ex: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/expeditions.json")).get("expeditions", {})
		var here_id: String = main.streaming.current_id
		for eid in ex:
			var e: Dictionary = ex[eid]
			if not mind.knowledge.has(String(e.clue)) or mind.knowledge.has(String(e.done_if)) or String(e.area) == here_id:
				continue
			if WorldState.route(here_id, String(e.area)).size() < 2:
				continue
			out.append({"kind": "expedition", "key": "expedition:" + eid, "area": String(e.area), "purpose": String(e.purpose),
				"curiosity": float(e.get("curiosity", 0.25)), "label": "set out for the %s (%s)" % [String(e.area).replace("_", " "), String(e.purpose)]})
	# at the lake at night: sit at the end of the pier and watch the lanterns (once a night)
	if here == "lantern_lake" and main.world and main.world.has_method("sit_spots") and int(mind.knowledge.get("lake_night", -1)) != night_id():
		out.append({"kind": "lakewatch", "key": "lakewatch", "area": "lantern_lake", "label": "sit at the end of the pier and watch the lanterns"})
	# a walk to another part of the home region (Day 2): the library, the woods' trails and clearings, the tower -
	# and home to the sanctuary again (always at dusk). Only the followed mage changes area; the other comes along.
	if is_foreground() and main.travel and not main.travel.active() and threat == null:
		for loc in HOME_VISITS:
			var va: String = WorldState.area_of(loc)
			if va == here or WorldState.route(here, va).size() < 2:
				continue
			out.append({"kind": "visit", "key": "visit:" + va, "area": va, "location": loc,
				"label": String(HOME_VISITS[loc])})
	# getting ready for an unfinished fight: drill her family's ward (a real cast each time; mastery grows)
	if not unfinished().is_empty() and mind.vigor > 0.5:
		for wid in MagicSystem.load_catalog().spells:
			var ws: Dictionary = MagicSystem.spell(wid)
			if String(ws.get("projectile", "")) == "ward" and String(ws.get("caster", agent_id)) == agent_id and main.magic.can_cast(wid, agent_id).ok:
				var uf: Dictionary = unfinished()[0]
				out.append({"kind": "drill", "key": "drill:" + wid, "spell": wid, "for": String(uf.get("kind", "")),
					"label": "drill her %s (getting ready for the %s)" % [String(ws.get("name", wid)).to_lower(), String(uf.get("name", "creature")).to_lower()]})
				break
	# a lesson being taught where she is (the academy's teacher living his own day): a free place on the bench
	if _allowed("lesson") and main.get("town") and main.town.teaching() != null:
		var last := float(String(mind.knowledge.get("lesson_last_min", "-9999")))
		if WorldState.world_min - last > 180.0:
			for sid in ["lesson_seat_3", "lesson_seat_4", "lesson_seat_5"]:
				var seat = main.world.interactables.get(sid)
				if seat and not seat.busy:
					var tch: Resident = main.town.teaching()
					out.append({"kind": "lesson", "key": "lesson:" + tch.id, "interactable": sid, "teacher": tch.id,
						"first": not mind.knowledge.has("mentor:" + tch.id), "label": "sit in on %s's lesson" % String(tch.data.get("name", tch.id))})
					break
	# attune: only where the place exists and once she has read what it is for
	if here == "sanctuary":
		for id in ATTUNE:
			var it = main.world.interactables.get(id)
			if it and (ATTUNE[id] as Array).any(func(k): return mind.knowledge.has(k)):
				out.append({"kind": "attune", "key": "attune:" + id, "interactable": id, "label": String(it.label).to_lower(),
					"attuned": mind.activity_counts.has("attune:" + id)})
	# hunt: only creatures SHE can see right now (no knowledge of what lurks out of sight)
	if main.spawner and here == "sanctuary":
		for mon in (main.spawner.perceived_by(me) if StreamFlags.fights() else []):
			var mk: String = mon.kind
			var mdef: Dictionary = Spawner.data.monsters.get(mk, {})
			out.append({"kind": "hunt", "key": "hunt:" + mon.id, "monster": mon.id, "monster_kind": mk, "tier": mon.tier(),
				"attacking_me": mon.target_mage == me, "distance": snappedf(me.global_position.distance_to(mon.global_position), 0.1),
				"label": "%s the %s" % ["fight off" if mon.target_mage == me else "hunt", String(mdef.get("name", mk)).to_lower()]})
		# loot she saw fall and has not picked up
		for l in LootPickup.all_in(main.world):
			if not l.claimed and me.global_position.distance_to(l.global_position) < 18.0:
				out.append({"kind": "collect", "key": "collect:" + str(l.get_instance_id()), "loot": l, "label": "pick up %s" % l.label()})
		# recover: hurt in battle -> withdraw inside the circle's ward and catch her breath
		if mind.vigor < 0.6:
			out.append({"kind": "recover", "key": "recover", "label": "catch my breath inside the circle"})
	# meet another mage she can see (she may also simply not)
	for other_id in main.mages:
		if other_id == agent_id:
			continue
		var oc: WorldCharacter = main.characters.get(other_id)
		if oc and oc.visible and me.global_position.distance_to(oc.global_position) < 30.0:
			var last_met := float(mind.knowledge.get("met_last:" + other_id, 0.0))
			if Time.get_unix_time_from_system() - last_met > MEET_COOLDOWN_S:
				out.append({"kind": "meet", "key": "meet:" + other_id, "other": other_id,
					"label": ("talk with %s" if mind.knowledge.has("met:" + other_id) else "introduce myself to %s") % MagicSystem.display_name(other_id)})
	# do something TOGETHER with the other mage (Milestone K): she may propose; the other decides for herself
	if main.get("companionship") and _allowed("meet"):
		for other_id in main.mages:
			if other_id == agent_id:
				continue
			var oc2: WorldCharacter = main.characters.get(other_id)
			if oc2 == null or not oc2.visible or me.global_position.distance_to(oc2.global_position) > (60.0 if _night_home() else 35.0):
				continue
			# (a relaunch resuming a shared activity: the shutdown cut it short, its cooldown does not count)
			if Time.get_unix_time_from_system() - float(mind.knowledge.get("together_last:" + other_id, 0.0)) < TOGETHER_COOLDOWN_S \
					and not resume_key.ends_with(":" + other_id):
				continue
			var cands: Array = explore_map.candidates(1) if main.world and me.visible else []
			if not cands.is_empty():
				out.append({"kind": "together", "key": "together:explore:" + other_id, "other": other_id, "sub": "explore_together",
					"target": {"pos": cands[0].pos, "fill": {"place": String(cands[0].describe)}}, "label": "ask %s to explore %s together" % [MagicSystem.display_name(other_id), cands[0].describe]})
			if StreamFlags.fights() and mind.vigor > 0.75 and float(needs.energy) > 0.6 and main.get("duel") and main.streaming.current_id == "sanctuary":
				out.append({"kind": "together", "key": "together:spar:" + other_id, "other": other_id, "sub": "train_together",
					"target": {"pos": SanctuaryTerrain.TRAINING_CENTER_3D, "fill": {}}, "label": "ask %s to spar at the training grounds" % MagicSystem.display_name(other_id)})
			var area_info: Dictionary = WorldState.areas.get(main.streaming.current_id, {})
			# stargazing (Day 2): any open grassy spot under the sky, not only the registry's one spot - with a saved
			# cooldown so it stays special (STARGAZE_GAP_S between two)
			var sg_last := float(mind.activity_counts.get("together:stargaze:" + other_id, {}).get("last_unix", 0))
			var sg_ok := Time.get_unix_time_from_system() - sg_last >= STARGAZE_GAP_S
			if sg_ok and WorldState.night and (float(needs.energy) > 0.25 or _night_home()):
				var sg_pos := Vector3.INF
				var sg_place := "the grass"
				if area_info.has("stargaze_spot") and (rng.randf() < 0.5 or _night_home()):
					var sp: Array = area_info.stargaze_spot
					sg_pos = Vector3(sp[0], 0, sp[1])
					sg_place = String(area_info.get("stargaze_place", "the grass"))
				else:
					sg_pos = _grass_stargaze_spot()
					sg_place = "an open patch of grass"
				if sg_pos != Vector3.INF:
					out.append({"kind": "together", "key": "together:stargaze:" + other_id, "other": other_id, "sub": "stargaze_together",
						"target": {"pos": sg_pos, "fill": {"place": sg_place}},
						"label": "ask %s to lie in the grass and watch the stars" % MagicSystem.display_name(other_id)})
			if (mind.vigor < 0.7 or float(needs.energy) < 0.55) and main.world and main.world.interactables.has("watchpoint_rest"):
				out.append({"kind": "together", "key": "together:rest:" + other_id, "other": other_id, "sub": "rest_together",
					"target": {"pos": main.world.interactables.watchpoint_rest.global_position, "fill": {}}, "label": "ask %s to rest together at the watchpoint" % MagicSystem.display_name(other_id)})
	# journal: after a real stretch of things done, and never again within JOURNAL_GAP_S (Day 2: it was every ~2 min)
	var last_j := float(mind.activity_counts.get("journal", {}).get("last_unix", 0))
	var unwritten_j := mind.activity_seq - int(mind.knowledge.get("journal_cursor", 0))
	if unwritten_j >= 6 and Time.get_unix_time_from_system() - last_j >= JOURNAL_GAP_S and not Journal.compose(mind).is_empty():
		out.append({"kind": "journal", "key": "journal", "label": "write in my journal"})
	# Starfall Hill at night: its spots to wander to (the old tree, the glowing flowers, the view, the roots)
	if _night_home():
		var sp: Dictionary = StarfallPlace.instance.spots()
		for sid in sp:
			if sid == "bed":
				continue
			var s3: Dictionary = sp[sid]
			if (s3.pos as Vector3).distance_to(me.global_position) > 2.0:
				out.append({"kind": "roam", "key": "starfall:" + sid, "pos": s3.pos, "cand": {"describe": String(s3.label), "pos": s3.pos, "score": 0.5, "novelty": 0.3, "off_path": false, "features": {"props": 2, "relief": 0.2, "water": false}},
					"label": "wander over to %s" % String(s3.label)})
	# Levels 1-9 live in their HOME REGION (Day 2, the developer: "living home region, forests, trails, clearings and
	# the library reachable at levels 1 to 9"): by day the sanctuary, the Ancient Spell Library, the Whispering Woods'
	# trails and clearings, the Mentor's Tower; at night home to Starfall Hill. No expeditions beyond it.
	if mind.level() <= 9:
		var home: Array = home_areas()
		var night_now := _night_home() or (WorldState.daylight() < 0.2 and mind.level() <= 9)
		out = out.filter(func(o):
			var a := String(o.get("area", ""))
			if o.kind == "expedition":
				return false
			if a == "" or a == main.streaming.current_id:
				return true
			return home.has(a) and (not night_now or a in ["sanctuary", "lantern_lake"]))
	# ("together" is already gated by _allowed("meet") where it is offered: without it here, no shared activity -
	# stargazing, exploring, sparring, resting together - had been chosen since this filter came in)
	return out.filter(func(o): return _allowed(o.kind) or o.kind in ["recover", "collect", "shelter", "listen_rain", "ascend", "together", "visit", "lakewatch", "discover", "join_find", "revisit", "wander"])


const MEET_COOLDOWN_S := 420.0
const JOURNAL_GAP_S := 900.0
const STARGAZE_GAP_S := 1800.0
const RECENT_KINDS := 12
## The same activity (same option key) again within this many seconds costs utility (fading to nothing); saved via
## mind.activity_counts, so a restart does not reset it.
const KIND_COOLDOWN_S := {"wander": 900.0, "revisit": 1800.0, "journal": 900.0, "attune": 1200.0, "explore": 480.0, "roam": 120.0, "alchemy": 600.0, "rest": 480.0,
	"perform": 900.0, "magic": 300.0, "visit": 600.0, "together": 600.0, "meet": 420.0, "chat": 600.0, "gather": 240.0}
## Kinds that pull harder the longer she has not done them (up to this bonus after ~40 min).
const RARE_PULL := {"research": 0.22, "investigate": 0.25, "gather": 0.22, "hunt": 0.18, "chat": 0.22, "lesson": 0.2,
	"ascend": 0.2, "drill": 0.15, "visit": 0.24, "together": 0.18, "perform": 0.12, "alchemy": 0.1, "converse": 0.12}
const TOGETHER_COOLDOWN_S := 600.0


## Attunements and the knowledge that tells her about them (the interactable's lore source).
const ATTUNE := {"ritual_circle_attune": ["read:scroll_first_circle"], "heartstone_attune": ["read:chamber_tablet", "lore:heartstone"]}


## The open trial an activity (interactable id or struck object) would advance, or {}.
func _open_trial(deed: String) -> Dictionary:
	for tr in WorldState.sanctuary.get("trials", []):
		if mind.trials_done.has(tr.id):
			continue
		if tr.get("activity", "") == deed:
			return tr
		if tr.has("activity_prefix") and deed.begins_with(tr.activity_prefix):
			if not mind.prefix_counts.get(tr.activity_prefix, {}).has(deed):
				return tr
	return {}


func _advances_trial(deed: String) -> bool:
	return not _open_trial(deed).is_empty()


func _book_location(bid: String) -> Dictionary:
	match bid:
		"liber_orbis": return {"interactable": "altar_spellbook", "area": "sanctuary"}
		"scroll_first_circle": return {"interactable": "scroll_first_circle", "area": "sanctuary"}
		"keepers_daybook": return {"interactable": "keepers_daybook", "area": "sanctuary"}
		"chamber_tablet": return {"interactable": "chamber_tablet", "area": "sanctuary"}
		"gate_inscription": return {"interactable": "gate_inscription", "area": "sanctuary"}
		"elementa_prima": return {"interactable": "lectern_warding_glyph", "area": "arcane_library"}
		"signs_and_wakings": return {"interactable": "research_desk", "area": "arcane_library"}
		"on_gathering": return {"interactable": "desk_gathering", "area": "arcane_library"}
	return {}


func score(o: Dictionary) -> Dictionary:
	var u := 0.0
	var why := []
	match o.kind:
		"research":
			u = 0.4 + needs.curiosity * 0.45 + minf(o.unread, 4) * 0.04
			if main.story.next_leads().any(func(l): return l.get("book", "") == o.book):
				u += 0.45
				why.append("story lead +0.45")
			if o.area != main.streaming.current_id:
				u -= 0.18
				why.append("needs travel -0.18")
		"magic":
			u = 0.35 + needs.mastery * 0.5 * (1.0 - minf(float(o.mastery), 3.0) / 3.0)
			if o.novel:
				u += 0.3 * needs.curiosity + 0.1
				why.append("untested reaction")
			if o.get("trial", false):
				u += 0.25
				why.append("advances a trial +0.25")
			u -= (1.0 - needs.energy) * 0.45
		"investigate":
			u = 0.85
			why.append("story lead")
		"explore":
			var last: int = int(mind.activity_counts.get(o.key, {}).get("last_unix", 0))
			var age := minf((Time.get_unix_time_from_system() - last) / 600.0, 1.0) if last > 0 else 1.0
			u = 0.2 + needs.curiosity * 0.35 * age
		"rest":
			u = 0.1 + (1.0 - needs.energy) * 0.95
			if o.interactable == "pond_reflect":
				u -= 0.05
		"alchemy":
			var wants: bool = mind.knowledge.has("recipe:luminous_draught") and int(mind.inventory.get("luminous_draught", 0)) == 0
			u = 0.4 + (0.25 if wants else 0.05) + needs.curiosity * 0.15
		"converse":
			u = 0.55 + needs.social * 0.5
			why.append("visitor present")
		"ascend":
			u = 0.45 + needs.curiosity * 0.35 + 0.25 - (1.0 - needs.energy) * 0.3
			why.append("the bells on the tower's crown, on a night of wind")
		"shelter":
			# nobody stands about in a downpour: this wins over nearly anything that is not urgent
			u = 0.7 + float(main.weather.rain) * 0.5
			why.append("it is raining %s" % ("hard" if main.weather.rain > 0.8 else "steadily"))
		"listen_rain":
			u = 0.45 + (1.0 - needs.energy) * 0.35 + float(main.weather.rain) * 0.2
			why.append("dry, and the rain is all round")
		"chat":
			u = 0.28 + needs.social * 0.5 + (0.12 if o.first else 0.0) - (1.0 - needs.energy) * 0.15
			why.append("someone she %s" % ("has not met yet" if o.first else "likes talking to"))
		"lakewatch":
			u = 1.25
			why.append("the lanterns are why she came")
		"visit":
			var last_v := float(mind.knowledge.get("visited_unix:" + String(o.area), 0.0))
			var age_v := clampf((Time.get_unix_time_from_system() - last_v) / 1800.0, 0.0, 1.0) if last_v > 0.0 else 1.0
			var here_since := float(mind.knowledge.get("arrived_unix", Time.get_unix_time_from_system()))
			var stayed_min := (Time.get_unix_time_from_system() - here_since) / 60.0
			if String(o.area) == "lantern_lake":
				# their second night spot (next to Starfall Hill): some nights, never by day, once a night
				if not WorldState.night or int(mind.knowledge.get("lake_night", -1)) == night_id():
					u = -1.0
				else:
					u = 0.42 + needs.social * 0.25 + (0.35 if main.characters.size() > 1 else 0.0) * rng.randf()
					why.append("a night for the lanterns")
			elif String(o.area) == "sanctuary":
				# home: after a good stretch away, when tired, and always as the day ends
				u = 0.1 + clampf(stayed_min / 12.0, 0.0, 0.55) + (1.0 - needs.energy) * 0.35
				if WorldState.hour_f() >= 17.5 or WorldState.daylight() < 0.35:
					u += 0.9
					why.append("the day is ending: home +0.90")
			else:
				u = 0.18 + needs.curiosity * 0.4 + 0.3 * age_v - (1.0 - needs.energy) * 0.3
				u -= clampf(1.0 - stayed_min / 6.0, 0.0, 1.0) * 0.25        # just arrived somewhere: not straight off again
				if WorldState.hour_f() >= 17.0 or WorldState.daylight() < 0.5:
					u -= 0.6
					why.append("too late to set off -0.60")
				why.append("not been there for a while" if age_v > 0.7 else "been there lately")
		"expedition":
			# a journey of days: wanted when the clue pulls, never when tired or hurt, less at nightfall
			u = 0.3 + needs.curiosity * 0.4 + float(o.get("curiosity", 0.25)) - (1.0 - needs.energy) * 0.5 - (1.0 - mind.vigor) * 0.6
			if WorldState.hour_f() > 17.0 or WorldState.hour_f() < 6.0:
				u -= 0.3
				why.append("too late in the day to set out -0.30")
			why.append("a clue leads there")
		"drill":
			u = 0.3 + needs.mastery * 0.3 + 0.35 - (1.0 - needs.energy) * 0.4 - (1.0 - mind.vigor) * 0.4
			why.append("unfinished business with the %s +0.35" % String(o.get("for", "")).replace("_", " "))
		"lesson":
			u = 0.45 + needs.curiosity * 0.3 + needs.mastery * 0.35 - (1.0 - needs.energy) * 0.2
			var unf := unfinished()
			if not unf.is_empty():
				u += 0.2
				why.append("to be readier for the %s +0.20" % String(unf[0].get("name", "creature")).to_lower())
			if o.first:
				u += 0.25
				why.append("a real teacher, never heard him +0.25")
		"attune":
			u = 0.3 + needs.mastery * 0.3 - (1.0 - needs.energy) * 0.2
			var tr := _open_trial(o.interactable)
			if not tr.is_empty():
				u += 0.35
				why.append("trial: %s +0.35" % tr.name)
			elif o.attuned:
				u -= 0.15
		"hunt":
			var first: bool = not mind.knowledge.has("defeated:" + String(o.monster_kind))
			var risk: float = {"weak": 0.0, "medium": 0.28 if mind.level() < 4 else 0.08, "rare": 0.55 if mind.level() < 8 else 0.2}.get(o.tier, 0.2)
			u = 0.35 + needs.mastery * 0.25 - risk - (1.0 - mind.vigor) * 0.7 - (1.0 - needs.energy) * 0.25 - float(o.distance) * 0.006
			if risk > 0.0:
				why.append("risky -%.2f" % risk)
			if first:
				u += 0.3
				why.append("never beaten one +0.30")
			if o.attacking_me:
				u += 0.65 * mind.vigor
				why.append("it is attacking me")
			elif mind.knowledge.has("unfinished:" + String(o.monster_kind)):
				# not ready: it keeps her away; the readier she has made herself, the more a rematch draws her
				var rd := clampf(readiness(String(o.monster_kind)), 0.0, 1.0)
				var adj := -0.35 + 0.75 * rd
				u += adj
				why.append(("a rematch she has prepared for %+.2f" if rd >= 1.0 else "not ready for it yet (readiness %d%%) %+.2f") % ([adj] if rd >= 1.0 else [int(rd * 100), adj]))
		"discover":
			u = 2.2                     # she has just seen something: nothing ordinary outranks walking over to it
			why.append("just noticed something")
		"join_find":
			u = 1.3
			why.append("the other found something")
		"revisit":
			u = 0.08 + needs.curiosity * 0.18
		"wander":
			u = 0.14 + needs.curiosity * 0.3
			if WorldState.visited_locations.get(String(main.streaming.current_id), 0) <= 2:
				u += 0.12
				why.append("a place she barely knows")
		"roam":
			var cs: Dictionary = o.cand
			u = 0.12 + needs.curiosity * 0.45 + float(cs.score) * 0.3
			why.append("novelty %.2f" % float(cs.novelty))
			if cs.off_path:
				why.append("off the usual paths")
		"perform":
			# leisure after a stretch of work; needs some energy, never when tired out or unsafe
			var since := mind.activity_seq - int(mind.music.get("seq_at_last", 0))
			u = 0.1 + minf(since, 20) * 0.02 + needs.energy * 0.15 - (0.3 if needs.energy < 0.3 else 0.0)
			if o.mode == "special":
				u += 0.35
				why.append("celebrating" if Time.get_unix_time_from_system() < _celebrate_until else "an evening performance")
			if since >= 12:
				why.append("a long stretch of work")
		"gather":
			var new_item: bool = not mind.knowledge.has("material:" + String(o.item))
			u = 0.25 + needs.curiosity * 0.2 + (0.3 if new_item else 0.0) - me.global_position.distance_to((o.node as Node3D).global_position) * 0.01
			if new_item:
				why.append("never gathered one")
		"collect":
			u = 0.7
			why.append("it fell right here")
		"recover":
			u = (1.0 - mind.vigor) * 1.5 + (0.3 if threat and is_instance_valid(threat) and mind.vigor < 0.35 else 0.0)
			why.append("vigor %.0f%%" % (mind.vigor * 100.0))
		"together":
			var relt: Dictionary = mind.knowledge.get("rel:" + String(o.other), {})
			u = 0.32 + needs.social * 0.4 + 0.35 * float(relt.get("camaraderie", 0.0)) - 0.1 * float(relt.get("rivalry", 0.0))
			if String(o.sub) == "explore_together":
				u += 0.15 * needs.curiosity
			if String(o.sub) == "rest_together":
				u += (1.0 - needs.energy) * 0.4
			if String(o.sub) == "train_together":
				u += needs.mastery * 0.3 - 0.1
			if String(o.sub) == "stargaze_together":
				u += 0.2 + 0.25 * (1.0 - needs.energy) + 0.1 * needs.social
				if _night_home():
					u += 0.6                 # their night: lying on Starfall Hill watching the stars, every night
					why.append("night on Starfall Hill +0.6")
				elif mind.knowledge.has("stargazed:" + main.streaming.current_id):
					u -= 0.15
			var declined := float(mind.knowledge.get("declined_by:%s:%s" % [o.other, o.sub], 0.0))
			if Time.get_unix_time_from_system() - declined < 900.0:
				u -= 0.5
				why.append("asked recently, she said no -0.5")
			why.append("companionship")
		"meet":
			var rel: Dictionary = mind.knowledge.get("rel:" + String(o.other), {})
			u = 0.3 + needs.social * 0.45 + 0.15 * float(rel.get("camaraderie", 0.0)) - 0.1 * float(rel.get("rivalry", 0.0))
			# something of her own to tell (a clue, a fight, a worry, something she wants to ask): she goes to say it
			if main.get("companionship"):
				var news: Array = Companionship.topics(agent_id, String(o.other))
				if not news.is_empty() and float(news[0].w) >= 1.0:
					u += 0.25
					why.append("something to tell +0.25")
			if not mind.knowledge.has("met:" + String(o.other)):
				u += 0.2
				why.append("we have never spoken")
		"journal":
			# grows with the number of things done since the last entry: she writes after a meaningful stretch
			var unwritten := mind.activity_seq - int(mind.knowledge.get("journal_cursor", 0))
			u = 0.2 + 0.055 * minf(unwritten, 14)
			if unwritten >= 8:
				why.append("%d things unwritten" % unwritten)
	# at night (Levels 1-9) the hill is where they are: its spots draw her, the ruins' errands wait for the morning
	if _night_home() and o.kind != "together":
		if String(o.key).begins_with("starfall:"):
			u += 0.35
			why.append("night on Starfall Hill +0.35")
		elif not (o.kind in ["recover", "hunt", "collect", "shelter", "meet", "journal"]):
			u -= 0.25
			why.append("night: the ruins can wait -0.25")
	var temper := float(profile.get("temperament", {}).get(o.kind, 1.0))
	if temper != 1.0 and u > 0.0:
		u *= temper
		why.append("temperament x%.2f" % temper)
	# --- variety (Day 2): saved per-activity cooldowns, a longer memory of kinds, and a pull toward what she has
	# not done for a long while (activities that had never been chosen on Day 1)
	var now_v := Time.get_unix_time_from_system()
	var cd := float(KIND_COOLDOWN_S.get(o.kind, 0.0))
	var last_k := float(mind.activity_counts.get(o.key, {}).get("last_unix", 0))
	if cd > 0.0 and last_k > 0.0 and now_v - last_k < cd:
		var pen := 0.6 * (1.0 - (now_v - last_k) / cd)
		u -= pen
		why.append("did this %d min ago -%.2f" % [int((now_v - last_k) / 60.0), pen])
	var long_reps := _recent_kinds.count(o.kind)
	if long_reps >= 3 and not (o.kind in ["hunt", "collect", "recover"]):
		u -= 0.06 * (long_reps - 2)
		why.append("%d of the last %d were %s" % [long_reps, _recent_kinds.size(), o.kind])
	if RARE_PULL.has(o.kind):
		var last_kind := float(mind.activity_counts.get("kind:" + o.kind, {}).get("last_unix", 0))
		var age_k := 1.0 if last_kind <= 0.0 else clampf((now_v - last_kind) / 2400.0, 0.0, 1.0)
		if age_k > 0.3:
			u += float(RARE_PULL[o.kind]) * age_k
			why.append("not done in a while +%.2f" % (float(RARE_PULL[o.kind]) * age_k))
	var kind_reps := _recent_kinds.slice(maxi(0, _recent_kinds.size() - 3)).count(o.kind)
	if o.kind in ["hunt", "collect", "recover"]:
		kind_reps = 0      # a fight is not "the same thing again" while creatures keep coming
	if kind_reps > 0:
		u -= 0.22 * kind_reps
		why.append("same kind recently -%.2f" % (0.22 * kind_reps))
	if _recent_targets.has(o.key):
		u -= 0.55
		why.append("same target recently -0.55")
	if _failures.get(o.key, 0) > 0:
		u -= 0.9
		why.append("failed recently -0.90")
	if o.kind == "magic" and viewer_request.get(o.spell, {}).get("target", "") == o.target:
		u += 0.45
		why.append("a viewer suggested it +0.45")
	if curiosity_bonus.has(o.key):
		u += float(curiosity_bonus[o.key])
		why.append("curiosity proposal +%.2f" % float(curiosity_bonus[o.key]))
	u += rng.randf_range(0.0, 0.06)
	return {"utility": snappedf(u, 0.001), "why": why}


func ranked() -> Array:
	var scored := []
	for o in options():
		scored.append(o.merged(score(o)))
	scored.sort_custom(func(a, b): return a.utility > b.utility)
	return scored


## What the decision layer can see (also served over the bridge as region_context).
func region_context() -> Dictionary:
	var data: Dictionary = WorldState.sanctuary
	var pos := me.global_position
	var here := SanctuaryBrain.sub_area(main.world, pos)
	var subs := []
	for id in data.sub_areas:
		var s: Dictionary = data.sub_areas[id]
		subs.append({"id": id, "name": s.name, "purpose": s.purpose,
			"distance": snappedf(Vector2(pos.x - s.center[0], pos.z - s.center[2]).length(), 0.1) if main.streaming.current_id == "sanctuary" else -1.0})
	return {"region": REGION, "in_region": _in_region(), "story": main.story.describe(), "sub_area": here,
		"sub_area_info": data.sub_areas.get(here, {}).get("purpose", ""), "sub_areas": subs,
		"options": ranked().slice(0, 10).map(func(o): return {"key": o.key, "kind": o.kind, "label": o.label, "utility": o.utility, "why": o.why}),
		"needs": status().needs, "mission": WorldState.mission_state(agent_id), "spells": main.magic.known_spells(agent_id),
		"visitors": main.npcs.nearby(pos, 60.0), "current": current}


# ------------------------------------------------------------------ main loop
func _loop() -> void:
	busy = true
	while enabled and is_inside_tree():
		if hold:
			current = {}
			await get_tree().create_timer(0.3).timeout
			continue
		if main.streaming.state != "idle" or not main.travel.journey.is_empty():
			await get_tree().create_timer(0.5).timeout
			continue
		if main.sim_mode(agent_id) == "background":
			await _background_step()       # her area is not loaded: honest abstract simulation (no free rewards)
			continue
		if is_foreground() and not _in_region():
			current = {"kind": "travel", "label": "return home"}
			await _travel("ritual_sanctuary")
			continue
		if main.curiosity and is_lead() and is_foreground():
			await main.curiosity.consult(self)        # LLM-capable: only for the followed mage
		if resume_key != "":
			curiosity_bonus[resume_key] = float(curiosity_bonus.get(resume_key, 0.0)) + 1.0
		var scored := ranked()
		if resume_key != "":
			print("[resume] %s carries on: %s (%s)" % [agent_id, resume_key, "on offer" if scored.any(func(o): return o.key == resume_key) else "no longer on offer"])
			resume_key = ""
		if scored.is_empty():
			await get_tree().create_timer(2.0).timeout
			continue
		var choice: Dictionary = scored[0]
		curiosity_bonus.clear()
		if choice.kind == "magic":
			viewer_request.erase(choice.spell)
		var now_s := Time.get_ticks_msec() / 1000.0
		for k in viewer_request.keys():
			if now_s - float(viewer_request[k].t) > VIEWER_REQUEST_S:
				viewer_request.erase(k)
		# the choice can take a moment (the curiosity consult is an LLM call): if the show or the other mage asked for her
		# meanwhile, she starts nothing (2026-10-18 live: the show asked for a dance during the consult, she said yes, the
		# music started - and her planner went on to lead Luna off to spar at the training grounds mid-song)
		if hold or not enabled:
			continue
		last_decision = {"key": choice.key, "kind": choice.kind, "label": choice.label, "utility": choice.utility, "why": choice.why,
			"alternatives": scored.slice(1, 4).map(func(x): return [x.label, x.utility])}
		decided.emit(last_decision)
		_private_thought("I'll %s." % choice.label)
		current = {"kind": choice.kind, "label": choice.label, "key": choice.key, "stage": "starting", "started": snappedf(Time.get_ticks_msec() / 1000.0, 0.1)}
		var t0 := Time.get_ticks_msec()
		var result: Dictionary = await run_activity(choice)
		if _cancel:
			break
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		WorldState.note_activity(choice.key, agent_id)
		WorldState.note_activity("kind:" + choice.kind, agent_id)
		_recent_kinds.append(choice.kind)
		_recent_targets.append(choice.key)
		if _recent_kinds.size() > RECENT_KINDS:
			_recent_kinds.pop_front()
		if _recent_targets.size() > 8:
			_recent_targets.pop_front()
		mind.knowledge["recent_kinds"] = _recent_kinds.duplicate()        # saved with her mind
		mind.knowledge["recent_targets"] = _recent_targets.duplicate()
		for k in _failures.keys():
			_failures[k] -= 1
			if _failures[k] <= 0:
				_failures.erase(k)
		if not result.get("ok", false):
			_failures[choice.key] = 3
		needs.social = clampf(needs.social + 0.05, 0.0, 1.0)
		needs.curiosity = clampf(needs.curiosity + 0.04, 0.0, 1.0)
		needs.mastery = clampf(needs.mastery + 0.05, 0.0, 1.0)
		history.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "kind": choice.kind, "label": choice.label, "utility": choice.utility,
			"ok": result.get("ok", false), "seconds": snappedf(secs, 0.1), "detail": str(result.get("detail", "")).left(110)})
		if history.size() > 150:
			history.pop_front()
		current = {}
		if main.curiosity and is_lead():
			main.curiosity.on_activity_finished(choice, result)
		await get_tree().create_timer(rng.randf_range(0.8, 2.4)).timeout
	busy = false


# ------------------------------------------------------------------ activities
func run_activity(o: Dictionary) -> Dictionary:
	_interrupt = ""
	match o.kind:
		"research": return await _research(o)
		"magic": return await _magic(o)
		"investigate": return await _investigate(o)
		"explore": return await _explore(o)
		"rest": return await _rest(o)
		"alchemy": return await _use("alchemy_table")
		"lesson": return await _use(String(o.interactable))
		"drill": return await _drill(o)
		"expedition": return await _expedition(o)
		"visit": return await _visit(o)
		"lakewatch": return await _lakewatch(o)
		"chat": return await _chat(o)
		"shelter": return await _shelter(o)
		"ascend": return await _ascend(o)
		"listen_rain": return await _listen_rain()
		"converse": return await _converse(o)
		"journal": return await _journal()
		"attune": return await _attune(o)
		"hunt": return await _hunt(o)
		"collect": return await _collect(o.loot)
		"recover": return await _recover()
		"meet": return await main.mage_talk.meet(self, String(o.other))
		"together":
			mind.knowledge["together_last:" + String(o.other)] = Time.get_unix_time_from_system()
			return await main.companionship.invite(self, String(o.other), String(o.sub), o.target)
		"roam": return await _roam(o)
		"gather": return await _gather(o)
		"perform": return await _perform(o)
		"discover":
			var res := await _use(String(o.interactable))
			if main.get("discoveries"):
				var e: Dictionary = main.discoveries.on_found(agent_id, res)
				if not e.is_empty():
					res["find"] = e
			return res
		"join_find": return await _join_find(o)
		"revisit": return await _use(String(o.interactable))
		"wander": return await _wander(o)
	return {"ok": false, "detail": "unknown activity"}


func _research(o: Dictionary) -> Dictionary:
	if main.streaming.current_id != o.area:
		current.stage = "travelling to the library"
		var j := await _travel("ancient_spell_library" if o.area == "arcane_library" else "ritual_sanctuary")
		if not j.get("ok", false):
			return {"ok": false, "detail": "could not reach %s" % o.area}
	current.stage = "reading"
	var r := await _use(o.interactable)
	var reading: Dictionary = r.get("reading", {})
	var learned: Array = reading.get("learned", [])
	needs.curiosity = clampf(needs.curiosity - 0.08 * reading.get("pages_read", []).size(), 0.0, 1.0)
	needs.energy = clampf(needs.energy - 0.04, 0.0, 1.0)
	if learned.any(func(k): return String(k).begins_with("incantation:")):
		needs.mastery = clampf(needs.mastery + 0.25, 0.0, 1.0)   # a new incantation makes her want to try it
		_maybe_say(["I want to try that incantation for real.", "Reading it is one thing. Now I should practise it."], 0.6)
	# (Day 2: she stays a while in the library - more to read, a look round - and walks home with the day's end or
	# when she has had enough; the "visit" option home takes her back)
	return r


## Several real attempts while she is improving; stops when the goal effect happens, when she tires,
## or after a refused cast.
func _magic(o: Dictionary) -> Dictionary:
	var goal := ""
	if o.spell == "wind_gust" and String(o.target).begins_with("brazier"):
		goal = "extinguished"
	var attempts := 0
	var res := {}
	var effects := []
	while attempts < 3 and not _cancel:
		attempts += 1
		current.stage = "attempt %d" % attempts
		if not await _stand_for_cast(o.spell, o.target):
			return {"ok": false, "detail": "no clear casting position for %s" % o.target}
		res = await main.magic.cast(me, o.spell, o.target)
		if res.get("outcome", "") == "refused":
			return {"ok": false, "detail": res.get("reason", "refused")}
		effects.append(res.get("effect", "none"))
		needs.energy = clampf(needs.energy - 0.07, 0.0, 1.0)
		needs.mastery = clampf(needs.mastery - 0.08, 0.0, 1.0)
		_react_to_result(res, attempts, goal)
		if goal == "" or res.get("effect", "") == goal or needs.energy < 0.3 or _interrupt != "":
			break
		await get_tree().create_timer(rng.randf_range(1.5, 3.0)).timeout
	res["attempts"] = attempts
	res["effects"] = effects
	res["ok"] = res.get("outcome", "") in ["hit", "self"]
	res["detail"] = "%d attempt(s): %s" % [attempts, ", ".join(effects)]
	return res


func _react_to_result(res: Dictionary, attempt: int, goal: String) -> void:
	var eff := String(res.get("effect", ""))
	var ch: Dictionary = res.get("changes", {})
	var first_time: bool = ch.keys().any(func(k): return String(k).begins_with("knowledge.reaction:") and ch[k][0] == 0)
	if goal != "" and eff != goal and eff in ["flicker", "guttered"] and attempt >= 2:
		_maybe_say(["Ha, still not enough. Breathe out first, then the words.", "Closer. Not there yet."] if mind.knowledge.has("fact:breath_before_word") else ["Ha, it barely moved. My gust needs more practice.", "Not enough. Again."], 0.8)
	elif first_time and eff == "extinguished":
		_maybe_say(["It went out! The gust was strong enough this time."], 1.0)
	elif first_time:
		var lines := {"surge": ["The water stood up! Just for a moment."], "shattered": ["It shattered. I'll let it grow back."],
			"revealed": ["There it is. A sign, woken."], "pattern_reflection": ["Seven points. The same shape as the gate sign."],
			"awakened": ["Three beats. It's awake."], "arcane_flame": ["Blue fire. That's beautiful."]}
		if lines.has(eff):
			_maybe_say(lines[eff], 1.0)


func _investigate(o: Dictionary) -> Dictionary:
	current.stage = "following a lead"
	_private_thought("Lead: %s" % o.label)
	if String(o.spell) != "":
		return await _magic({"spell": o.spell, "target": o.target, "kind": "magic", "key": o.key})
	return {"ok": false, "detail": "no way to follow this lead yet"}


func _explore(o: Dictionary) -> Dictionary:
	var sub: Dictionary = WorldState.sanctuary.sub_areas[o.sub_area]
	var c := Vector3(sub.center[0], 0, sub.center[2])
	c.y = main.world.ground_at(c.x, c.z) if main.world.has_method("ground_at") else 0.0
	current.stage = "walking to the %s" % sub.name
	var map := me.get_world_3d().navigation_map
	var dest := NavigationServer3D.map_get_closest_point(map, c + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)))
	if not await _walk(dest):
		return {"ok": false, "detail": "could not reach the %s" % sub.name}
	current.stage = "looking around"
	var pois := []
	for id in main.world.points_of_interest:
		var p: Vector3 = main.world.points_of_interest[id].position
		if p.distance_to(me.global_position) < float(sub.radius) + 4.0 and not String(id).begins_with("gate:"):
			pois.append(p)
	pois.shuffle()
	var looked := 0
	for p in pois.slice(0, rng.randi_range(2, 4)):
		me.look_at_point(p + Vector3(0, 1.0, 0))
		me.look_head_at(p + Vector3(0, 1.0, 0))
		await get_tree().create_timer(rng.randf_range(2.0, 4.0)).timeout
		looked += 1
	me.look_head_at(null)
	var lines: Array = WorldState.sanctuary.thoughts.get(o.sub_area, [])
	if not lines.is_empty():
		_private_thought(lines[rng.randi() % lines.size()])
	needs.curiosity = clampf(needs.curiosity - 0.12, 0.0, 1.0)
	needs.energy = clampf(needs.energy - 0.03, 0.0, 1.0)
	for id in ["gate_inscription", "chamber_tablet"]:
		var it = main.world.interactables.get(id)
		if it and it.global_position.distance_to(me.global_position) < 9.0 and BookLibrary.pages_read(it.book_id, agent_id).is_empty():
			await _use(id)
	# standing at the Watchpoint for the first time: actually survey the realm from it (the plaque is right there)
	var survey = main.world.interactables.get("watchpoint_survey")
	if survey and o.sub_area == "watchpoint" and not mind.knowledge.has("survey:realm") and survey.global_position.distance_to(me.global_position) < 9.0:
		current.stage = "surveying the realm"
		await _use("watchpoint_survey")
	return {"ok": true, "detail": "looked at %d places in the %s" % [looked, sub.name]}


func _perform(o: Dictionary) -> Dictionary:
	current.stage = "performing"
	var r: Dictionary = await main.performance.perform(agent_id, String(o.mode))
	mind.music["seq_at_last"] = mind.activity_seq
	if String(o.mode) == "special" and r.get("ok", false):
		mind.music["last_special_unix"] = int(Time.get_unix_time_from_system())
	if r.get("ok", false):
		needs.energy = clampf(needs.energy + 0.1, 0.0, 1.0)      # it was relaxing
		needs.curiosity = clampf(needs.curiosity + 0.1, 0.0, 1.0)
	return r


## Walk (real navigation) to a spot she chose out of curiosity, look at what is actually there, notice
## things nearby, remember the place if something was there.
func _roam(o: Dictionary) -> Dictionary:
	var c: Dictionary = o.cand
	var dest: Vector3 = o.pos
	current.stage = "heading for %s" % c.describe
	me.look_head_at(dest + Vector3(0, 0.8, 0))
	await get_tree().create_timer(0.6).timeout
	if not await _walk(dest):
		return {"ok": false, "detail": "could not get to %s" % c.describe}
	current.stage = "looking around"
	# look at the things that are really there (solid props near the spot, the water's edge)
	var targets := []
	var space := me.get_world_3d().direct_space_state
	var sq := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 4.0
	sq.shape = sph
	sq.transform = Transform3D(Basis.IDENTITY, me.global_position + Vector3(0, 1.0, 0))
	sq.collision_mask = 1
	for h in space.intersect_shape(sq, 12):
		var col = h.collider
		if col is Node3D and col is StaticBody3D and not (col as Node).is_in_group("cat_terrain") and col != me:
			targets.append((col as Node3D).global_position)
	for r in main.magic.reactives().values():
		if (r as ReactiveElement).kind == "water" and (r as ReactiveElement).global_position.distance_to(me.global_position) < 10.0:
			targets.append((r as ReactiveElement).global_position)
	# what is in front of her, scanned in one direction (left to right or right to left): looking from one side to
	# the other and back read as her head swinging back and forth
	var fwd := -me.global_transform.basis.z
	var bearing := func(p: Vector3) -> float:
		var d := p - me.global_position
		return rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(d.x, d.z)))
	targets = targets.filter(func(p): return absf(bearing.call(p)) < 75.0)
	targets.shuffle()
	if targets.is_empty():
		for k in 2:
			var a := rng.randf_range(-0.9, 0.9)
			targets.append(me.global_position + fwd.rotated(Vector3.UP, a) * 6.0)
	targets = targets.slice(0, rng.randi_range(2, 3))
	var dir_sign := 1.0 if rng.randf() < 0.5 else -1.0
	targets.sort_custom(func(a, b): return dir_sign * bearing.call(a) < dir_sign * bearing.call(b))
	var looked := 0
	for p in targets:
		me.look_head_at((p as Vector3) + Vector3(0, 0.6, 0))
		await get_tree().create_timer(rng.randf_range(2.2, 3.6)).timeout
		looked += 1
	me.look_head_at(null)
	var noticed := perceive()
	explore_map.mark(me.global_position)
	needs.curiosity = clampf(needs.curiosity - 0.15, 0.0, 1.0)
	needs.energy = clampf(needs.energy - 0.03, 0.0, 1.0)
	var res := {"ok": true, "detail": "looked around %s (%d things%s)" % [c.describe, looked, (", noticed " + ", ".join(noticed)) if not noticed.is_empty() else ""],
		"pos": [snappedf(dest.x, 0.1), snappedf(dest.y, 0.1), snappedf(dest.z, 0.1)], "off_path": c.off_path, "features": c.features, "noticed": noticed}
	if ExplorationMap.notable(c.features):
		res["changes"] = WorldState.record_activity({"id": "roam:%s:%s" % [main.streaming.current_id, ExplorationMap.cell_key(dest)], "verb": "explore", "label": "Looked at %s" % c.describe},
			{"knowledge": {"place:%s:%s" % [main.streaming.current_id, ExplorationMap.cell_key(dest)]: 1}}, agent_id)
	last_roam = res
	return res


## The other mage found something: walk over, stand beside it, look.
func _join_find(o: Dictionary) -> Dictionary:
	var p: Vector3 = o.pos
	var side := (me.global_position - p)
	side.y = 0.0
	var stand := p + (side.normalized() if side.length() > 0.2 else Vector3.BACK) * 2.2
	if not await _walk(NavigationServer3D.map_get_closest_point(me.get_world_3d().navigation_map, stand)):
		return {"ok": false, "detail": "could not get over there"}
	me.look_head_at(p + Vector3(0, 0.6, 0))
	await get_tree().create_timer(4.0).timeout
	me.look_head_at(null)
	return {"ok": true, "detail": "went to see the find"}


## Off the paths: a walk to somewhere she has not been, 18-35 m away. Now and then she takes a wrong turn and is a
## little lost for a while (looks around, says so, works out the way back) - a real walk there and back, never a jump.
func _wander(_o: Dictionary) -> Dictionary:
	var map: RID = me.get_world_3d().navigation_map
	var best = null
	var best_s := -1e9
	for i in 16:
		var want := me.global_position + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(18.0, 35.0)
		var p := NavigationServer3D.map_get_closest_point(map, want)
		if p.distance_to(Vector3(want.x, p.y, want.z)) > 3.0 or p.distance_to(me.global_position) < 12.0:
			continue
		var s := rng.randf() * 0.4
		if explore_map and explore_map.off_path(p):
			s += 1.0
		if explore_map and not explore_map.grid().has(ExplorationMap.cell_key(p)):
			s += 0.6
		if s > best_s:
			best_s = s
			best = p
	if best == null:
		return {"ok": false, "detail": "nowhere new to wander"}
	var start := me.global_position
	current.stage = "wandering off the path"
	if not await _walk(best):
		return {"ok": false, "detail": "the way petered out"}
	if explore_map:
		explore_map.mark(me.global_position)
	if rng.randf() < 0.3:
		# a wrong turn: one more stretch further on, then she realises she doesn't know where she is
		var on := NavigationServer3D.map_get_closest_point(map, me.global_position + (me.global_position - start).normalized() * rng.randf_range(10.0, 18.0))
		await _walk(on)
		lost = true
		current.stage = "a little lost"
		_maybe_say(_lines("lost", ["Hm. I don't think I've been this way before...", "Wait - which way did we come from?", "I may have taken a wrong turn. Just a small one."]), 1.0, "lost")
		me.play_gesture("look_around")
		await get_tree().create_timer(rng.randf_range(20.0, 40.0)).timeout
		current.stage = "finding the way back"
		await _walk(NavigationServer3D.map_get_closest_point(map, start))      # back the way she came, on foot
		lost = false
		return {"ok": true, "detail": "wandered off, got a little lost and found the way back", "lost": true}
	return {"ok": true, "detail": "wandered off the path"}


func _rest(o: Dictionary) -> Dictionary:
	var it: Interactable = main.world.interactables.get(o.interactable)
	if it == null:
		return {"ok": false, "detail": "no %s here" % o.interactable}
	var deficit: float = 1.0 - needs.energy
	it.duration_override = clampf(12.0 + deficit * 50.0, 10.0, 60.0)   # a real rest takes as long as she needs
	current.stage = "resting %.0f s" % it.duration_override
	var r := await _use(o.interactable)
	if r.get("ok", false):
		needs.energy = clampf(needs.energy + 0.35 + deficit * 0.3, 0.0, 1.0)
		needs.curiosity = clampf(needs.curiosity + 0.15, 0.0, 1.0)
	return r


func _attune(o: Dictionary) -> Dictionary:
	current.stage = "attuning"
	var r := await _use(o.interactable)
	if r.get("ok", false):
		needs.mastery = clampf(needs.mastery - 0.15, 0.0, 1.0)
		needs.energy = clampf(needs.energy - 0.03, 0.0, 1.0)
	return r


func _converse(o: Dictionary) -> Dictionary:
	var npc = main.npcs.present.get(o.npc)
	if npc == null or not is_instance_valid(npc):
		return {"ok": false, "detail": "they left"}
	current.stage = "walking over to %s" % main.dialogue.travellers[o.npc].name
	var to: Vector3 = npc.global_position + (me.global_position - npc.global_position).normalized() * 1.6
	await _walk(to)
	current.stage = "talking"
	var r: Dictionary = await main.dialogue.converse(o.npc, me)
	_talked_this_visit[o.npc + str(main.dialogue.state_of(o.npc).visits)] = true
	needs.social = clampf(needs.social - 0.4, 0.0, 1.0)
	return r


func _journal() -> Dictionary:
	var it: Interactable = main.world.interactables.get("mika_journal") if is_lead() else null
	if it == null and is_lead():
		return {"ok": false, "detail": "the journal is in the sanctuary"}
	if it:
		await _walk(_stand_at(it))
		if not is_instance_valid(it):
			return {"ok": false, "detail": "the journal is in the sanctuary"}      # (a journey unloaded it mid-walk)
	var entry := Journal.compose(mind)
	if entry.is_empty():
		return {"ok": false, "detail": "nothing new to write"}
	current.stage = "writing"
	if it:
		me.look_at_point(it.global_position)
		me.look_head_at(it.global_position + Vector3(0, 0.75, 0))
	else:
		me.look_head_at(me.global_position + -me.global_transform.basis.z * 0.5 + Vector3(0, 1.0, 0))   # her own notebook
	await get_tree().create_timer(clampf(String(entry.text).split(" ").size() / 2.5, 4.0, 14.0)).timeout
	var j: Array = mind.knowledge.get("journal", []).duplicate()
	j.append({"heading": entry.heading, "text": entry.text, "unix": int(Time.get_unix_time_from_system())})
	mind.knowledge["journal"] = j
	mind.knowledge["journal_cursor"] = entry.cursor
	var ch := WorldState.record_activity({"id": "journal_write", "verb": "write", "label": entry.heading}, {}, agent_id)
	me.look_head_at(null)
	return {"ok": true, "detail": "wrote %s: %s" % [entry.heading, String(entry.text).left(80)], "entry": entry, "changes": ch}


# ------------------------------------------------------------------ combat
## The spell she trusts most against a creature: her signature spell first, then whichever castable spell
## hits hardest (damage x her power with it), ignoring spells that cannot reach creatures.
func combat_spell() -> String:
	var best := ""
	var best_v := -1.0
	for sp in main.magic.known_spells(agent_id):
		if not sp.castable or sp.id in ["elemental_charge", "rune_activation"]:
			continue
		var d := MagicSystem.spell(sp.id)
		var kinds: Array = d.get("target_kinds", ["*"])
		if not kinds.has("*"):
			continue
		var v := float(d.get("damage", 0.5)) * float(sp.power) + (0.25 if sp.id == profile.get("signature_spell", "") else 0.0)
		if v > best_v:
			best_v = v
			best = sp.id
	return best


## Called by the spawner when a creature strikes her: she stops what she is walking to and decides again.
var _sight_t := 2.0

## Milestone K8: a creature seen in the distance is remembered (bestiary knowledge, an activity) and can be talked
## about, without a fight. Hunting records the same key, so nothing is counted twice.
func _notice_creatures() -> void:
	if me == null or main.get("spawner") == null or not me.visible:
		return
	for mon in main.spawner.perceived_by(me, 34.0):
		var m := mon as Monster
		if m == null or not m.alive() or mind.knowledge.has("bestiary:" + m.kind):
			continue
		WorldState.record_activity({"id": "sight:" + m.kind, "verb": "observe", "label": "Saw a %s" % m.def.name},
			{"knowledge": {"bestiary:" + m.kind: 1}}, agent_id)
		_maybe_say(_lines("first_sight", ["What is that?", "Something is moving out there."]), 0.9, "first_sight")


func on_threat(m: Monster) -> void:
	threat = m
	if current.get("kind", "") not in ["hunt", "recover"]:
		_interrupt = "threat"


func _monster(id: String) -> Monster:
	if main.spawner == null:
		return null
	for m in main.spawner.alive:
		if is_instance_valid(m) and m.id == id:
			return m
	return null


func _hunt(o: Dictionary) -> Dictionary:
	var m := _monster(o.monster)
	if m == null or not m.alive():
		return {"ok": false, "detail": "it was already gone"}
	var spell := combat_spell()
	if spell == "":
		return {"ok": false, "detail": "no spell that can reach a creature"}
	if not mind.knowledge.has("bestiary:" + m.kind):
		WorldState.record_activity({"id": "sight:" + m.kind, "verb": "observe", "label": "Saw a %s" % m.def.name}, {"knowledge": {"bestiary:" + m.kind: 1}}, agent_id)
		_maybe_say(_lines("first_sight", ["What is that?", "Something is moving out there."]), 0.9, "first_sight")
	# a strong creature and an unlocked form: an Orbit Surge first (the short sequence), if not already
	if m.tier() in ["medium", "rare"] and main.transformer and main.transformer.can_surge(agent_id) and mind.vigor > 0.4:
		current.stage = "calling an Orbit Surge"
		await main.transformer.surge(agent_id)
		if not is_instance_valid(m) or not m.alive():
			return {"ok": true, "detail": "it was gone when she finished transforming"}
	# Milestone J: a tactical loop. Each beat she decides from what she perceives (CombatTactics) and
	# Godot executes it: dodges are real movement, casts go through the truthful spell pipeline.
	me.set_combat_stance(true)
	var st := {"casts": 0, "hits": 0, "dodges": 0, "dodged": 0, "struck": 0, "signature": 0, "assists": 0, "intents": {}, "wards": 0, "spells": {}, "effects": {}}
	var t_fight := Time.get_ticks_msec()
	while is_instance_valid(m) and m.alive() and int(st.casts) < 12 and not _cancel and Time.get_ticks_msec() - t_fight < 90000:
		if m.mstate == "fleeing":
			st["fled"] = true             # it is running from them (the fire): let it go
			break
		if me.reaction and me.reaction.active and me.reaction.tier in ["stagger", "down"]:
			# knocked off her feet: nothing to decide until she is up again (BodyReaction owns her body)
			current.stage = "recovering (%s)" % me.reaction.phase
			st["knocked"] = int(st.get("knocked", 0)) + (1 if me.reaction.phase == "falling" and int(st.get("_kf", -1)) != me.reaction._seq else 0)
			st["_kf"] = me.reaction._seq
			await get_tree().physics_frame
			continue
		var dec := CombatTactics.decide(self, me, m, spell)
		var intent: String = dec.intent
		st.intents[intent] = int(st.intents.get(intent, 0)) + 1
		current.stage = "%s (%s)" % [intent.replace("_", " "), dec.get("why", "")]
		_note_tactic(dec)
		match intent:
			"dodge":
				st.dodges += 1
				var hz: AttackHazard = dec.hazard
				if hz and not hz.resolved.is_connected(_on_dodge_resolved):
					hz.resolved.connect(_on_dodge_resolved.bind(st))
				await me.dodge(dec.to)
				if is_instance_valid(m):
					me.look_at_point(m.global_position)
			"brace":
				me.play_gesture("brace", 0.06, 0.3)
				await get_tree().create_timer(0.4).timeout
			"hold":
				# her ward is up: stand, face the bolt, let the ward answer it
				if bool(dec.get("turn", false)):
					me.look_at_point(dec.face)
				await get_tree().create_timer(0.12).timeout
			"ward":
				# her family's defence, a real one: the bolt is judged against the ward when it arrives
				var wid := String(dec.spell)
				var wres: Dictionary = await main.magic.cast(me, wid)
				st.wards += 1
				st.spells[wid] = int(st.spells.get(wid, 0)) + 1
				if wres.get("ok", false):
					_note_cooldown(wid)
					_maybe_say(_lines("ward", ["Not this time."]), 0.35, "ward")
			"retreat":
				me.set_combat_stance(false)
				_maybe_say(_lines("retreat", ["Too much. I need to step back.", "Back to the circle."]), 1.0, "retreat")
				_remember_unfinished(m)
				await _recover()
				return {"ok": false, "detail": "withdrew to the circle after %d cast(s), %d hit(s), %d dodge(s)" % [st.casts, st.hits, st.dodges], "tactics": st}
			"assist":
				st.assists += 1
				m = dec.monster
				_maybe_say(_lines("assist", ["I've got this one!", "Hold on, I'm coming!"]), 0.7, "assist")
				# switching targets takes a moment (and must never spin: with several foes on two mages the
				# assist choice can alternate - without a frame the game froze)
				await get_tree().create_timer(0.15).timeout
			"keep_distance", "approach", "reposition":
				await _move_alert(dec.to, 2.5)
			"steady":
				await get_tree().create_timer(0.8).timeout
			"cast":
				var res: Dictionary
				var sig := SignatureCast.can(main, agent_id, m)
				if sig.ok and m.tier() != "weak" and (bool(dec.get("opening", false)) or m.hp > m.max_hp * 0.5) and rng.randf() < 0.7:
					res = await SignatureCast.perform(main, me, m)
					st.signature += 1
				else:
					var sp := String(dec.get("spell", spell))
					res = await main.magic.cast(me, sp, m.id)
					st.spells[sp] = int(st.spells.get(sp, 0)) + 1
					if res.get("ok", false):
						_note_cooldown(sp)
				st.casts += 1
				needs.energy = clampf(needs.energy - 0.04, 0.0, 1.0)
				var eff := String(res.get("effect", ""))
				if eff != "":
					st.effects[eff] = int(st.effects.get(eff, 0)) + 1
				if eff == "bound":
					_maybe_say(_lines("bind", ["Hold still!"]), 0.8, "bind")
				elif eff == "dazed":
					_maybe_say(_lines("rift", ["Stand there, then."]), 0.6, "rift")
				if res.get("outcome", "") == "hit":
					st.hits += 1
				elif res.get("outcome", "") == "refused":
					await get_tree().create_timer(0.4).timeout
				await get_tree().create_timer(rng.randf_range(0.15, 0.45)).timeout
			_:
				await get_tree().create_timer(0.3).timeout
	me.set_combat_stance(false)
	threat = null
	if not is_instance_valid(m) or not m.alive():
		_remember_overcome(String(o.get("monster_kind", "")))
		needs.mastery = clampf(needs.mastery - 0.2, 0.0, 1.0)
		me.play_gesture("victory_nod", 0.3, 0.5)
		me.set_expression("happy", 0.6)
		get_tree().create_timer(2.0).timeout.connect(func(): me.set_expression("happy", 0.0))
		_maybe_say(_lines("victory", ["Got it.", "That's done. Breathe."]), 0.8, "victory")
		await get_tree().create_timer(1.2).timeout
		var picked := 0
		var tries_loot := []
		for l in LootPickup.all_in(main.world):
			if not l.claimed and me.global_position.distance_to(l.global_position) < 10.0:
				var cr: Dictionary = await _collect(l)
				tries_loot.append(String(cr.get("detail", "")))
				if cr.get("ok", false):
					picked += 1
		return {"ok": true, "detail": "won after %d cast(s), %d hit(s), %d dodge(s); picked up %d thing(s)" % [st.casts, st.hits, st.dodges, picked],
			"hits": st.hits, "loot": tries_loot, "tactics": st}
	if st.get("fled", false):
		me.set_combat_stance(false)
		return {"ok": true, "detail": "it fled after %d cast(s), %d hit(s)" % [st.casts, st.hits], "hits": st.hits, "tactics": st, "fled": true}
	return {"ok": false, "detail": "%d cast(s), %d hit(s); it is still there" % [st.casts, st.hits], "hits": st.hits, "tactics": st}


## V3 Part 5 (experiences lead to future actions): a creature she had to withdraw from is UNFINISHED BUSINESS in
## her own mind - what it was, when, how strong she was then. Until she is readier (a level higher, or a lesson /
## a new ward since) her planner keeps her away from it and leans toward getting ready (wards, lessons); once she
## is, a rematch is attractive. Beating it closes the episode ("overcame:<kind>"), and both are things she can tell
## her companion about. Nothing is scripted: the scores move, her own choices do the rest.
func _remember_unfinished(m: Monster) -> void:
	if m == null or not is_instance_valid(m):
		return
	var k := "unfinished:" + m.kind
	var prev: Dictionary = mind.knowledge.get(k, {}) if mind.knowledge.get(k) is Dictionary else {}
	mind.knowledge[k] = {"kind": m.kind, "name": String(m.def.get("name", m.kind)), "at": WorldState.clock_text(), "world_min": WorldState.world_min,
		"level": mind.level(), "lessons": _lessons_heard(), "wards": _ward_mastery(), "times": int(prev.get("times", 0)) + 1}
	_private_thought("That %s was too much for me. Next time I'll be ready for it." % String(m.def.get("name", m.kind)).to_lower())


func _remember_overcome(kind: String) -> void:
	var k := "unfinished:" + kind
	if kind == "" or not mind.knowledge.has(k):
		return
	var u: Dictionary = mind.knowledge[k] if mind.knowledge[k] is Dictionary else {}
	mind.knowledge.erase(k)
	mind.knowledge["overcame:" + kind] = {"kind": kind, "name": String(u.get("name", kind)), "at": WorldState.clock_text(), "after": int(u.get("times", 1)), "first_at": String(u.get("at", ""))}
	_private_thought("I beat the %s this time. I was ready." % String(u.get("name", kind)).to_lower())


## Walk up to a resident and talk: they turn to her and say what is on their mind (their own voice), she answers;
## what they tell or give her is hers (data/residents.json "talk").
func _chat(o: Dictionary) -> Dictionary:
	var rr = main.town.residents.get(String(o.resident)) if main.get("town") else null
	if rr == null or not is_instance_valid(rr) or not rr.visible:
		return {"ok": false, "detail": "they are not here any more"}
	var to: Vector3 = rr.global_position + (me.global_position - rr.global_position).normalized() * 1.7
	if not await _walk(to):
		return {"ok": false, "detail": "could not get to %s" % String(rr.data.get("name", ""))}
	me.look_at_point(rr.global_position)
	rr.notice(me, false)
	rr.state = "talking"
	rr._face_yaw = atan2(me.global_position.x - rr.global_position.x, me.global_position.z - rr.global_position.z)
	rr.play("talk", 0.3)
	me.look_head_at(rr.global_position + Vector3(0, 1.6, 0))
	var tp: Dictionary = o.topic
	await main.voice.say(String(rr.data.get("voice", rr.id)), String(tp.line), {"max_wait": 2.5})
	await get_tree().create_timer(0.3).timeout
	await main.voice.say(_voice(), String(tp.reply), {"max_wait": 2.5, "mood": "happy"})
	me.look_head_at(null)
	var eff: Dictionary = (tp.get("effects", {}) as Dictionary).duplicate(true)
	var know: Dictionary = eff.get_or_add("knowledge", {})
	know["talked:%s:%s" % [rr.id, String(tp.id)]] = 1
	know["met_resident:" + rr.id] = 1
	var changes := WorldState.record_activity({"id": "chat:" + rr.id, "verb": "talk", "label": "Talked with %s" % String(rr.data.get("name", ""))}, eff, agent_id)
	rr.state = "at:" + String(rr.activity)
	rr._begin_activity()
	return {"ok": true, "detail": "talked with %s: %s" % [String(rr.data.get("name", "")), String(tp.id)], "changes": changes}


## Set out on foot (JourneyDirector: real legs, waypoints, camps, nights) with Luna, for the reason the clue gave.
## Rising Air to a place no stair reaches: walk to where the air can take her from, rise, do what she came for
## (the Crown's bells), drift back down to where she rose from.
func _ascend(o: Dictionary) -> Dictionary:
	var rs: Dictionary = o.spot
	current.stage = "making her way to where she can rise from"
	if not await _walk(rs.foot):
		return {"ok": false, "detail": "could not reach the place to rise from"}
	var t0 := Time.get_ticks_msec()
	while me.global_position.distance_to(rs.foot) > 0.6 and Time.get_ticks_msec() - t0 < 5000 and not _cancel:
		me.navigate_to(rs.foot)
		await get_tree().process_frame
	me.stop_action()
	await get_tree().create_timer(0.4).timeout
	# up stage by stage (each lift is within what the air can carry her), then the same way back down
	var stages: Array = rs.get("stages", [rs.top])
	var up := {"ok": true, "height": 0.0, "stages": []}
	var h0 := me.global_position.y
	for i in stages.size():
		current.stage = "rising to %s (%d/%d)" % [String(rs.label), i + 1, stages.size()]
		var st: Dictionary = await main.magic.rise_to(me, stages[i])
		(up.stages as Array).append(st)
		if not st.get("ok", false):
			up["ok"] = false
			up["reason"] = st.get("reason", "?")
			break
		await get_tree().create_timer(0.8).timeout
	up["height"] = snappedf(me.global_position.y - h0, 0.1)
	if not up.ok:
		var back: Array = [rs.foot] if (up.stages as Array).size() > 1 else []
		for b in back:
			await main.magic.rise_to(me, b)
		return {"ok": false, "detail": "Rising Air refused: %s" % String(up.get("reason", "?")), "rise": up}
	var what := {}
	if String(rs.purpose) == "crown" and main.world.get("crown"):
		current.stage = "listening to the bells"
		await get_tree().create_timer(1.0).timeout
		what = await main.world.crown.listen(me, main)
	await get_tree().create_timer(2.5).timeout
	current.stage = "drifting back down"
	var way_down: Array = stages.slice(0, stages.size() - 1)
	way_down.reverse()
	way_down.append(rs.foot)
	var down := {"ok": true}
	for wd in way_down:
		var dd: Dictionary = await main.magic.rise_to(me, wd)
		if not dd.get("ok", false):
			await get_tree().create_timer(1.5).timeout
			dd = await main.magic.rise_to(me, wd)
		if not dd.get("ok", false):
			down = dd
			break
		await get_tree().create_timer(0.6).timeout
	mind.knowledge["ascended:" + String(rs.key)] = WorldState.day()
	needs.curiosity = clampf(needs.curiosity - 0.3, 0.0, 1.0)
	return {"ok": down.get("ok", false) and what.get("ok", true), "rise": up, "down": down, "crown": what,
		"detail": "rose %.1f m to %s; %s; %s" % [float(up.get("height", 0.0)), String(rs.label), String(what.get("detail", "")),
			"drifted back down" if down.get("ok", false) else "could not get down: %s" % String(down.get("reason", "?"))]}


## Out of the rain: walk to the spot (and right in under the eaves / against the trunk), turn to look out.
func _shelter(o: Dictionary) -> Dictionary:
	var spot: Dictionary = o.spot
	var to: Vector3 = spot.pos
	current.stage = "hurrying out of the rain"
	_maybe_say(_lines("rain_shelter", ["Over here - it's dry under here!", "Quick, under the %s!" % ("eaves" if spot.kind == "eaves" else "tree")]), 0.5, "rain_shelter")
	if not await _walk(to):
		return {"ok": false, "detail": "could not reach the shelter"}
	var t0 := Time.get_ticks_msec()
	while me.global_position.distance_to(to) > 0.45 and Time.get_ticks_msec() - t0 < 5000 and not _cancel:
		me.navigate_to(to)
		await get_tree().process_frame
	me.stop_action()
	me.look_at_point(spot.face)
	var dry: bool = main.weather.sheltered_at(me.global_position)
	return {"ok": dry, "detail": "sheltering %s (%s)" % ["under the eaves of a house" if spot.kind == "eaves" else "under a big tree", "dry" if dry else "still in the rain"],
		"where": spot.kind}


## Dry, with the rain all round: sit (or lean) and just listen for a while. Rests her; a quiet word now and then.
func _listen_rain() -> Dictionary:
	_listened_this_rain = String(main.streaming.current_id)
	current.stage = "listening to the rain"
	var sat := false
	# under a roof the ground is dry and she sits; under a tree she stays standing, out of the drips
	if me.has_clip("sit_ground_enter") and main.weather.covered(me.global_position):
		me.play_gesture("sit_ground_enter", 0.3, 0.3)
		me.set_ground_pose("sit", me.animation_length("sit_ground_enter") * 0.9)
		await get_tree().create_timer(me.animation_length("sit_ground_enter") * 0.85).timeout
		me.play_gesture("sit_ground_loop", 0.3, 0.6)
		sat = true
	if me.get("face") and me.face:
		me.face.pulse("relaxed", 0.5, 6.0)
	var secs := rng.randf_range(22.0, 40.0)
	var t0 := Time.get_ticks_msec()
	var said := false
	while (Time.get_ticks_msec() - t0) / 1000.0 < secs and not _cancel and _interrupt == "" and main.weather.rain > 0.2:
		if not said and (Time.get_ticks_msec() - t0) / 1000.0 > 6.0:
			said = true
			_maybe_say(_lines("rain_listen", ["Listen to it on the leaves.", "I could fall asleep to this.", "Everything smells different when it rains."]), 0.7, "rain_listen")
		await get_tree().create_timer(0.5).timeout
	if sat:
		me.end_gesture()
		me.play_gesture("sit_ground_exit", 0.2, 0.4)
		me.set_ground_pose("", me.animation_length("sit_ground_exit") * 0.9)
		await get_tree().create_timer(me.animation_length("sit_ground_exit") + 0.2).timeout
	needs.energy = clampf(needs.energy + 0.2, 0.0, 1.0)
	needs.curiosity = clampf(needs.curiosity + 0.1, 0.0, 1.0)
	var heard := (Time.get_ticks_msec() - t0) / 1000.0
	mind.knowledge["listened_to_rain"] = int(mind.knowledge.get("listened_to_rain", 0)) + 1
	return {"ok": true, "detail": "%s and listened to the rain for %.0f s" % ["sat" if sat else "stood", heard], "seconds": heard}


func _expedition(o: Dictionary) -> Dictionary:
	var plan: Dictionary = main.journeys.start(String(o.area), String(o.purpose), ["mika", "luna"] if main.characters.has("luna") else ["mika"], agent_id)
	if not plan.get("ok", false):
		return {"ok": false, "detail": "could not set out: %s" % plan.get("error", "")}
	_maybe_say(["Let's go and see for ourselves.", "It's a long walk. We'd better start now."], 1.0)
	var j: Dictionary = await main.journeys.run_live()
	var arrived := String(j.get("phase", "")) == "done"
	return {"ok": arrived, "detail": "%s the %s (%.0f km)" % ["reached" if arrived else "set out for", String(o.area).replace("_", " "), float(plan.get("km", 0.0))], "journey": j.get("id", "")}


func _drill(o: Dictionary) -> Dictionary:
	var wid := String(o.spell)
	var m0 := MagicSystem.mastery(wid, agent_id)
	var done := 0
	for i in 3:
		if _cancel:
			break
		current.stage = "drilling the %s (%d/3)" % [String(MagicSystem.spell(wid).get("name", wid)).to_lower(), i + 1]
		var r: Dictionary = await main.magic.cast(me, wid)
		if r.get("ok", false):
			done += 1
		# let it fade, breathe, set her feet again
		await get_tree().create_timer(rng.randf_range(2.5, 4.0)).timeout
	var m1 := MagicSystem.mastery(wid, agent_id)
	return {"ok": done > 0, "detail": "drilled her %s %d time(s) (mastery %.2f -> %.2f), getting ready for the %s" % [String(MagicSystem.spell(wid).get("name", wid)).to_lower(), done, m0, m1, String(o.get("for", "")).replace("_", " ")],
		"mastery": [m0, m1]}


func _lessons_heard() -> int:
	return mind.knowledge.keys().filter(func(x): return String(x).begins_with("lesson:")).size()


func _ward_mastery() -> float:
	var t := 0.0
	for id in MagicSystem.load_catalog().spells:
		if String(MagicSystem.spell(id).get("projectile", "")) == "ward":
			t += MagicSystem.mastery(id, agent_id)
	return t


## How much readier she is for an unfinished fight than when she withdrew (0 = no different).
func readiness(kind: String) -> float:
	var u = mind.knowledge.get("unfinished:" + kind)
	if not (u is Dictionary):
		return 1.0
	return float(mind.level() - int(u.get("level", 0))) + float(_lessons_heard() - int(u.get("lessons", 0))) * 0.5 + (_ward_mastery() - float(u.get("wards", 0.0))) * 0.8


func unfinished() -> Array:
	return mind.knowledge.keys().filter(func(x): return String(x).begins_with("unfinished:")).map(func(x): return mind.knowledge[x])


## Recent tactical decisions (overlay, tests, bridge): what she chose and why.
var tactics_log: Array = []
## V3 Part XIII: when each technique of her family may be used again (game time), from the spell's cooldown_s.
var spell_cd := {}


func spell_ready(id: String) -> bool:
	return WorldState.game_time() >= float(spell_cd.get(id, 0.0))


func _note_cooldown(id: String) -> void:
	var cd := float(MagicSystem.spell(id).get("cooldown_s", 0.0))
	if cd > 0.0:
		spell_cd[id] = WorldState.game_time() + cd

func _note_tactic(dec: Dictionary) -> void:
	tactics_log.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "intent": dec.intent, "why": dec.get("why", "")})
	if tactics_log.size() > 40:
		tactics_log.pop_front()


func _on_dodge_resolved(_h: AttackHazard, struck: Array, st: Dictionary) -> void:
	if struck.has(me):
		st.struck = int(st.struck) + 1
	else:
		st.dodged = int(st.dodged) + 1


## Move toward `to` (running), but stay alert: stop the moment she perceives a blow coming at her, so
## the next decision can be a dodge. Returns when arrived, interrupted or after `max_s`.
func _move_alert(to: Vector3, max_s: float) -> void:
	me.navigate_to(to, true)
	var t0 := Time.get_ticks_msec()
	while me.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < int(max_s * 1000.0) and not _cancel:
		await get_tree().physics_frame
		if CombatTactics.incoming(me, main.world) != null:
			me.stop_action()
			return


## Can she see this point from her eyes (no solid world geometry in between)?
func can_see(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(me.global_position + Vector3(0, 1.5, 0), p)
	q.exclude = [me.get_rid()]
	q.collision_mask = 1
	var hit := me.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(p) < 1.0


func _collect(l) -> Dictionary:
	if l == null or not is_instance_valid(l) or l.claimed:
		return {"ok": false, "detail": "nothing left to pick up"}
	current.stage = "picking up %s" % l.label()
	await _approach(l.global_position, 0.55)
	if not is_instance_valid(l) or l.claimed:
		return {"ok": false, "detail": "someone else took it"}
	var label: String = l.label()
	var pk: Dictionary = await PickupAction.pick(me, l)          # the hand really has to reach it
	if not pk.ok and is_instance_valid(l) and not l.claimed:
		await _approach(l.global_position, 0.3)                    # step in closer and try once more
		if not is_instance_valid(l) or l.claimed:
			return {"ok": false, "detail": "someone else took it"}
		pk = await PickupAction.pick(me, l)
	if not pk.ok or not is_instance_valid(l):
		return {"ok": false, "detail": "could not reach %s" % label}
	return l.collect(me)


func _gather(o: Dictionary) -> Dictionary:
	var g: GatherNode = o.node
	if not is_instance_valid(g) or not g.available():
		return {"ok": false, "detail": "it was already picked"}
	current.stage = "walking to the %s" % g.label().to_lower()
	await _approach(g.global_position, 0.5)
	if not g.available():
		return {"ok": false, "detail": "it was already picked"}
	current.stage = "picking the %s" % g.label().to_lower()
	var tok := g.token()
	var pk: Dictionary = await PickupAction.pick(me, tok)
	if is_instance_valid(tok):
		tok.queue_free()
	if not pk.ok:
		return {"ok": false, "detail": "could not reach the %s" % g.label().to_lower()}
	var r := g.harvest(me)
	r["pickup"] = pk
	return r


## Walk to stand `dist` m in front of a small object (facing it), through normal navigation.
func _approach(p: Vector3, dist: float) -> void:
	var from := Vector3(me.global_position.x - p.x, 0, me.global_position.z - p.z)
	var stand := p + (from.normalized() if from.length() > 0.1 else Vector3.BACK) * dist
	var map := me.get_world_3d().navigation_map
	await _walk(NavigationServer3D.map_get_closest_point(map, stand))
	# _walk accepts 2.5 m; picking something up needs her right there: a short precise second approach
	if Vector2(me.global_position.x - stand.x, me.global_position.z - stand.z).length() > 0.9:
		me.navigate_to(NavigationServer3D.map_get_closest_point(map, stand), false)
		var t0 := Time.get_ticks_msec()
		while me.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < 6000 and not _cancel:
			await get_tree().process_frame
	if me.global_position.distance_to(stand) > 0.5:
		var d := Vector3(stand.x - me.global_position.x, 0, stand.z - me.global_position.z)
		if d.length() < 1.6 and not me.test_move(me.global_transform, d):
			var tw := me.create_tween()
			tw.tween_property(me, "global_position", me.global_position + d, 0.4)
			await tw.finished


## Withdraw inside the ritual circle (creatures will not cross its ward) and recover vigor there.
func _recover() -> Dictionary:
	current.stage = "withdrawing to the circle"
	var safe := Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-3.0, 3.0))
	var map := me.get_world_3d().navigation_map
	await _walk(NavigationServer3D.map_get_closest_point(map, safe), true)
	current.stage = "catching her breath"
	me.set_expression("relaxed", 0.6)
	var t0 := Time.get_ticks_msec()
	while mind.vigor < 0.9 and Time.get_ticks_msec() - t0 < 25000 and not _cancel:
		mind.vigor = clampf(mind.vigor + 0.1 * get_process_delta_time(), 0.0, 1.0)   # ~9 s from exhausted to steady
		await get_tree().process_frame
	me.set_expression("relaxed", 0.0)
	needs.energy = clampf(needs.energy + 0.15, 0.0, 1.0)
	threat = null
	return {"ok": true, "detail": "recovered to %d%% vigor" % int(mind.vigor * 100.0)}


## Slow natural recovery of vigor; faster inside the ward. Also her senses: what she can see nearby.
var _sense_t := 0.0

func _process(delta: float) -> void:
	_sight_t -= delta
	if _sight_t <= 0.0:
		_sight_t = 2.0
		_notice_creatures()
	if mind == null or not enabled:
		return
	_sense_t -= delta
	if _sense_t <= 0.0 and me.visible and main.world:
		_sense_t = 2.0
		perceive()
	_mark_t -= delta
	if _mark_t <= 0.0 and me.visible and main.world and main.streaming.state == "idle":
		_mark_t = 1.0
		explore_map.mark(me.global_position)
	var inside: bool = main.streaming.current_id == "sanctuary" and Vector2(me.global_position.x, me.global_position.z).length() < 12.0
	mind.vigor = clampf(mind.vigor + delta * (0.012 if inside else 0.004), 0.0, 1.0)
	if threat and (not is_instance_valid(threat) or not threat.alive()):
		threat = null


## Things she can actually see right now: interactables within 12 m with a clear line from her eyes. Each is
## remembered as "noticed:<id>" in HER mind (no XP; it only makes those things available to her plans).
func perceive() -> Array:
	var seen := []
	var eyes := me.global_position + Vector3(0, 1.5, 0)
	var space := me.get_world_3d().direct_space_state
	# plants she can see (gathering is only planned for things she has noticed)
	for g in get_tree().get_nodes_in_group("gatherable"):
		var gk := "noticed:gather:" + String(g.gid)
		if not mind.knowledge.has(gk) and eyes.distance_to((g as Node3D).global_position) < 12.0:
			var qg := PhysicsRayQueryParameters3D.create(eyes, (g as Node3D).global_position + Vector3(0, 0.2, 0))
			qg.exclude = [me.get_rid()]
			qg.collision_mask = 1
			var hg := space.intersect_ray(qg)
			if hg.is_empty() or (hg.position as Vector3).distance_to((g as Node3D).global_position) < 1.0:
				mind.knowledge[gk] = 1
				seen.append("gather:" + String(g.gid))
	# kinds of magic-reactive objects she has seen in this area (what background practice may use)
	for r in main.magic.reactives().values():
		if r is Monster:
			continue
		var key := "noticed_kind:%s:%s" % [main.streaming.current_id, (r as ReactiveElement).kind]
		if not mind.knowledge.has(key) and eyes.distance_to((r as ReactiveElement).aim_point()) < 18.0:
			mind.knowledge[key] = 1
	for id in main.world.interactables:
		if mind.knowledge.has("noticed:" + String(id)):
			continue
		var it: Node3D = main.world.interactables[id]
		var p := it.global_position + Vector3(0, 0.6, 0)
		if eyes.distance_to(p) > 12.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(eyes, p)
		q.exclude = [me.get_rid()]
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit.position as Vector3).distance_to(p) < 1.2:
			mind.knowledge["noticed:" + String(id)] = 1
			seen.append(id)
	return seen


# ------------------------------------------------------------------ background simulation (honest)
## Her area is not loaded. She may only do what can be represented without the physical world, under the
## SAME rules as in the foreground, at real-time pace:
##   rest     - recovers energy and vigor at the normal rates
##   practice - repeat a reaction she has ALREADY observed, on a kind of object she has seen in this area;
##              success is a bounded chance from her mastery (0.7..0.95); success = the same mastery gain and
##              repeat-practice XP as a real cast; a miss gains nothing
##   journal  - writes from her real activity log (only if there is something new)
##   wander   - walks about places she knows: tiredness only, nothing new is learned
## Anything needing the world (new pages or reactions, creatures, alchemy, meetings, new places) is deferred:
## remembered in mind.deferred and offered again once she is in view. No LLM calls in the background.
var _bg_rng := RandomNumberGenerator.new()
var bg_log: Array = []

func _background_step() -> void:
	var area := String(mind.location.get("area", "sanctuary"))
	var practice := []
	for k in mind.knowledge:
		var ks := String(k)
		if not ks.begins_with("reaction:"):
			continue
		var parts := ks.split(":")
		if parts.size() < 4 or parts[3] in ["none", "defeated", "struck"] or Spawner.load_data().monsters.has(parts[2]):
			continue
		if mind.knowledge.has("noticed_kind:%s:%s" % [area, parts[2]]) and main.magic.can_cast(parts[1], agent_id).ok:
			practice.append(parts)
	var w := {"rest": 0.2 + (1.0 - needs.energy) * 1.2 + (1.0 - mind.vigor), "practice": (0.3 + needs.mastery * 0.6) if not practice.is_empty() else 0.0,
		"journal": 0.6 if not Journal.compose(mind).is_empty() else 0.0, "wander": 0.25 + needs.curiosity * 0.2}
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := _bg_rng.randf() * total
	var pick := "wander"
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			pick = k
			break
	# what she would rather be doing, if only she were in view (deferred, never simulated)
	var want := ""
	if needs.curiosity > 0.75:
		want = "explore somewhere new"
	elif needs.mastery > 0.8 and mind.vigor > 0.7:
		want = "find something to fight"
	if want != "" and (mind.deferred.is_empty() or String(mind.deferred[-1].get("want", "")) != want):
		mind.deferred.append({"want": want, "unix": int(Time.get_unix_time_from_system()), "area": area})
		if mind.deferred.size() > 20:
			mind.deferred.pop_front()
	current = {"kind": "background", "label": {"rest": "resting", "practice": "practising", "journal": "writing her journal", "wander": "walking about"}[pick] + " (out of view)", "stage": pick}
	var entry := {"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "area": area, "activity": pick}
	match pick:
		"rest":
			await _bg_wait(_bg_rng.randf_range(20.0, 35.0))
			needs.energy = clampf(needs.energy + 0.3, 0.0, 1.0)
		"practice":
			var p: Array = practice[_bg_rng.randi() % practice.size()]
			await _bg_wait(_bg_rng.randf_range(8.0, 14.0))
			var chance := clampf(0.7 + 0.08 * MagicSystem.mastery(p[1], agent_id), 0.7, 0.95)
			var ok := _bg_rng.randf() < chance
			entry["spell"] = p[1]
			entry["on"] = p[2]
			entry["success"] = ok
			if ok:
				var m0 := MagicSystem.mastery(p[1], agent_id)
				var gain := 0.08 / (1.0 + m0 * 0.8)          # same formula as MagicSystem._award (no "first" bonus)
				entry["changes"] = WorldState.record_activity({"id": "spell:%s" % p[1], "verb": "practice", "label": "%s (%s, out of view)" % [MagicSystem.spell(p[1]).name, p[3]], "sim": "background"},
					{"skills": {p[1]: gain}, "knowledge": {"reaction:%s:%s:%s" % [p[1], p[2], p[3]]: 1}}, agent_id)
			needs.energy = clampf(needs.energy - 0.07, 0.0, 1.0)
			needs.mastery = clampf(needs.mastery - 0.08, 0.0, 1.0)
		"journal":
			var e := Journal.compose(mind)
			await _bg_wait(clampf(String(e.get("text", "")).split(" ").size() / 2.5, 4.0, 14.0))
			if not e.is_empty() and not Journal.compose(mind).is_empty():
				var j: Array = mind.knowledge.get("journal", []).duplicate()
				j.append({"heading": e.heading, "text": e.text, "unix": int(Time.get_unix_time_from_system())})
				mind.knowledge["journal"] = j
				mind.knowledge["journal_cursor"] = e.cursor
				entry["changes"] = WorldState.record_activity({"id": "journal_write", "verb": "write", "label": e.heading, "sim": "background"}, {}, agent_id)
		"wander":
			await _bg_wait(_bg_rng.randf_range(15.0, 30.0))
			needs.energy = clampf(needs.energy - 0.03, 0.0, 1.0)
			needs.curiosity = clampf(needs.curiosity + 0.05, 0.0, 1.0)
	needs.social = clampf(needs.social + 0.02, 0.0, 1.0)
	bg_log.append(entry)
	if bg_log.size() > 100:
		bg_log.pop_front()
	current = {}


## Waits in 1 s steps; returns early if she comes into view (her area got loaded) or is released.
func _bg_wait(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < seconds and enabled and main.sim_mode(agent_id) == "background":
		await get_tree().create_timer(1.0).timeout


## Per-mage line overrides (data/mages.json "lines"); falls back to the given defaults.
func _lines(key: String, defaults: Array) -> Array:
	return profile.get("lines", {}).get(key, defaults)


# ------------------------------------------------------------------ helpers
func _use(id: String) -> Dictionary:
	var it: Interactable = main.world.interactables.get(id)
	if it == null:
		return {"ok": false, "detail": "no '%s' in %s" % [id, main.streaming.current_id]}
	var label := it.label
	var area := String(main.streaming.current_id)
	if not await _walk(_stand_at(it)):
		return {"ok": false, "detail": "could not reach %s" % label}
	# the walk can outlive the place: a journey unloads the area and frees its interactables while she walks (after a
	# permanent transformation she resumes her interrupted activity; touching the freed one crashed Godot at the
	# journey's last "arrived" - 6 of 11 runs, GDScript backtrace _use -> it.in_reach, 2026-10-16/17)
	if not is_instance_valid(it) or String(main.streaming.current_id) != area:
		return {"ok": false, "detail": "%s is no longer here" % label}
	if not it.in_reach(me.global_position):
		# the walk tolerance is looser than the interaction reach: close the last metre
		await _walk(_stand_at(it))
		if not is_instance_valid(it) or String(main.streaming.current_id) != area:
			return {"ok": false, "detail": "%s is no longer here" % label}
	return await it.perform(me)


func _walk(target: Vector3, ignore_threat := false) -> bool:
	if _interrupt.begins_with("the show") and not ignore_threat:
		return false                 # the show asked for her: no new errand steps (each one used to start and stop at once)
	for attempt in 2:
		# she always walks (2026-10-17 live: trips over 45 m ran at 4.1 m/s - the altar to Starfall Hill is 44-50 m,
		# so every crossing of the sanctuary looked like a dash). A run belongs to a fight, never to an errand.
		me.navigate_to(target, false)
		if me.current_action != "navigate_to":
			if me.global_position.distance_to(target) < 2.0:
				return true
			continue
		while me.current_action == "navigate_to" and not _cancel:
			if (_interrupt in ["threat", "social", "transform"] or _interrupt.begins_with("the show") or (_interrupt == "discovery" and String(current.get("kind", "")) in ["roam", "wander", "explore", "visit", "gather"])) and not ignore_threat:
				me.stop_action()
				return false
			await get_tree().process_frame
		if me.global_position.distance_to(target) < 2.5:
			return true
		var away := me.global_position - target
		away.y = 0
		me.navigate_to(me.global_position + away.normalized() * 1.2)
		await get_tree().create_timer(1.0).timeout
	return me.global_position.distance_to(target) < 2.5


## Find a nearby navmesh spot with line of sight, range and space for this spell, then walk there.
func _stand_for_cast(spell_id: String, target_id: String) -> bool:
	var target: ReactiveElement = main.magic.reactives().get(target_id)
	if target == null:
		return false
	if main.magic.validate(spell_id, me, target).ok and main.world.has_space_for_magic(me.global_position):
		return true
	var tp := target.aim_point()
	var map := me.get_world_3d().navigation_map
	var rangev := float(MagicSystem.spell(spell_id).get("range", 8.0))
	var from_dir := Vector3(me.global_position.x - tp.x, 0, me.global_position.z - tp.z)
	var base := atan2(from_dir.x, from_dir.z)
	for ring in [minf(5.0, rangev - 1.0), minf(3.5, rangev - 1.0), minf(7.0, rangev - 1.0)]:
		for k in 12:
			var ang: float = base + (k / 2) * 0.5 * (1.0 if k % 2 == 0 else -1.0)
			var want: Vector3 = tp + Vector3(sin(ang), 0, cos(ang)) * float(ring)
			var p := NavigationServer3D.map_get_closest_point(map, want)
			if p.distance_to(Vector3(want.x, p.y, want.z)) > 0.8:
				continue
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.3, 0), tp)
			q.exclude = [me.get_rid()]
			var hit := me.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty() and not target.owns_collider(hit.collider) and (hit.position as Vector3).distance_to(tp) > target.aim_radius + 0.35:
				continue
			if not main.world.has_space_for_magic(p):
				continue
			if await _walk(p):
				# check where she actually stopped (navigation can stop up to ~0.7 m short)
				if main.magic.validate(spell_id, me, target).ok and main.world.has_space_for_magic(me.global_position):
					return true
	return false


## Grass, per area: 2 m cells -> blade-clump count, from the area's grass MultiMeshes (built once per area).
static var _grass_cache := {}


static func _is_grass(n: Node, root: Node) -> bool:
	var x := n
	while x and x != root:
		if x.is_in_group("cat_grass") or String(x.name).to_lower().contains("grass"):
			return true
		x = x.get_parent()
	return false


func _grass_cells() -> Dictionary:
	var w: Node = main.world
	var key := w.get_instance_id()
	if _grass_cache.has(key):
		return _grass_cache[key]
	var cells := {}
	for mmi in w.find_children("*", "MultiMeshInstance3D", true, false):
		if not _is_grass(mmi, w) or (mmi as MultiMeshInstance3D).multimesh == null:
			continue
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		var xf: Transform3D = (mmi as Node3D).global_transform
		var step := maxi(1, mm.instance_count / 3000)
		for i in range(0, mm.instance_count, step):
			var p: Vector3 = xf * mm.get_instance_transform(i).origin
			var c := Vector2i(floori(p.x / 2.0), floori(p.z / 2.0))
			cells[c] = int(cells.get(c, 0)) + step
	_grass_cache = {key: cells}
	return cells


## An open grassy spot 6-30 m away: thick grass, open sky straight above (no canopy), on the navmesh. INF if none.
func _grass_stargaze_spot() -> Vector3:
	var cells := _grass_cells()
	if cells.is_empty():
		return Vector3.INF
	var here := me.global_position
	var cands := []
	for c in cells:
		if int(cells[c]) < 6:
			continue
		var p := Vector3(c.x * 2.0 + 1.0, here.y, c.y * 2.0 + 1.0)
		var d := Vector2(p.x - here.x, p.z - here.z).length()
		if d < 6.0 or d > 30.0:
			continue
		cands.append([int(cells[c]) + rng.randi_range(0, 6), p])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var map := me.get_world_3d().navigation_map
	var space := me.get_world_3d().direct_space_state
	for cd in cands.slice(0, 24):
		var p: Vector3 = NavigationServer3D.map_get_closest_point(map, cd[1])
		if p == Vector3.ZERO or Vector2(p.x - cd[1].x, p.z - cd[1].z).length() > 1.5:
			continue
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p + Vector3(0, 30.0, 0))
		q.exclude = [me.get_rid()]
		if space.intersect_ray(q).is_empty():
			return p
	return Vector3.INF


## The home region's places to walk to (location id -> what she says she is doing).
const HOME_VISITS := {"ancient_spell_library": "go down to the Ancient Spell Library", "whispering_woods": "walk the trails of the Whispering Woods",
	"mentors_tower": "walk over to the Mentor's Tower", "ritual_sanctuary": "head back to the sanctuary",
	"lantern_lake": "walk down to Lantern Lake to watch the lanterns"}
const LAKE_LINES := {
	"mika": ["Look at them all... it's like the sky came down to sit on the water.", "Make a wish, Luna. I'll make one too.",
		"Every one of those is somebody's wish, I think.", "I could stay here until the last one is gone."],
	"luna": ["...They drift so slowly. Like they're not in any hurry at all.", "Mine's already made. Don't ask what it is.",
		"The lake holds all of them. Even the ones that fly away.", "Stay a little longer. Just a little."]}


## The night a moment belongs to (the evening's date, also after midnight).
static func night_id() -> int:
	return WorldState.day() - (1 if WorldState.hour_f() < 12.0 else 0)


static func home_areas() -> Array:
	var out := []
	for a in WorldState.areas:
		if String(WorldState.areas[a].get("region", "")) == REGION:
			out.append(a)
	return out


## Lantern Lake: both walk out to the end of the pier, sit on the planks facing the lake, watch the lanterns, say a
## few quiet words and let one or two lanterns go; then they get up (and later walk home).
func _lakewatch(_o: Dictionary) -> Dictionary:
	var w: Node = main.world
	var spots: Array = w.sit_spots()
	var face: Vector3 = w.lake_facing()
	var other: WorldCharacter = null
	var ob: SanctuaryBrain = null
	for wid in main.mage_brains:
		if wid != agent_id:
			var oc: WorldCharacter = main.characters.get(wid)
			if oc and oc.visible and oc.global_position.distance_to(me.global_position) < 40.0:
				other = oc
				ob = main.mage_brains[wid]
	if ob:
		ob.hold = true
		ob.interrupt("watching the lanterns together")
		await get_tree().create_timer(0.4).timeout
	current.stage = "walking out along the pier"
	var ob_box := {}
	if ob:
		var ojob := func(): ob_box["ok"] = await ob._walk(spots[1])        # (her own walk, with its retries)
		ojob.call()
	if not await _walk(spots[0]):
		if ob:
			ob.hold = false
		return {"ok": false, "detail": "could not get out onto the pier"}
	var tw := Time.get_ticks_msec()
	while ob and not ob_box.has("ok") and Time.get_ticks_msec() - tw < 90000:
		await get_tree().process_frame
	if other and other.global_position.distance_to(spots[1]) > 1.5:
		other = null                                  # she could not get out there: Mika watches alone (no sitting on the bank)
	current.stage = "sitting at the end of the pier"
	var sitters: Array = [me] + ([other] if other else [])
	for c in sitters:
		(c as WorldCharacter).look_at_point(Vector3(face.x, (c as WorldCharacter).global_position.y, face.z))
	await get_tree().create_timer(0.8).timeout
	for c in sitters:
		var wc: WorldCharacter = c
		wc.play_gesture("sit_ground_enter", 0.25, 0.3)
		wc.set_ground_pose("sit", wc.animation_length("sit_ground_enter") * 0.9)
	await get_tree().create_timer(me.animation_length("sit_ground_enter") * 0.85).timeout
	for c in sitters:
		(c as WorldCharacter).play_gesture("sit_ground_loop", 0.3, 0.6)
	var cam_on: bool = is_foreground() and main.get("director") != null and w.has_method("watch_shot")
	if cam_on:
		main.director.enabled = true
		var tt := {"t": 0.0}
		main.director.begin_scene(func(d: float) -> Dictionary:
			tt.t += d
			return w.watch_shot(float(tt.t)))
	var oid := other.character_id if other else ""
	var ml: Array = LAKE_LINES.get(agent_id, LAKE_LINES.mika)
	var ol: Array = LAKE_LINES.get(oid, [])
	var pick := rng.randi() % ml.size()
	await get_tree().create_timer(4.0).timeout
	if main.get("voice"):
		await main.voice.say(_voice(), String(ml[pick]))
	if w.has_method("release_lantern"):
		w.release_lantern()                           # they let one go
	await get_tree().create_timer(6.0).timeout
	if other and not ol.is_empty() and main.get("voice"):
		await main.voice.say(String(ob.profile.get("voice", oid)), String(ol[pick % ol.size()]))
	await get_tree().create_timer(rng.randf_range(18.0, 30.0)).timeout
	if w.has_method("release_lantern"):
		w.release_lantern()
	if main.get("voice"):
		await main.voice.say(_voice(), String(ml[(pick + 1) % ml.size()]))
	await get_tree().create_timer(rng.randf_range(20.0, 35.0)).timeout
	current.stage = "getting up"
	if cam_on:
		main.director.end_scene()
	for c in sitters:
		var wc2: WorldCharacter = c
		wc2.play_gesture("sit_ground_exit", 0.2, 0.4)
		wc2.set_ground_pose("", wc2.animation_length("sit_ground_exit") * 0.9)
	await get_tree().create_timer(me.animation_length("sit_ground_exit") + 0.6).timeout
	var nid := night_id()
	mind.knowledge["lake_night"] = nid
	if other:
		WorldState.mind(oid).knowledge["lake_night"] = nid
	if ob:
		ob.hold = false
	needs.social = clampf(needs.social - 0.3, 0.0, 1.0)
	needs.energy = clampf(needs.energy + 0.1, 0.0, 1.0)
	return {"ok": true, "detail": "watched the lanterns at the end of the pier%s" % (" with " + MagicSystem.display_name(oid) if other else "")}


func _visit(o: Dictionary) -> Dictionary:
	current.stage = "walking to the %s" % String(o.area).replace("_", " ")
	var j := await _travel(String(o.location))
	if not j.get("ok", false):
		return {"ok": false, "detail": "could not reach %s: %s" % [o.area, j.get("detail", j.get("reason", "?"))]}
	mind.knowledge["visited_unix:" + String(o.area)] = Time.get_unix_time_from_system()
	needs.curiosity = clampf(needs.curiosity - 0.1, 0.0, 1.0)
	return {"ok": true, "detail": "arrived at %s" % o.area}


func _travel(location: String) -> Dictionary:
	# the other mage, here with her and free, walks along (Day 2: Luna had vanished whenever Mika changed area)
	var dest_area := WorldState.area_of(location)
	if is_foreground() and dest_area != main.streaming.current_id and main.has_method("bring_along"):
		for w in main.mage_brains:
			if w == agent_id:
				continue
			var oc: WorldCharacter = main.characters.get(w)
			# (anywhere in this area: they are a pair - Day 2 soak: from Starfall Hill she was 40+ m off and stayed behind)
			if oc and oc.visible and not oc.has_meta("transforming"):
				# she finishes (or stops) what she is doing first: nothing of hers may be mid-way when the area unloads
				if main.book_reader.reading() and String(main.book_reader.current.get("reader", "")) == w:
					main.book_reader.stop()
				var ob2: SanctuaryBrain = main.mage_brains[w]
				ob2.interrupt("walking along with %s" % agent_id)
				var tw2 := Time.get_ticks_msec()
				while not ob2.current.is_empty() and Time.get_ticks_msec() - tw2 < 20000:
					await get_tree().process_frame
				main.bring_along(w, agent_id)
	var r: Dictionary = main.travel.travel_to(location, "walk")
	if not r.get("ok", false):
		return {"ok": false, "detail": r.get("error", "?")}
	var res := [null]
	var cb := func(ev): if ev.event == "journey_finished": res[0] = ev
	main.travel.journey_event.connect(cb)
	var t0 := Time.get_ticks_msec()
	while res[0] == null and Time.get_ticks_msec() - t0 < 180000 and not _cancel:
		await get_tree().process_frame
	main.travel.journey_event.disconnect(cb)
	if res[0] == null:
		main.travel.cancel("brain timeout")
		return {"ok": false, "detail": "timeout"}
	mind.knowledge["arrived_unix"] = Time.get_unix_time_from_system()
	return res[0]


func _private_thought(text: String) -> void:
	thought.emit(VoiceService.clean(text), SanctuaryBrain.sub_area(main.world, me.global_position))


## Spoken only when the moment justifies it, at most once a minute.
## key: a line pool with a fixed mood (data/voices.json line_moods) - pre-rendered in her voice, and in a fight it
## never holds the action up (latency budget: shown as a subtitle if the voice is not ready in time).
func _maybe_say(lines: Array, chance: float, key := "") -> void:
	if Time.get_ticks_msec() / 1000.0 < _speak_cd or rng.randf() > chance:
		return
	_speak_cd = Time.get_ticks_msec() / 1000.0 + 60.0
	var opts := {}
	var mood := String(main.voice.config.get("line_moods", {}).get(key, "")) if key != "" else ""
	if mood != "":
		opts["mood"] = mood
	if me.combat_stance:
		opts["max_wait"] = 1.5
	main.voice.say(_voice(), lines[rng.randi() % lines.size()], opts)


## Compatibility with the bridge's perform_action{action}: runs the matching activity once.
func perform_action(action_id: String) -> Dictionary:
	for o in options():
		if o.key == action_id or o.get("interactable", "") == action_id or o.label == action_id:
			return await run_activity(o)
	return {"ok": false, "error": "no available activity '%s' (see region_context.options)" % action_id}
