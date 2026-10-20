extends RefCounted
## Which humanoid bones a Move Library bake leaves out (those keep whatever the body player shows under the clip).
## Marks "[tracks] ...".

static func run(t) -> void:
	await t._hold_all()
	var l: WorldCharacter = t.main.characters.luna
	var a := MocapBake.bake(l.skeleton, WorldCharacter.MOCAP_DIR + "orb_gather.json")
	var have := {}
	for i in a.get_track_count():
		have[String(a.track_get_path(i)).get_slice(":", 1) + ("@pos" if a.track_get_type(i) == Animation.TYPE_POSITION_3D else "")] = true
	var miss := PackedStringArray()
	var prof := SkeletonProfileHumanoid.new()
	for i in prof.bone_size:
		var bn := String(prof.get_bone_name(i))
		if l.skeleton.find_bone(bn) >= 0 and not have.has(bn):
			miss.append(bn)
	print("[tracks] bake has %d tracks %s" % [a.get_track_count(), ", ".join(PackedStringArray(have.keys()))])
	print("[tracks] humanoid bones not in the bake %s" % ", ".join(miss))
	var p := l.body_player
	print("[tracks] body player playing %s %s" % [p.current_animation, str(p.is_playing())])
	t._check(true, "listed")
