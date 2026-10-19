extends RefCounted
## --mktest=fight_probe: the duel's candidate clips on Mika at the training clearing (FightDeck + softness pass):
## prints each clip's length; with a display, saves 6 frames per clip (side view) to screenshots/mktest/fprobe_*.png
## for a pose contact sheet. --fp-clips=a,b limits the list.

const CLIPS := ["combat_idle", "cast_quick", "magic_attack_1h", "magic_attack_2h", "wide_arm_spell", "prepare_and_cast", "spell_casting",
	"brace", "hit_chest", "hit_head", "hit_knockback", "dodge_dash", "lift_off", "land_soft", "victory_nod", "rx_fall_back",
	"rx_sit_up", "rx_stand_from_sit", "rx_reach_help", "sword:great_sword_power_up", "sword:great_sword_kick", "sword:great_sword_kick_2",
	"sword:great_sword_jump_attack", "sword:great_sword_jump", "sword:great_sword_high_spin_attack", "sword:great_sword_slide_attack",
	"sword:great_sword_blocking", "sword:great_sword_strafe", "sword:great_sword_strafe_2", "sword:great_sword_impact",
	"sword:great_sword_impact_3", "sword:spell_cast", "sword:great_sword_casting", "ual:Roll", "ual_react:NinjaJump_Land",
	"ual_react:OverhandThrow", "ual:Idle_Shield_Loop", "sword:great_sword_slash", "sword:great_sword_slash_3", "sword:great_sword_idle_2"]


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var center := SanctuaryTerrain.TRAINING_CENTER_3D
	for id in main.characters:
		var c: WorldCharacter = main.characters[id]
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
		c.set_physics_process(false)
		c.visible = id == "mika"
	var y := FightDirector.ground_y(mika, center)
	mika.global_position = Vector3(center.x, y, center.z)
	FightDirector.face(mika, Vector3(0, 0, 1))
	var deck := FightDeck.make(mika)
	BodyLife.make(mika.skeleton, 1)
	SoftArms.make(mika.skeleton, 2)
	for cl in t.get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	for g in t.get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	pin.fov = 40.0
	pin.active = true
	var p0 := mika.global_position
	pin.pos = p0 + Vector3(3.6, 1.1, 1.2)
	pin.look = p0 + Vector3(0, 0.95, 0)
	var list: Array = CLIPS
	if RenderProfile.options.has("fp-clips"):
		list = String(RenderProfile.options.get("fp-clips")).split(",")
	await t._wait(1.0)
	for clip in list:
		var L := FightDeck.clip_length(mika, clip)
		print("[fprobe] %s length %.2f" % [clip, L])
		if L <= 0.0:
			continue
		deck.play(clip, 0.0, -1.0, 1.0, 0.05)
		for k in 6:
			var tt := L * (k + 0.5) / 6.0
			deck._cur.t = tt
			deck._prev = {}
			await t._wait(0.12)
			var hp := mika.skeleton.global_transform * mika.skeleton.get_bone_global_pose(mika.skeleton.find_bone("Hips")).origin
			if k == 0 or k == 3:
				print("[fprobe]   %s t %.2f hips y %.2f" % [clip, tt, hp.y - p0.y])
			t._shot("fprobe_%s_%d" % [clip.replace(":", "_"), k])
