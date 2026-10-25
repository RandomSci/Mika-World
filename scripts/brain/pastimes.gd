## (no class_name: preloaded where used, so a build needs no class re-scan)
extends RefCounted
## Small things to do right where she is (26 Oct, Selwyn: "make their thinking brains think of many activities, not
## just walking"). On the 25 Oct stream 156 of their 227 choices were walks somewhere (a visit, a spot, a roam, a
## wander, a revisit), and a walk is where they got stuck. A pastime needs no walk: a stretch, a sit on the grass,
## the clouds or the stars, something picked up from the ground, a tiny thing looked at close, a wave to everyone
## watching, a thought about the case, a drink, a boot to fix. Each one is followed by a few words about it (the
## language model writes them new every time, between the two of them; alone, a line she has never said before).
## Every pastime waits 30 minutes before it comes again (Selwyn's repetition rule), and while walks keep going wrong,
## or after a run of walks, a pastime is the natural thing to do next.

const AGAIN_S := 1800.0               # the same pastime at most every 30 minutes
const WALK_KINDS := ["visit", "spot", "roam", "wander", "revisit", "explore", "expedition", "join_find"]

## id -> label (what she thinks "I'll ..."), what happens (clips), how long, and the words that follow
const LIST := {
	"stretch": {"label": "stretch for a moment", "talk": "you just stopped to stretch your arms and neck after all the walking"},
	"take_in_view": {"label": "stop and take in the view", "talk": "you just stopped and looked all round %s, taking it in"},
	"sit_grass": {"label": "sit down on the grass for a bit", "ground": true, "dry": true, "talk": "you just sat down on the grass at %s to rest your feet"},
	"cloud_watch": {"label": "lie in the grass and watch the clouds", "ground": true, "dry": true, "day": true, "talk": "you just lay in the grass at %s watching the clouds drift over"},
	"star_count": {"label": "lie back and count the stars", "ground": true, "dry": true, "night": true, "talk": "you just lay back at %s counting the stars"},
	"pick_up": {"label": "pick up something from the ground", "talk": "you just picked up %s from the ground at %s and looked at it closely"},
	"look_close": {"label": "crouch down to look at something tiny", "talk": "you just crouched down at %s to look at %s"},
	"wave_viewers": {"label": "wave to everyone watching", "talk": "you just waved hello to everyone watching the stream with you"},
	"think_case": {"label": "stop and think about the case", "story": true, "talk": "you just stopped, arms folded, thinking about the case: %s"},
	"drink": {"label": "have a drink from my flask", "talk": "you just stopped for a drink of water from your flask at %s"},
	"fix_boot": {"label": "fix my boot", "talk": "you just knelt down to fix a loose boot strap at %s"},
	"point_out": {"label": "point something out to %s", "pair": true, "talk": "you just pointed something out to %s far off across %s"},
}
const FINDS := ["a smooth river pebble", "a striped feather", "a tiny acorn", "a shiny beetle shell", "a pressed-flat leaf",
	"a blue glass bead", "a sliver of glowing crystal", "a snail shell", "a pine cone", "a four-leaf clover"]
const TINY := ["a line of ants carrying crumbs", "a mushroom no bigger than a button", "a glowing moss", "a ladybird",
	"a flower closing for the night", "a spider's web full of dew", "a tiny frog", "a moth with silver wings"]
const LINES := {
	"stretch": ["Ow, my shoulders. That's better.", "Okay, stretch break. Mage legs need it too.", "Mm. My back says thank you."],
	"take_in_view": ["Look at it. I never get tired of this.", "Let me just look for a second.", "It's prettier every time."],
	"sit_grass": ["I'm sitting down. Just for a minute.", "The grass is warm here.", "My feet needed this."],
	"cloud_watch": ["That one looks like a rabbit.", "Clouds are slower than they look.", "If I squint, that's a dragon."],
	"star_count": ["Forty one, forty two... I lost count.", "There's the one I always find first.", "So many tonight."],
	"pick_up": ["Ooh, what's this?", "I'm keeping this one.", "Look what I found."],
	"look_close": ["Hello, little one.", "Come look how tiny it is.", "Shh. Don't scare it."],
	"wave_viewers": ["Hi everyone!", "Hello to everyone watching!", "Thanks for keeping us company."],
	"think_case": ["Something doesn't add up yet.", "Let me think this through.", "What are we missing?"],
	"drink": ["Water break.", "Ah. I needed that.", "Walking makes me thirsty."],
	"fix_boot": ["Hold on, my boot.", "This strap again.", "One second, nearly done."],
	"point_out": ["Look, over there!", "Do you see that?", "There, far off. See it?"],
}


static func _place(brain) -> String:
	var a: Dictionary = WorldState.areas.get(String(brain.main.streaming.current_id), {})
	return String(a.get("name", String(brain.main.streaming.current_id).replace("_", " ")))


static func _done_recently(brain, id: String) -> bool:
	var last := float(brain.mind.activity_counts.get("pastime:" + id, {}).get("last_unix", 0))
	return last > 0.0 and Time.get_unix_time_from_system() - last < AGAIN_S


static func _flat_dry(brain) -> bool:
	var me: WorldCharacter = brain.me
	if not me.is_on_floor() or me.get_floor_normal().y < 0.94:
		return false
	if brain.main.get("weather") and float(brain.main.weather.rain) > 0.15:
		return false
	return true


## The pastimes on offer right now (none in a fight, a journey or the background).
static func options(brain) -> Array:
	var out := []
	var me: WorldCharacter = brain.me
	if not me.visible or brain.threat != null or me.casting or me.seated or me.ground_pose != "":
		return out
	var night: bool = WorldState.night
	var other: WorldCharacter = null
	for w in brain.main.characters:
		if w != brain.agent_id:
			var c: WorldCharacter = brain.main.characters[w]
			if c and c.visible and c.global_position.distance_to(me.global_position) < 7.0:
				other = c
	var flat := _flat_dry(brain)
	for id in LIST:
		var p: Dictionary = LIST[id]
		if _done_recently(brain, id):
			continue
		if p.get("ground", false) and not flat:
			continue
		if p.get("day", false) and night or p.get("night", false) and not night:
			continue
		if p.get("pair", false) and other == null:
			continue
		if p.get("story", false) and brain.main.story.next_leads().is_empty() and brain.main.story.describe().get("clues_found", {}).is_empty():
			continue
		if id == "wave_viewers" and not brain.is_lead():
			continue
		var label := String(p.label)
		if p.get("pair", false):
			label = label % MagicSystem.display_name(other.character_id)
		out.append({"kind": "pastime", "key": "pastime:" + id, "pastime": id, "label": label,
			"other": other.character_id if other else ""})
	return out


## How much she wants it: more when tired (the sitting and lying ones), when curious (the finds), with company
## (pointing out), and most when walks keep going wrong or she has walked a lot lately.
static func score(brain, o: Dictionary) -> Dictionary:
	var n: Dictionary = brain.needs
	var id := String(o.pastime)
	var u := 0.42
	var why := []
	match id:
		"sit_grass", "cloud_watch", "star_count":
			u += (1.0 - float(n.energy)) * 0.45
		"pick_up", "look_close", "take_in_view":
			u += float(n.curiosity) * 0.25
		"point_out", "wave_viewers":
			u += float(n.social) * 0.3
		"think_case":
			u += 0.15
		"stretch", "drink", "fix_boot":
			u += 0.05
	var walks: int = brain._recent_kinds.slice(maxi(0, brain._recent_kinds.size() - 3)).filter(func(k): return k in WALK_KINDS).size()
	if walks >= 1:
		u += 0.16 * walks
		why.append("%d of the last 3 were walks +%.2f" % [walks, 0.16 * walks])
	if Time.get_unix_time_from_system() < float(brain.walk_trouble_until):
		u += 0.35
		why.append("the walking keeps going wrong +0.35")
	return {"u": u, "why": why}


static func run(brain, o: Dictionary) -> Dictionary:
	var me: WorldCharacter = brain.me
	var id := String(o.pastime)
	var tree: SceneTree = brain.get_tree()
	var place := _place(brain)
	var talk := String(LIST[id].talk)
	brain.current.stage = String(LIST[id].label)
	me.stop_action()
	var hold := func(secs: float) -> bool:      # waits, giving way to anything that interrupts her
		var t0 := Time.get_ticks_msec()
		while (Time.get_ticks_msec() - t0) / 1000.0 < secs:
			if brain._cancel or brain._interrupt != "":
				return false
			await tree.create_timer(0.25).timeout
		return true
	var ok := true
	match id:
		"stretch":
			me.play_gesture("stretch_arms", 0.3, 0.5)
			ok = await hold.call(me.animation_length("stretch_arms"))
			if ok:
				me.play_gesture("stretch_neck", 0.3, 0.5)
				ok = await hold.call(me.animation_length("stretch_neck"))
		"take_in_view":
			var fwd := -me.global_transform.basis.z
			me.play_gesture("look_around", 0.3, 0.5)
			me.look_head_at(me.global_position + fwd.rotated(Vector3.UP, brain.rng.randf_range(-0.8, 0.8)) * 12.0 + Vector3(0, 1.8, 0))
			ok = await hold.call(maxf(me.animation_length("look_around"), 5.0))
			me.look_head_at(null)
			talk = talk % place
		"sit_grass":
			me.play_gesture("sit_ground_enter", 0.3, 0.3)
			me.set_ground_pose("sit", me.animation_length("sit_ground_enter") * 0.9)
			await tree.create_timer(me.animation_length("sit_ground_enter") * 0.85).timeout
			me.play_gesture("sit_ground_loop", 0.3, 0.6)
			ok = await hold.call(brain.rng.randf_range(18.0, 32.0))
			me.end_gesture()
			me.play_gesture("sit_ground_exit", 0.2, 0.4)
			me.set_ground_pose("", me.animation_length("sit_ground_exit") * 0.9)
			await tree.create_timer(me.animation_length("sit_ground_exit") + 0.2).timeout
			brain.needs.energy = clampf(float(brain.needs.energy) + 0.15, 0.0, 1.0)
			talk = talk % place
		"cloud_watch", "star_count":
			await me.lie_down()
			me.look_head_at(me.global_position + Vector3(0, 12.0, 0) - me.global_transform.basis.z * 3.0)
			ok = await hold.call(brain.rng.randf_range(20.0, 34.0))
			me.look_head_at(null)
			await me.get_up()
			brain.needs.energy = clampf(float(brain.needs.energy) + 0.12, 0.0, 1.0)
			talk = talk % place
		"pick_up":
			var find: String = FINDS[brain.rng.randi() % FINDS.size()]
			me.play_gesture("pick_floor", 0.25, 0.45)
			ok = await hold.call(me.animation_length("pick_floor"))
			me.look_head_at(me.global_position - me.global_transform.basis.z * 0.4 + Vector3(0, 1.1, 0))
			ok = ok and await hold.call(2.5)
			me.look_head_at(null)
			brain.needs.curiosity = clampf(float(brain.needs.curiosity) - 0.1, 0.0, 1.0)
			talk = talk % [find, place]
		"look_close":
			var tiny: String = TINY[brain.rng.randi() % TINY.size()]
			me.play_gesture("crouch_loop", 0.35, 0.5)
			me.look_head_at(me.global_position - me.global_transform.basis.z * 0.7)
			ok = await hold.call(brain.rng.randf_range(6.0, 10.0))
			me.look_head_at(null)
			me.end_gesture()
			await tree.create_timer(0.5).timeout
			brain.needs.curiosity = clampf(float(brain.needs.curiosity) - 0.1, 0.0, 1.0)
			talk = talk % [place, tiny]
		"wave_viewers":
			var cam := me.get_viewport().get_camera_3d()
			if cam:
				me.look_at_point(Vector3(cam.global_position.x, me.global_position.y, cam.global_position.z))
				await tree.create_timer(0.8).timeout
			me.play_gesture("waving", 0.25, 0.45)
			ok = await hold.call(me.animation_length("waving"))
		"think_case":
			var obj: String = String(brain.main.story.objective())
			me.play_gesture("idle_folded", 0.35, 0.5)
			ok = await hold.call(brain.rng.randf_range(8.0, 13.0))
			me.end_gesture()
			talk = talk % obj.trim_prefix("Next: ")
		"drink":
			me.play_gesture("consume", 0.3, 0.5)
			ok = await hold.call(me.animation_length("consume"))
			talk = talk % place
		"fix_boot":
			me.play_gesture("kneel_fix", 0.3, 0.5)
			ok = await hold.call(me.animation_length("kneel_fix"))
			talk = talk % place
		"point_out":
			var other: WorldCharacter = brain.main.characters.get(String(o.other))
			var fwd2 := -me.global_transform.basis.z
			var far := me.global_position + fwd2.rotated(Vector3.UP, brain.rng.randf_range(-0.6, 0.6)) * 20.0
			me.look_at_point(Vector3(far.x, me.global_position.y, far.z))
			if other:
				other.look_head_at(far + Vector3(0, 1.5, 0))
			await tree.create_timer(0.7).timeout
			me.play_gesture("pointing", 0.25, 0.45)
			ok = await hold.call(me.animation_length("pointing"))
			if other:
				other.look_head_at(null)
			talk = talk % [MagicSystem.display_name(String(o.other)), place]
	brain.mind.activity_counts["pastime:" + id] = {"last_unix": int(Time.get_unix_time_from_system()),
		"n": int(brain.mind.activity_counts.get("pastime:" + id, {}).get("n", 0)) + 1}
	WorldState.record_activity({"id": "pastime_" + id, "verb": id, "label": String(LIST[id].label)}, {}, brain.agent_id)
	# a few words about it: between the two of them the model writes them fresh; alone, a line she never said
	if brain.main.get("mage_dialogue"):
		brain.main.mage_dialogue._event(brain.agent_id, "pastime", talk)
	brain._maybe_say(brain._lines("pastime_" + id, LINES.get(id, [])), 0.55)
	return {"ok": ok, "detail": "%s at %s" % [String(LIST[id].label), place]}
