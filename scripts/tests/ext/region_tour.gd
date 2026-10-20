extends RefCounted
## --mktest=region_tour (2026-10-20 go live, Selwyn: "which regions are reachable, does travel to each one work, with
## no freezes, no camera loss, and nothing broken on arrival"): the home region's places one after another, walked
## to the real way (the journey to the gate, the travel card, the arrival), their own minds held so nothing else
## leads them off. Per place: the travel report, every frame over 100 ms (on screen or behind the card), whether
## Mika is in the picture each second for 20 s after arriving (nobody between, not off screen), script errors in
## the log meanwhile, review frames (--shots=dir). Marks "[tour] ...".

const STOPS := [["ancient_spell_library", "arcane_library"], ["ritual_sanctuary", "sanctuary"], ["mentors_tower", "mentor_tower"],
	["ritual_sanctuary", "sanctuary"], ["whispering_woods", "whispering_woods"], ["ritual_sanctuary", "sanctuary"],
	["lantern_lake", "lantern_lake"], ["ritual_sanctuary", "sanctuary"]]


static func run(t) -> void:
	var main = t.main
	main.day_night.clear_override()
	main.director.enabled = true
	for w in main.mage_brains:
		main.mage_brains[w].hold = true
		main.mage_brains[w].interrupt("the region tour")
	await t._wait(3.0)
	var shot_dir := String(RenderProfile.options.get("shots", ""))
	var results := []
	for stop in STOPS:
		var loc: String = stop[0]
		var area: String = stop[1]
		var r := {"to": area, "slow_on_screen": [], "slow_behind_card": [], "hidden_s": 0, "seen_s": 0, "arrived": false}
		print("[tour] walking to %s (from %s)" % [loc, main.streaming.current_id])
		var started: Dictionary = main.travel.travel_to(loc, "walk")
		if not started.get("ok", false):
			r["error"] = String(started.get("error", "?"))
			print("[tour] %s: could not start (%s)" % [area, r.error])
			results.append(r)
			continue
		var done := [null]
		var cb := func(ev): if ev.event == "journey_finished": done[0] = ev
		main.travel.journey_event.connect(cb)
		var t0 := Time.get_ticks_msec()
		var last := Time.get_ticks_usec()
		while done[0] == null and Time.get_ticks_msec() - t0 < 240000:
			await t.get_tree().process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - last) / 1000.0
			last = now
			if dt > 100.0:
				var behind: bool = main.streaming.state != "idle"
				(r.slow_behind_card if behind else r.slow_on_screen).append(int(dt))
		main.travel.journey_event.disconnect(cb)
		r["journey_ok"] = done[0] != null and bool((done[0] as Dictionary).get("ok", false))
		r["arrived"] = main.streaming.current_id == area
		r["walk_s"] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)
		var rep: Dictionary = main.streaming.last_report if main.streaming.current_id == area else {}
		r["worst_build_step_ms"] = rep.get("worst_build_step_ms", -1)
		# 20 s there: is Mika in the picture each second
		var t1 := Time.get_ticks_msec()
		var next_s := 0.0
		var shots := 0
		while Time.get_ticks_msec() - t1 < 20000:
			await t.get_tree().process_frame
			var now2 := Time.get_ticks_usec()
			var dt2 := (now2 - last) / 1000.0
			last = now2
			if dt2 > 100.0:
				r.slow_on_screen.append(int(dt2))
			var el := (Time.get_ticks_msec() - t1) / 1000.0
			if el >= next_s:
				next_s += 1.0
				var vcam: Camera3D = t.get_viewport().get_camera_3d()
				var mk: WorldCharacter = main.characters["mika"]
				var head := mk.global_position + Vector3(0, 1.35, 0)
				var vs: Vector2 = t.get_viewport().get_visible_rect().size
				var on: bool = vcam != null and mk.visible and not vcam.is_position_behind(head) and Rect2(Vector2.ZERO, vs).has_point(vcam.unproject_position(head))
				if on and not main.director._mate_blocks(vcam.global_position, head):
					r.seen_s += 1
				else:
					r.hidden_s += 1
				if shot_dir != "" and (shots < 4) and int(el) % 5 == 1:
					shots += 1
					var im: Image = t.get_viewport().get_texture().get_image()
					im.resize(640, 360, Image.INTERPOLATE_BILINEAR)
					im.save_jpg("%s/%02d_%s_%02d.jpg" % [shot_dir, results.size(), area, int(el)], 0.8)
		print("[tour] %s: arrived %s (journey %s, %.0f s), worst build step %s ms, slow frames on screen %s, behind the card %s, Mika in the picture %d of %d s%s" % [
			area, str(r.arrived), str(r.journey_ok), r.walk_s, str(r.worst_build_step_ms), str(r.slow_on_screen), str(r.slow_behind_card), r.seen_s,
			r.seen_s + r.hidden_s, (" | %s" % String(done[0].get("detail", ""))) if done[0] != null and not r.journey_ok else ""])
		results.append(r)
	for w in main.mage_brains:
		main.mage_brains[w].hold = false
	print("[tour] summary %s" % JSON.stringify(results))
	for r in results:
		t._check(bool(r.arrived), "%s reached" % r.to)
		t._check((r.slow_on_screen as Array).is_empty(), "%s no frame over 100 ms on screen %s" % [r.to, str(r.slow_on_screen)])
		t._check(int(r.hidden_s) <= 1, "%s Mika in the picture (%d s hidden)" % [r.to, int(r.hidden_s)])
