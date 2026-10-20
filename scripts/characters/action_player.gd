class_name ActionPlayer
extends Node
## One action player for every mode (2026-10-20, Selwyn: "one action player that every mode calls. It plays any
## catalog entry through the one body pipeline with the body guard and the gesture director always on. One function
## per behaviour, not per clip ... A clip's entry picks the behaviour and its settings. New clips later need only a
## new entry"). Fights, free time, dance, travel, the lake, the boat, transformations and chat reactions call
## ActionPlayer.of(character).play(entry_id, ctx).
##
## The entries are the action catalog (res://data/action_catalog.json, synced from Mika-Project docs): each clip's
## behaviour, window (start_s, end_s), gather, release and contact times, lead limb, blend in and out, speed range,
## and its status. A blocked entry (status not pass) is refused with its reason.
##
## The clip always plays through her one pose pipeline: in a fight on her FightDeck (the MeleeSim's), elsewhere through
## her locomotion tree's one shot slot with the entry's own window (AnimationNodeAnimation custom timeline). PoseBase,
## the body guard and the limits run on either. In a fight a cast goes through the GestureDirector (LimboAI).
## Contact behaviours use real targets (WorldTargets): she walks to the real thing, faces it, plays the clip, and at
## the entry's contact time her hand is put on its real surface by her arm IK (ObjectHandler's TwoBoneIK3D); the
## target reacts (leaves fall, the flower bobs and sheds petals, water splashes, Luna jumps or laughs).
##
## ctx: {sim, s, o, spell, move} in a fight; {target: Dictionary} to give the target; {force: true} QA only (plays a
## blocked entry); {hold: s} how long a loop holds.

const CATALOG := "res://data/action_catalog.json"
static var _entries := {}
## The fight's procedural strikes and guards (MeleeBook) and the catalog entry each one is (its timing source).
const FIGHT_MOVES := {"jab": "combo_jab_cross_hook", "cross": "combo_jab_cross_hook", "hook": "combo_jab_cross_hook",
	"body_hook": "combo_jab_cross_hook", "uppercut": "uppercut_launcher", "launcher": "uppercut_launcher",
	"front_kick": "front_kick", "roundhouse": "jump_spin_kick", "low_sweep": "low_sweep", "crescent_kick": "crescent_kick",
	"axe_kick": "axe_kick", "hook_kick": "hook_kick", "spin_back_kick": "spin_back_kick", "palm_strike": "dash_palm_strike"}

var c: WorldCharacter
var busy := false
var current := ""
var log: Array = []                     # one row per action played (QA)

signal contact_made(entry: String, target: Dictionary, point: Vector3)


static func entries() -> Dictionary:
	if _entries.is_empty() and FileAccess.file_exists(CATALOG):
		var d = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if d is Dictionary:
			for e in d.get("clips", []):
				_entries[String(e.id)] = e
	return _entries


static func entry(id: String) -> Dictionary:
	return entries().get(id, {})


static func of(ch: WorldCharacter) -> ActionPlayer:
	var p := ch.get_node_or_null("ActionPlayer") as ActionPlayer
	if p == null:
		p = ActionPlayer.new()
		p.name = "ActionPlayer"
		p.c = ch
		ch.add_child(p)
	return p


## May this entry play now? A blocked entry (its body scan or the eye check failed) may not, except a fight's
## procedural strike (ctx.move): it plays MeleeBook's key poses with IK, not the clip, so the clip's scan does not
## apply to it.
static func allowed(id: String, ctx := {}) -> bool:
	var e := entry(id)
	if e.is_empty():
		return false
	return not bool(e.get("blocked", true)) or bool(ctx.get("force", false)) or ctx.has("move")


## Plays one catalog entry. Awaitable; returns {ok, why, ...}.
func play(id: String, ctx := {}) -> Dictionary:
	var e := entry(id)
	if e.is_empty():
		return _row(id, {"ok": false, "why": "no catalog entry"})
	if not allowed(id, ctx):
		return _row(id, {"ok": false, "why": "blocked: " + String(e.get("block_reason", e.get("status", "")))})
	if busy:
		return _row(id, {"ok": false, "why": "busy with " + current})
	busy = true
	current = id
	var t0 := Time.get_ticks_msec()
	var r: Dictionary
	match String(e.behaviour):
		"strike": r = await _b_strike(e, ctx)
		"strike_aerial": r = await _b_strike_aerial(e, ctx)
		"cast": r = await _b_cast(e, ctx)
		"cast_hold": r = await _b_cast_hold(e, ctx)
		"ultimate": r = await _b_ultimate(e, ctx)
		"ultimate_duo": r = await _b_ultimate_duo(e, ctx)
		"move": r = await _b_move(e, ctx)
		"move_acrobatic": r = await _b_move_acrobatic(e, ctx)
		"evade": r = await _b_evade(e, ctx)
		"defend": r = await _b_defend(e, ctx)
		"react": r = await _b_react(e, ctx)
		"react_floor": r = await _b_react_floor(e, ctx)
		"partner": r = await _b_partner(e, ctx)
		"idle_loop": r = await _b_idle_loop(e, ctx)
		"social": r = await _b_social(e, ctx)
		"prop": r = await _b_prop(e, ctx)
		"prop_seated": r = await _b_prop_seated(e, ctx)
		"pose_loop": r = await _b_pose_loop(e, ctx)
		"dance": r = await _b_dance(e, ctx)
		"dance_partner": r = await _b_dance_partner(e, ctx)
		"contact_world": r = await _b_contact_world(e, ctx)
		"world_magic": r = await _b_world_magic(e, ctx)
		"mischief": r = await _b_mischief(e, ctx)
		"mischief_partner": r = await _b_mischief_partner(e, ctx)
		_:
			r = {"ok": false, "why": "no behaviour " + String(e.behaviour)}
	busy = false
	current = ""
	r["ms"] = Time.get_ticks_msec() - t0
	return _row(id, r)


func _row(id: String, r: Dictionary) -> Dictionary:
	var row := r.duplicate()
	row["entry"] = id
	row["who"] = String(c.character_id) if c else ""
	row.erase("target")
	log.append(row)
	print("[action] %s" % JSON.stringify(row))
	return r


# ================================================================================================ the behaviours
# (one function each; an entry's fields are their settings)

## Procedural key poses from the clip's timing: in a fight the MeleeSim's strike (its IK lands it on her real
## surface); elsewhere the clip itself (shadow practice).
func _b_strike(e: Dictionary, ctx: Dictionary) -> Dictionary:
	if ctx.has("sim") and ctx.has("move"):
		(ctx.sim as MeleeSim)._attack(ctx.s, ctx.o, String(ctx.move))
		return {"ok": true, "how": "fight strike " + String(ctx.move)}
	await _clip(e, ctx)
	return {"ok": true, "how": "clip"}


func _b_strike_aerial(e: Dictionary, ctx: Dictionary) -> Dictionary:
	return await _b_strike(e, ctx)


## A spell's gesture: in a fight through the GestureDirector (face, plant, gather at the hand, aim, release at the
## clip's frame); elsewhere the gesture with a visible gather and release at the entry's times.
func _b_cast(e: Dictionary, ctx: Dictionary) -> Dictionary:
	if ctx.has("sim"):
		var sim: MeleeSim = ctx.sim
		var spell := String(ctx.get("spell", ""))
		var over: Dictionary = ctx.get("over", {})
		if sim.gestures:
			var ok := sim.gestures.request(ctx.s, ctx.o, spell, over)
			return {"ok": ok, "why": "" if ok else "director busy", "how": "gesture director"}
		sim.magic.cast(ctx.s, ctx.o, spell, over)
		return {"ok": true, "how": "magic caster"}
	return await _magic_free(e, ctx, false)


func _b_cast_hold(e: Dictionary, ctx: Dictionary) -> Dictionary:
	return await _b_cast(e, ctx)


func _b_ultimate(e: Dictionary, ctx: Dictionary) -> Dictionary:
	if ctx.has("sim"):
		var L := UltimateCast.perform(ctx.sim, String(ctx.s.id), String(ctx.o.id), String(e.id))
		return {"ok": L > 0.0, "how": "ultimate cinematic"}
	return await _magic_free(e, ctx, false)


## Both girls play their halves, started together; their contact points meet.
func _b_ultimate_duo(e: Dictionary, ctx: Dictionary) -> Dictionary:
	var t := WorldTargets.partner(c)
	if t.is_empty():
		return {"ok": false, "why": "needs her partner"}
	var other: WorldCharacter = t.node
	await _turn_to(other.global_position)
	var po := ActionPlayer.of(other)
	if not po.busy:
		po.play(String(e.id), {"force": ctx.get("force", false), "as_partner": true})
	await _clip(e, ctx)
	return {"ok": true, "how": "duo"}


func _b_move(e: Dictionary, ctx: Dictionary) -> Dictionary:
	if ctx.has("sim"):
		var sim: MeleeSim = ctx.sim
		sim.d.anim(String(ctx.s.id), "ml_" + String(e.id), float(e.start_s), float(e.end_s), 1.0, float(e.get("blend_in_s", 0.15)))
		return {"ok": true, "how": "fight footwork"}
	await _clip(e, ctx)
	return {"ok": true}


func _b_move_acrobatic(e: Dictionary, ctx: Dictionary) -> Dictionary:
	return await _b_move(e, ctx)


func _b_evade(e: Dictionary, ctx: Dictionary) -> Dictionary:
	return await _b_move(e, ctx)


func _b_defend(e: Dictionary, ctx: Dictionary) -> Dictionary:
	return await _b_move(e, ctx)


## A reaction plays from the real blow (in a fight the HitReactions system owns it); elsewhere the clip.
func _b_react(e: Dictionary, ctx: Dictionary) -> Dictionary:
	await _clip(e, ctx)
	return {"ok": true}


func _b_react_floor(e: Dictionary, ctx: Dictionary) -> Dictionary:
	await _clip(e, ctx)
	return {"ok": true}


## Needs her partner in range: she goes to her, faces her and plays.
func _b_partner(e: Dictionary, ctx: Dictionary) -> Dictionary:
	var t: Dictionary = ctx.get("target", WorldTargets.partner(c))
	if t.is_empty():
		return {"ok": false, "why": "needs her partner"}
	if not await _go(t):
		return {"ok": false, "why": "could not reach her partner"}
	await _clip(e, ctx)
	return {"ok": true}


func _b_idle_loop(e: Dictionary, ctx: Dictionary) -> Dictionary:
	await _clip(e, ctx, {"loop": true, "hold": float(ctx.get("hold", 4.0))})
	return {"ok": true}


## Waves, bows, taunts: to whoever she greets (her partner, the camera).
func _b_social(e: Dictionary, ctx: Dictionary) -> Dictionary:
	var t := WorldTargets.partner(c)
	if not t.is_empty():
		await _turn_to((t.node as Node3D).global_position)
	await _clip(e, ctx)
	return {"ok": true}


## A prop in her hand (a lantern, a stick): only if the world has one for her; otherwise refused (no prop drawn from
## nothing).
func _b_prop(e: Dictionary, ctx: Dictionary) -> Dictionary:
	var prop := String(e.get("prop", ""))
	if prop != "" and not ctx.has("prop_node"):
		return {"ok": false, "why": "needs the %s prop in the world" % prop}
	await _clip(e, ctx)
	return {"ok": true}


func _b_prop_seated(e: Dictionary, ctx: Dictionary) -> Dictionary:
	var t := WorldTargets.seat(c)
	if t.is_empty():
		return {"ok": false, "why": "no seat near"}
	return await _b_prop(e, ctx)


## Sits, leans or lies on a real surface found in the world, the hold segment loops.
func _b_pose_loop(e: Dictionary, ctx: Dictionary) -> Dictionary:
	var id := String(e.id)
	var kind := "ground"
	if id.begins_with("sit_dangle") or id.begins_with("lean_rail"):
		kind = "seat"
	var t: Dictionary = ctx.get("target", WorldTargets.find(c, kind))
	if t.is_empty():
		return {"ok": false, "why": "no %s near for %s" % [kind, id]}
	if kind != "ground" and not await _go(t):
		return {"ok": false, "why": "could not reach the " + kind}
	await _clip(e, ctx, {"loop": true, "hold": float(ctx.get("hold", 5.0))})
	return {"ok": true, "target": t, "where": kind}


## Song synced: the section picks the clip (the dance director calls with the entry); the clip on the beat.
func _b_dance(e: Dictionary, ctx: Dictionary) -> Dictionary:
	await _clip(e, ctx)
	return {"ok": true}


func _b_dance_partner(e: Dictionary, ctx: Dictionary) -> Dictionary:
	var t := WorldTargets.partner(c)
	if t.is_empty():
		return {"ok": false, "why": "needs her partner"}
	await _turn_to((t.node as Node3D).global_position)
	var at := float(e.get("contact_s", -1.0)) if e.get("contact_s") != null else -1.0
	if at >= 0.0:
		_touch_at(e, t, at - float(e.start_s), "partner")
	await _clip(e, ctx)
	return {"ok": true}


## Walks to the real target, faces it, plays the clip; at the contact time her lead hand (or foot) is put on its real
## surface; the target reacts.
func _b_contact_world(e: Dictionary, ctx: Dictionary) -> Dictionary:
	var kind := _target_kind(String(e.id))
	var t: Dictionary = ctx.get("target", WorldTargets.find(c, kind))
	if t.is_empty():
		return {"ok": false, "why": "no %s near" % kind}
	if not await _go(t):
		return {"ok": false, "why": "could not reach the " + kind}
	var at := float(e.contact_s) - float(e.start_s) if e.get("contact_s") != null else 0.5
	_touch_at(e, t, at, kind)
	await _clip(e, ctx)
	return {"ok": true, "target": t, "kind": kind, "point": t.point}


## A cast at a world target: a real visible result where the spell lands, fading after.
func _b_world_magic(e: Dictionary, ctx: Dictionary) -> Dictionary:
	return await _magic_free(e, ctx, true)


func _b_mischief(e: Dictionary, ctx: Dictionary) -> Dictionary:
	await _clip(e, ctx)
	return {"ok": true}


## Needs her partner, and the partner reacts (a jump, a laugh, a shield, a chase back).
func _b_mischief_partner(e: Dictionary, ctx: Dictionary) -> Dictionary:
	var t := WorldTargets.partner(c)
	if t.is_empty():
		return {"ok": false, "why": "needs her partner"}
	var id := String(e.id)
	if not (id in ["chase_run_laugh", "blow_raspberry_run"]) and not await _go(t):
		return {"ok": false, "why": "could not reach her partner"}
	var at := float(e.contact_s) - float(e.start_s) if e.get("contact_s") != null else float((e.get("release_s", [1.0]) as Array)[0]) - float(e.start_s)
	if id in ["tickle_magic_poke", "pull_hair_tease", "roll_eyes_shove", "splash_water_tease"]:
		_touch_at(e, t, at, "partner")
	else:
		get_tree().create_timer(maxf(at, 0.05)).timeout.connect(func(): _partner_reacts(t.node, id))
	await _clip(e, ctx)
	return {"ok": true, "target": t}


# ================================================================================================ shared parts

## The entry's clip through her one pipeline. Returns when it ends (plus its blend out).
func _clip(e: Dictionary, ctx: Dictionary, opts := {}) -> void:
	var start := float(e.get("start_s", 0.0))
	var end := float(e.get("end_s", 3.0))
	var sr: Array = e.get("speed_range", [0.85, 1.15])
	var pace := clampf(float(opts.get("pace", 1.0)), float(sr[0]), float(sr[1]))
	var bin := float(e.get("blend_in_s", 0.15))
	var bout := float(e.get("blend_out_s", 0.2))
	var loop := bool(opts.get("loop", false))
	var clip := "ml_" + String(e.id)
	if ctx.has("sim"):
		var sim: MeleeSim = ctx.sim
		var dur: float = sim.d.anim(String(ctx.s.id), clip, start, end, pace, bin, loop)
		await get_tree().create_timer(float(opts.get("hold", dur)) if loop else dur).timeout
		return
	if not c.has_clip(clip):
		push_warning("[action] %s has no clip %s" % [c.character_id, clip])
		return
	var bt := c.anim_tree.tree_root as AnimationNodeBlendTree
	var node := bt.get_node("cast_anim") as AnimationNodeAnimation
	node.use_custom_timeline = true
	node.start_offset = start
	node.timeline_length = maxf(end - start, 0.1)
	node.stretch_time_scale = false
	node.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	c.anim_tree.set("parameters/gesture_speed/scale", pace)
	var ok := c.play_gesture(clip, bin, bout)
	if not ok:
		node.use_custom_timeline = false
		return
	var dur2 := (end - start) / pace
	await get_tree().create_timer(float(opts.get("hold", dur2)) if loop else dur2).timeout
	if loop:
		c.end_gesture()
	await get_tree().create_timer(bout).timeout
	node.use_custom_timeline = false
	node.loop_mode = Animation.LOOP_NONE
	c.anim_tree.set("parameters/gesture_speed/scale", 1.0)


## Walk to a target's stand point and face it. False if she could not get there (12 s at most).
func _go(t: Dictionary) -> bool:
	var stand: Vector3 = t.stand
	if WorldTargets._flat(c.global_position - stand).length() > 0.35:
		var res := {"done": false, "ok": false}
		var cb := func(action: String, ok: bool, _d: String):
			if action == "navigate_to":
				res.done = true
				res.ok = ok
		c.action_finished.connect(cb)
		c.navigate_to(stand)
		var t0 := Time.get_ticks_msec()
		while not bool(res.done) and Time.get_ticks_msec() - t0 < 12000:
			await get_tree().process_frame
		c.action_finished.disconnect(cb)
		if WorldTargets._flat(c.global_position - stand).length() > 0.8:
			return false
	await _turn_to(t.face)
	return true


## Turn her body to face a point (0.3 s).
func _turn_to(p: Vector3) -> void:
	var d := WorldTargets._flat(p - c.global_position)
	if d.length() < 0.05:
		return
	var yaw := atan2(-d.x, -d.z)
	var tw := c.create_tween()
	tw.tween_method(func(k: float): c.rotation.y = lerp_angle(c.rotation.y, yaw, k), 0.0, 1.0, 0.3)
	await tw.finished


## At `at` seconds from the clip's start, her lead hand goes to the target's real surface (arm IK in 0.18 s, held to
## the end of the contact, out in 0.25 s), the contact is logged and the target reacts.
func _touch_at(e: Dictionary, t: Dictionary, at: float, kind: String) -> void:
	var lead := String(e.get("lead_limb", "rh"))
	if lead in ["rf", "lf"]:
		get_tree().create_timer(maxf(at, 0.05)).timeout.connect(func(): _reacts(e, t, kind, t.point))
		return
	var left := lead == "lh"
	var hold := 0.5
	if e.get("hold_s") != null:
		hold = maxf(float(e.hold_s[1]) - float(e.hold_s[0]), 0.3)
	get_tree().create_timer(maxf(at - 0.18, 0.02)).timeout.connect(func():
		var h := c.handler
		if h == null:
			return
		var ik: TwoBoneIK3D = h.ik_left if left else h.ik
		var tg: Node3D = h.target_left if left else h.target
		var pole: Node3D = h.pole_left if left else h.pole
		if ik == null or tg == null:
			return
		var hand: Node3D = c.left_hand if left else c.right_hand
		# the IK puts the wrist: aim it so the palm lands on the surface point
		var palm_off: Vector3 = hand.global_transform.basis * ObjectHandler.PALM
		var p: Vector3 = t.point
		tg.global_position = p - palm_off
		var fwd := -c.global_transform.basis.z
		var side := Vector3(-fwd.z, 0, fwd.x) * (-1.0 if left else 1.0)
		pole.global_position = c.global_position + Vector3(0, 1.0, 0) + side * 0.6 - fwd * 0.2
		var tw := c.create_tween()
		tw.tween_property(ik, "influence", 1.0, 0.18)
		tw.tween_callback(func():
			contact_made.emit(String(e.id), t, p)
			print("[action] contact %s %s %s at %s frame %d" % [c.character_id, e.id, kind, str(p.snappedf(0.01)), Engine.get_frames_drawn()])
			_reacts(e, t, kind, p))
		tw.tween_interval(hold)
		tw.tween_property(ik, "influence", 0.0, 0.25))


## The target answers the touch.
func _reacts(e: Dictionary, t: Dictionary, kind: String, p: Vector3) -> void:
	var host := c.get_parent()
	match kind:
		"tree":
			var n: Node3D = t.node
			var crown := Vector3(n.global_position.x, n.global_position.y + 3.2, n.global_position.z)
			var strong := String(e.id) in ["kick_tree_shake", "punch_tree_ouch"]
			WorldFX.leaves(host, crown, 40 if strong else 12, 3.0 if strong else 2.2)
			WorldFX.sway(n, 0.05 if strong else 0.02, 1.4)
		"flower":
			WorldFX.bob(t.node, 1.0)
			WorldFX.petals(host, p, 10)
		"water":
			WorldFX.splash(host, p, 0.6)
		"partner":
			_partner_reacts(t.node, String(e.id))
		_:
			WorldFX.dust(host, p, 8)


## Her partner's answer to a mischief: a jump, a laugh, a shield, a chase back (from the catalog, through her own
## action player).
func _partner_reacts(other: WorldCharacter, id: String) -> void:
	var answer: String = {"sneak_up_scare": "hit_light", "tickle_magic_poke": "victory_dance_silly", "pull_hair_tease": "roll_eyes_shove",
		"splash_water_tease": "dodge_right", "roll_eyes_shove": "hit_light", "chase_run_laugh": "chase_run_laugh",
		"blow_raspberry_run": "taunt_beckon", "stick_sword_play": "block_side_right"}.get(id, "hit_light")
	var po := ActionPlayer.of(other)
	if not po.busy:
		po._turn_to(c.global_position)
		po.play(answer, {"force": false})


## A spell outside a fight: her gesture with the energy gathering at her hand and a real visible result at the release
## (in front of her, or on the world target for world magic), fading after.
func _magic_free(e: Dictionary, ctx: Dictionary, world: bool) -> Dictionary:
	var start := float(e.get("start_s", 0.0))
	var g = e.get("gather_s")
	var rel: Array = e.get("release_s", [])
	var lead := String(e.get("lead_limb", "rh"))
	var col := Color(0.55, 0.85, 1.0) if String(c.character_id) == "mika" else Color(0.75, 0.55, 1.0)
	var host := c.get_parent()
	if g != null:
		get_tree().create_timer(maxf(float(g[0]) - start, 0.02)).timeout.connect(func():
			WorldFX.glow_hand(host, (c.left_hand if lead == "lh" else c.right_hand), col, maxf(float(g[1]) - float(g[0]), 0.3)))
	var at := (float(rel[0]) if not rel.is_empty() else float(e.get("end_s", 2.0)) * 0.6) - start
	var fwd := WorldTargets._flat(-c.global_transform.basis.z).normalized()
	var p := c.global_position + fwd * 2.0
	get_tree().create_timer(maxf(at, 0.05)).timeout.connect(func():
		WorldFX.magic_result(host, String(e.id), p, col)
		print("[action] magic %s %s result at %s frame %d" % [c.character_id, e.id, str(p.snappedf(0.01)), Engine.get_frames_drawn()]))
	await _clip(e, ctx)
	return {"ok": true, "point": p}


func _target_kind(id: String) -> String:
	if id.contains("tree") or id == "hide_behind_peek":
		return "tree"
	if id.contains("flower") and not id.begins_with("cast"):
		return "flower"
	if id.contains("water") or id.contains("puddle"):
		return "water"
	if id.contains("petal") or id.contains("pebble"):
		return "ground"
	return "ground"
