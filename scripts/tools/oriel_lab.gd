extends Node3D
## ORIEL LAB (visual pass 2): Oriel's two bodies under the Whispering Woods' daylight (the same HDRI sky, sun
## angle, AgX tonemap and bloom as the area) on a mossy stone floor, without loading the world - for fast,
## honest iteration on her look, her attack and her transformation. Writes PNG stills.
##   godot --path . res://scenes/tools/oriel_lab.tscn -- --out=res://screenshots/oriel_lab --lab=true|human|attack|tf|reform
##   [--views=front,front34,...] [--clip=majestic]

var rig: PhoenixTrueRig
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var out := "res://screenshots/oriel_lab"
var report := {}


func _ready() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := PanoramaSkyMaterial.new()
	psm.panorama = load("res://assets/polyhaven/hdris/nature_reserve_forest/nature_reserve_forest_2k.hdr")
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.34
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.88
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, [0.0, 0.6, 1.0, 1.0, 0.8, 0.5, 0.0][i])
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.2
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, 150, 0)
	sun.light_energy = 3.1
	sun.light_color = Color(1, 0.9, 0.74)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	floor_mi.material_override = RealKit.stone_mat("mossy_stone_wall", false)
	add_child(floor_mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	out = String(RenderProfile.options.get("out", out))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	_run.call_deferred()


func _look(pos: Vector3, at: Vector3, fov := 40.0) -> void:
	cam.global_position = pos
	cam.look_at(at)
	cam.fov = fov


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var im := get_viewport().get_texture().get_image()
	im.convert(Image.FORMAT_RGB8)
	im.save_png("%s/%s.png" % [out, name])
	print("[lab] wrote ", name)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


const VIEWS := {
	"front": [Vector3(0, 2.6, 12.5), Vector3(0, 2.7, 0), 44.0],
	"front34": [Vector3(-7.5, 2.4, 9.5), Vector3(0, 2.3, 0), 42.0],
	"side": [Vector3(11, 2.2, 0.5), Vector3(0, 2.0, 0.3), 42.0],
	"back34": [Vector3(6.5, 3.6, -8.5), Vector3(0, 2.2, 0), 42.0],
	"low": [Vector3(-3.5, 0.6, 7.5), Vector3(0, 3.0, 0), 50.0],
	"head": [Vector3(-1.4, 3.0, 3.2), Vector3(0, 2.85, 1.3), 30.0],
}


func _run() -> void:
	var lab := String(RenderProfile.options.get("lab", "true"))
	match lab:
		"true":
			await _true_form()
		"human":
			await _human_form()
		"tf", "tf_short", "reform":
			await _human_tf(lab)
		"attack":
			await _attack()
		"fx":
			await _fx()
		"creature":
			await _creature()
		"gripcal":
			await _gripcal()
		"rivals":
			await _rivals()
		_:
			print("[lab] unknown lab ", lab)
	var f := FileAccess.open(out + "/oriel_lab.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	get_tree().quit()


func _true_form() -> void:
	rig = PhoenixTrueRig.new()
	add_child(rig)
	rig.build()
	rig.rotation.y = 0.0               # she faces +Z (toward the front camera)
	var clips := String(RenderProfile.options.get("clip", "majestic,idle")).split(",")
	var views := String(RenderProfile.options.get("views", "front,front34,side,head,low")).split(",")
	for c in clips:
		rig.play_clip(c, 0.0, 1.0, true)
		await _wait(1.6)
		for v in views:
			var spec: Array = VIEWS[v]
			_look(spec[0], spec[1], spec[2])
			await _wait(0.25)
			await _grab("true_%s_%s" % [c, v])
	report["true_clips"] = clips


var human: PhoenixHuman

const HVIEWS := {
	"full": [Vector3(0, 1.0, 3.6), Vector3(0, 0.95, 0), 40.0],
	"full34": [Vector3(-2.2, 1.2, 2.9), Vector3(0, 0.95, 0), 40.0],
	"face": [Vector3(-0.25, 1.62, 0.85), Vector3(0, 1.55, 0), 30.0],
	"back": [Vector3(1.6, 1.3, -2.8), Vector3(0, 1.0, 0), 40.0],
	"wide": [Vector3(-1.2, 1.4, 5.2), Vector3(0, 1.2, 0), 46.0],
	"medium": [Vector3(-0.9, 1.3, 3.3), Vector3(0, 1.05, 0), 42.0],
}


func _spawn_human() -> void:
	human = PhoenixHuman.new()
	add_child(human)
	human.global_position = Vector3.ZERO
	human.rotation.y = PI                 # she faces +Z (the cameras)
	await _wait(1.2)
	var head := human.head_point()
	report["human_head_m"] = snappedf(head.y, 0.01)


func _human_form() -> void:
	await _spawn_human()
	for v in String(RenderProfile.options.get("views", "full,full34,face,back")).split(","):
		var spec: Array = HVIEWS[v]
		_look(spec[0], spec[1], spec[2])
		await _wait(0.3)
		await _grab("human_%s" % v)


func _human_tf(mode: String) -> void:
	await _spawn_human()
	var m := "cinematic" if mode == "tf" else ("short" if mode == "tf_short" else "reform")
	var marks: Array = {"cinematic": [0.25, 0.9, 1.9, 2.9, 3.3, 4.2, 4.8, 5.4, 6.1, 6.7], "short": [0.3, 0.8, 1.3, 2.0, 2.5], "reform": [0.5, 1.4, 2.2, 3.0, 3.6, 4.1]}[m]
	var total: float = PhoenixHuman.TF_LEN[m]
	var spec: Array = HVIEWS[String(RenderProfile.options.get("view", "medium"))]
	_look(spec[0], spec[1], spec[2])
	if m != "reform":
		human.tf_prepare()
		await _wait(2.5)
	human.tf_begin(m)
	var u := 0.0                      # game clock (run with --fixed-fps 30: stills never slip)
	var mi := 0
	while true:
		u += get_process_delta_time()
		human.tf_step(u)
		if mi < marks.size() and u >= float(marks[mi]):
			await _grab("tf_%s_%02d_%.1f" % [m, mi, u])
			mi += 1
		if u > total + 0.2:
			break
		await get_tree().process_frame
	human.tf_end()
	await _wait(0.8)
	await _grab("tf_%s_end" % m)


## The solar nova, standalone (the same beats as Phoenix.cast_nova): stills of the charge, the release, the flight
## and the detonation, from a side-front camera that holds her and the target.
func _attack() -> void:
	rig = PhoenixTrueRig.new()
	add_child(rig)
	rig.build()
	rig.play_clip("idle", 0.0, 1.0, true)
	await _wait(1.5)
	var tgt := Vector3(0, 0.9, 13.0)
	var v := String(RenderProfile.options.get("view", "side"))
	if v == "side":
		_look(Vector3(-10.5, 3.2, 5.0), Vector3(0, 1.9, 6.5), 52.0)
	else:
		_look(Vector3(-3.0, 2.2, -6.5), Vector3(0, 2.4, 4.0), 55.0)
	var nova := PhoenixNova.new()
	add_child(nova)
	rig.play_clip("attack_charge", 0.2, 1.0, false)
	rig.set_heat(1.0)
	rig.set_aura(1.0)
	rig.set_glow(1.6)
	rig.set_embers(1.0)
	var r := rig
	nova.charge(func() -> Vector3: return r.chest_point() + Vector3(0, 0.45, 1.6))
	var marks := [0.7, 1.5, 1.86, 2.05, 2.3, 2.45, 2.7, 3.1, 3.8, 4.6, 5.6, 7.0]
	var mi := 0
	var held := false
	var released := false
	var launched := false
	var recovered := false
	var u := 0.0
	while true:
		u += get_process_delta_time()
		if u >= 1.4 and not held:
			held = true
			rig.play_clip("attack_hold", 0.1, 1.0, true)
		if u >= 1.7 and not released:
			released = true
			rig.play_clip("attack_release", 0.05, 1.0, false)
		if u >= 1.84 and not launched:
			launched = true
			nova.launch(tgt, 1.0)
			ImpactFX.shockwave(self, rig.chest_point() + Vector3(0, 0, 1.0), Color(1.0, 0.6, 0.25), 5.5)
		if u >= 2.3 and not recovered:
			recovered = true
			rig.play_clip("attack_recover", 0.15, 1.0, false)
			rig.set_aura(0.0)
		if mi < marks.size() and u >= float(marks[mi]):
			await _grab("attack_%s_%02d_%.2f" % [v, mi, u])
			mi += 1
		if mi >= marks.size():
			break
		await get_tree().process_frame


## The cinematic pass's fire effects alone (FireFX), for tuning: a fire tornado growing, the ring of fire, the
## transformation burst, the wings of fire, a detonation.
func _fx() -> void:
	_look(Vector3(0, 3.0, 14.0), Vector3(0, 2.6, 0), 50.0)
	await _wait(0.5)
	var ring := FireFX.ring_of_fire(self, Vector3.ZERO, 3.1, 6.0, 0.6)
	var v := FireFX.vortex(self, Vector3.ZERO, 0.82)
	report["fx"] = {"vortex_cards": v.get_child_count(), "has_vortex": FireFX.has("vortex")}
	for k in 8:
		v.set_strength(0.3 + 0.1 * k)
		await _wait(0.4)
		if k in [0, 3, 7]:
			await _grab("fx_vortex_%d" % k)
		if k == 7:
			_look(Vector3(1.0, 1.6, 5.2), Vector3(0, 2.4, 0), 44.0)
			await _wait(0.1)
			await _grab("fx_vortex_close")
			_look(Vector3(0, 3.0, 14.0), Vector3(0, 2.6, 0), 50.0)
	v.set_strength(1.45)
	v.collapse(0.6)
	FireFX.card(self, "explosion", Vector3(0, 1.5, 0), 0.62, 1.7, {"fire_gain": 1.3, "fire_tint": Color(1.0, 0.7, 0.42), "smoke_alpha": 0.45})
	FireFX.card(self, "burst", Vector3(0, 1.0, 0), 1.4, 0.9, {"fire_gain": 1.5, "fire_tint": Color(1.0, 0.7, 0.42)}, 0.0, 1.2)
	await _wait(0.25)
	await _grab("fx_burst")
	await _wait(1.5)
	FireFX.fire_wings(self, Vector3(0, 1.25, 0), PI, 3.2, 2.6)
	await _wait(1.0)
	await _grab("fx_wings")
	await _wait(2.0)
	FireFX.explosion(self, Vector3(0, 1.0, 0), 1.3)
	for k in 5:
		await _wait(0.45)
		await _grab("fx_explosion_%d" % k)
	if is_instance_valid(ring):
		ring.queue_free()


## A hero-scene creature alone, built exactly as the game builds it (ClipRig from data/monsters.json "body"): its idle,
## the windup and the strike, from the front and three-quarter.
func _creature() -> void:
	var id := String(RenderProfile.options.get("creature", "briar_imp"))
	var defs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json")).monsters
	var cr := ClipRig.new()
	add_child(cr)
	cr.rotation.y = PI * 0.12
	cr.build(defs[id].body, Color(1.0, 0.55, 0.2))
	await _wait(1.0)
	# frame by its real size (a Mossback is three times an imp)
	var hgt := 0.0
	for mi in cr.find_children("*", "MeshInstance3D", true, false):
		var bb := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		hgt = maxf(hgt, bb.end.y)
	print("[lab] creature %s height %.2f m" % [id, hgt])
	var k := maxf(hgt / 1.6, 1.0)
	for st in ["idle", "alert", "windup", "strike", "move"]:
		cr.play(st)
		await _wait(0.45 if st != "idle" else 1.2)
		_look(Vector3(0.6, 1.25, 3.4) * k, Vector3(0, 0.95, 0) * k, 42.0)
		await _wait(0.05)
		await _grab("creature_%s_%s_front" % [id, st])
		_look(Vector3(2.6, 1.6, 2.2) * k, Vector3(0, 0.9, 0) * k, 42.0)
		await _wait(0.05)
		await _grab("creature_%s_%s_34" % [id, st])


## --lab=gripcal: the ronin holding the katana under six candidate hand rotations (sword idle), side by side.
func _gripcal() -> void:
	var rots := [[0, 0, 0], [0, 0, 90], [0, 0, -90], [90, 0, 0], [-90, 0, 0], [0, 90, 90]]
	for i in rots.size():
		var cr := ClipRig.new()
		add_child(cr)
		cr.position = Vector3((i - 2.5) * 1.6, 0, 0)
		var spec := {"glb": "res://assets/creatures/rivals/ronin.glb", "ground": true, "keep_materials": true, "scale": 1.0,
			"clips": {"idle": ["idle", 1.0, true]}, "weapons": [{"model": "antique_katana_01", "bone": "hand_r", "pos": [0, 0, 0], "rot": rots[i]}]}
		cr.build(spec, Color(1, 0.5, 0.2))
		var lbl := Label3D.new()
		lbl.text = str(rots[i])
		lbl.position = Vector3(0, 2.1, 0)
		lbl.pixel_size = 0.004
		cr.add_child(lbl)
	await _wait(1.5)
	_look(Vector3(0, 1.3, 7.5), Vector3(0, 1.0, 0), 50.0)
	await _wait(0.1)
	await _grab("gripcal_front")
	_look(Vector3(6.5, 1.4, 3.5), Vector3(0, 1.0, 0), 55.0)
	await _wait(0.1)
	await _grab("gripcal_side")


## --lab=rivals: the four human rivals with their weapons, in idle and mid-technique, front and three-quarter.
func _rivals() -> void:
	var defs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json")).monsters
	var ids := ["rival_cutthroat", "rival_shade", "rival_ronin", "rival_hexer"]
	var rigs := []
	for i in ids.size():
		if not defs.has(ids[i]):
			continue
		var cr := ClipRig.new()
		add_child(cr)
		cr.position = Vector3((i - 1.5) * 1.8, 0, 0)
		cr.build(defs[ids[i]].body, Color(1, 0.4, 0.3))
		rigs.append(cr)
	await _wait(1.5)
	for st in ["idle", "combo_strike", "dash_strike", "cast_strike"]:
		for cr in rigs:
			(cr as ClipRig).play(st)
		await _wait(0.55)
		_look(Vector3(0.0, 1.35, 6.8), Vector3(0, 1.0, 0), 50.0)
		await _wait(0.05)
		await _grab("rivals_%s_front" % st)
		_look(Vector3(5.5, 1.6, 4.5), Vector3(0, 0.95, 0), 55.0)
		await _wait(0.05)
		await _grab("rivals_%s_34" % st)
