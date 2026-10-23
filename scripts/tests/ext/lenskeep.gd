extends RefCounted
## --mktest=lenskeep (23 Oct, Selwyn: "fix that white crystal in the camera"): the floating altar crystal and the
## Heartstone had no body, the lens slid up to them and a glowing crystal filled the picture. Both now keep the lens
## out (ThirdPersonCamera.keep_lens_out). Mika and Luna stand, talk and walk round the altar and the Heartstone with
## the camera director as on stream; twice a second, how close the lens comes to either crystal. Marks frames.


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("lens keep")
	await t._hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = true
	if main.streaming.current_id != "sanctuary":
		await main.streaming.travel("sanctuary", main.characters["mika"], false)
	await t._wait(3.0)
	var world = main.world
	var crystals := []
	if world.get("altar_crystal"):
		crystals.append(["altar crystal", world.altar_crystal])
	var hs: Node = world.find_child("AnimatedHeartstone", true, false)
	if hs:
		crystals.append(["Heartstone", hs])
	print("[lenskeep] keep-outs in the sanctuary: %d" % world.find_children("LensKeepOut", "StaticBody3D", true, false).size())
	for ko in world.find_children("LensKeepOut", "StaticBody3D", true, false):
		var q0 := PhysicsPointQueryParameters3D.new()
		q0.position = (ko as Node3D).global_position + Vector3(0.3, 0, 0)
		q0.collision_mask = ThirdPersonCamera.LENS_ONLY
		print("[lenskeep] keep-out at %s layer %d in tree %s, point query hits %d" % [str((ko as Node3D).global_position), (ko as StaticBody3D).collision_layer,
			(ko as Node).is_inside_tree(), main.characters["mika"].get_world_3d().direct_space_state.intersect_point(q0, 4).size()])
	var mc: WorldCharacter = main.characters["mika"]
	var lc: WorldCharacter = main.characters.get("luna")
	var map := mc.get_world_3d().navigation_map
	var nearest := 99.0
	var n := 0
	for item in crystals:
		var c: Vector3 = (item[1] as Node3D).global_position
		for k in 6:
			var a := k * TAU / 6.0
			var p := NavigationServer3D.map_get_closest_point(map, c + Vector3(cos(a), 0, sin(a)) * 1.6)
			for ch in [mc, lc]:
				if ch and main.teleport_guard:
					main.teleport_guard.allow(ch)
			mc.global_position = p
			mc.look_at_point(c)
			if lc:
				lc.global_position = NavigationServer3D.map_get_closest_point(map, p + Vector3(cos(a + 1.2), 0, sin(a + 1.2)) * 1.4)
			# standing a while (the two-shot), then a few steps past the crystal (the follow lens)
			var t0 := Time.get_ticks_msec()
			var walked := false
			while Time.get_ticks_msec() - t0 < 7000:
				await t._wait(0.5)
				if not walked and Time.get_ticks_msec() - t0 > 3500:
					walked = true
					mc.navigate_to(NavigationServer3D.map_get_closest_point(map, c - (p - c).normalized() * 3.0), false)
				var cam: Camera3D = t.get_viewport().get_camera_3d()
				for it2 in crystals:
					var d: float = cam.global_position.distance_to((it2[1] as Node3D).global_position)
					nearest = minf(nearest, d)
					if d < 0.9:
						print("[lenskeep] lens %.2f m from the %s, mode %s at frame %d | director pos %.2f m from it, cam==rig %s, shot_active %s" % [d, it2[0], main.director.mode, Engine.get_frames_drawn(),
							(main.director._pos as Vector3).distance_to((it2[1] as Node3D).global_position), cam == main.director.rig.camera, main.director.rig.shot_active])
				n += 1
			print("[lenskeep] %s side %d at frame %d nearest so far %.2f" % [item[0], k, Engine.get_frames_drawn(), nearest])
			mc.stop_action()
	print("[lenskeep] %d samples, the lens never closer than %.2f m to a crystal" % [n, nearest])
	t._check(nearest >= 0.8, "the lens keeps out of the crystals (closest %.2f m)" % nearest)
