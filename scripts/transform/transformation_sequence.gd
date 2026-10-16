class_name TransformationSequence
extends Node
## The transformation cutscene: a full-screen video per form (made outside this project, converted with
## tools/transformations/convert.sh into assets/transformations/<character>_<level>.ogv) between two white-gold
## flashes. Embers and sound carry across each flash so the cut in and the cut back out feel like one shot.
##   in       the moment is saved (TfContinuity); a riser and embers start, the screen floods white-gold, the video
##            starts under the flash and the flash clears off it
##   video    plays full screen with its own sound; behind it she takes her new form (never seen changing)
##   out      near the video's end the flash floods in again (a shimmer and embers already rising over the video),
##            the video goes, the moment is put back exactly - she stands where she stood, in the same area, in her
##            new outfit, the camera where it was - the flash clears and the embers drift down round her
## A form with no video yet transforms on the flash alone (in, change, out). While it plays both planners hold and
## viewer replies wait (TransformationDirector.playing); no LLM and no TTS. After the first showing of a form a
## viewer can type "skip": it cuts straight to the flash out.

signal started(who: String, level: int, mode: String)
signal finished(who: String, result: Dictionary)
signal beat(name: String, t: float)

const VIDEO_DIR := "res://assets/transformations/"
const SOUND_DIR := "res://assets/audio/transformation/"
const FLASH := Color(1.0, 0.94, 0.8)            # white-gold
const FLASH_IN := 0.35
const FLASH_OUT := 0.6
const EXIT_LEAD := 0.45                         # the flash out starts this long before the video ends

static var data := {}

var main: Node
var director: Node
var playing := ""
var level := 0
var mode := "full"
var t := 0.0
var skip_requested := false
var skip_by := ""
var log: Array = []
var shots_dir := ""
var c: WorldCharacter
var fs := {}
var layer: CanvasLayer          # the video, full screen
var video: VideoStreamPlayer
var top: CanvasLayer            # the flash and the screen-space embers, over the video
var flash: ColorRect
var embers2d: GPUParticles2D
var embers3d: GPUParticles3D
var sfx_players: Array = []
var continuity_report := {}
var _cont: TfContinuity
var _form_path := ""
var _swapped := false
var _exiting := false
var _shot_n := 0


static func load_data() -> Dictionary:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformation_sequences.json"))
	return data


func setup(m: Node, dir_node: Node) -> void:
	main = m
	director = dir_node
	load_data()
	layer = CanvasLayer.new()
	layer.name = "TransformationVideo"
	layer.layer = 40
	layer.visible = false
	main.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	video = VideoStreamPlayer.new()
	video.set_anchors_preset(Control.PRESET_FULL_RECT)
	video.expand = true
	video.bus = "Cinematic"
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(video)
	top = CanvasLayer.new()
	top.name = "TransformationFlash"
	top.layer = 41
	main.add_child(top)
	flash = ColorRect.new()
	flash.color = Color(FLASH.r, FLASH.g, FLASH.b, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(flash)
	embers2d = _embers_2d()                             # over the flash: the embers carry straight through it
	top.add_child(embers2d)
	embers3d = _embers_3d()
	main.add_child(embers3d)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Cinematic"
		main.add_child(p)
		sfx_players.append(p)
	prefetch.call_deferred()


var _prefetched := {}                   # avatar path -> PackedScene, kept loaded


## Each character's next form loads quietly in the background long before she levels up (no wait when it comes).
func prefetch() -> void:
	for who in main.characters:
		var cur: WorldCharacter = main.characters[who]
		var cur_order := 0
		for s in AppearanceRegistry.stages(who):
			if String(s.get("avatar", "")) == cur.avatar_path:
				cur_order = int(s.get("order", 0))
		var nxt := {}
		for s in AppearanceRegistry.stages(who):
			if String(s.get("status", "")) == "ready" and int(s.get("order", 0)) > cur_order and ResourceLoader.exists(String(s.get("avatar", ""))):
				if nxt.is_empty() or int(s.order) < int(nxt.order):
					nxt = s
		if nxt.is_empty() or _prefetched.has(String(nxt.avatar)):
			continue
		var path := String(nxt.avatar)
		ResourceLoader.load_threaded_request(path, "PackedScene", true)
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().create_timer(0.5).timeout
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			_prefetched[path] = ResourceLoader.load_threaded_get(path)


## Gold embers drifting up across the whole screen (they rise over the video and keep rising over the world).
func _embers_2d() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = maxi(24, int(140 * float(RenderProfile.get_setting("particle_scale"))))
	p.lifetime = 3.2
	p.emitting = false
	p.local_coords = false
	var vp := Vector2(1920, 1080)
	p.position = Vector2(vp.x * 0.5, vp.y + 40.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1100, 80, 1)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 60.0
	pm.initial_velocity_max = 190.0
	pm.gravity = Vector3(0, -20, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 6.0
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 0.78, 0.35, 0), Color(1, 0.7, 0.25, 1), Color(0.95, 0.45, 0.1, 0.85), Color(0.7, 0.2, 0.03, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var dot := GradientTexture2D.new()
	dot.width = 24
	dot.height = 24
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var dg := Gradient.new()
	dg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	dot.gradient = dg
	p.texture = dot
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX       # (mix, not add: they must still show on the white flash)
	p.material = cm
	return p


## Embers falling round her in the world after she reappears.
func _embers_3d() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(16, int(70 * float(RenderProfile.get_setting("particle_scale"))))
	p.lifetime = 3.5
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.4, 0.3, 1.4)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0, -0.15, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 0.85, 0.5, 0), Color(1, 0.78, 0.38, 1), Color(0.9, 0.35, 0.08, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.6, 1.2, 0.6)
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func form_spec(who: String, lvl: int) -> Dictionary:
	return data.get("forms", {}).get(who, {}).get(str(lvl), {})


## The outfit a form wears: its own ready stage, else (no 3D outfit yet) the latest ready look below it - a
## placeholder until the form's GLBs are fitted and its stage registered.
static func target_avatar(who: String, lvl: int) -> Dictionary:
	var best := {}
	for s in AppearanceRegistry.stages(who):
		if String(s.get("status", "")) != "ready" or String(s.get("avatar", "")) == "" or not ResourceLoader.exists(String(s.avatar)):
			continue
		if int(s.get("order", 0)) <= lvl and (best.is_empty() or int(s.order) > int(best.order)):
			best = s
	if best.is_empty():
		return {}
	return {"avatar": String(best.avatar), "stage": String(best.id), "placeholder": int(best.order) != lvl}


static func video_path(who: String, lvl: int) -> String:
	return VIDEO_DIR + "%s_%d.ogv" % [who, lvl]


static func has_video(who: String, lvl: int) -> bool:
	return FileAccess.file_exists(video_path(who, lvl))


static func seen(who: String, lvl: int) -> bool:
	return (WorldState.mind(who).progress.get("tfseq_seen", {}) as Dictionary).has(str(lvl))


## A viewer typed "skip": only once this form has been shown in full; it cuts to the flash out.
func request_skip(by := "") -> bool:
	if playing == "" or skip_requested or _exiting or not seen(playing, level):
		return false
	skip_requested = true
	skip_by = by
	return true


# ------------------------------------------------------------------ audio, flash
func _sfx(name: String, db := 0.0) -> void:
	var path := SOUND_DIR + name + ".ogg"
	if not ResourceLoader.exists(path):
		return
	var pick: AudioStreamPlayer = sfx_players[0]
	for p in sfx_players:
		if not (p as AudioStreamPlayer).playing:
			pick = p
			break
	pick.stream = load(path)
	pick.volume_db = db
	pick.play()


func _flash_to(a: float, dur: float) -> void:
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(flash, "color:a", a, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN if a > flash.color.a else Tween.EASE_OUT)
	await tw.finished


func _mark(name: String) -> void:
	log.append({"t": snappedf(t, 0.01), "beat": name})
	beat.emit(name, t)
	if shots_dir != "":
		_shot.call_deferred("%s/%s_L%d_%02d_%s.png" % [shots_dir, playing, level, _shot_n, name])
		_shot_n += 1


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	get_viewport().get_texture().get_image().save_png(path)


# ------------------------------------------------------------------ the cutscene
func play(who: String, lvl: int, _mode_req := "full", opts := {}) -> Dictionary:
	if playing != "":
		return {"ok": false, "detail": "a transformation is playing"}
	c = main.characters.get(who)
	fs = form_spec(who, lvl)
	var tgt := target_avatar(who, lvl)
	if c == null or tgt.is_empty():
		return {"ok": false, "detail": "no form for %s level %d" % [who, lvl]}
	playing = who
	level = lvl
	skip_requested = false
	skip_by = ""
	_swapped = false
	_exiting = false
	_shot_n = 0
	t = 0.0
	shots_dir = String(opts.get("shots_dir", ""))
	_form_path = String(tgt.avatar)
	if director:
		director.playing = who                         # viewer replies wait; the planners hold
	# her new form loads while the world carries on (no hitch later); the moment is saved once it is ready
	if c.avatar_path != _form_path and not _prefetched.has(_form_path):
		ResourceLoader.load_threaded_request(_form_path, "PackedScene", true)
		var tl := Time.get_ticks_msec()
		while ResourceLoader.load_threaded_get_status(_form_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() - tl < 30000:
			await get_tree().process_frame
	_cont = TfContinuity.capture(main)
	_cont.freeze(main)
	c.stop_action()
	c.set_meta("transforming", true)
	started.emit(who, lvl, mode)
	var vpath := video_path(who, lvl)
	var has := FileAccess.file_exists(vpath)
	var t0 := Time.get_ticks_msec()
	# in: a riser and embers start over the world, the screen floods white-gold
	_sfx("px_flyby_1", -4.0)
	_sfx("px_tfburst_3", -2.0)
	embers2d.restart()
	embers2d.emitting = true
	if shots_dir != "":                               # the untouched moment, before the flash's first frame
		await _shot("%s/%s_L%d_%02d_00_before_flash.png" % [shots_dir, playing, level, _shot_n])
		_shot_n += 1
	log.append({"t": 0.0, "beat": "00_before_flash"})
	beat.emit("00_before_flash", 0.0)
	await _flash_to(1.0, FLASH_IN)
	_mark("01_flash_in")
	_swap_to_form()                                    # under the full white: any hitch is never seen
	await get_tree().process_frame
	if has:
		var vs := VideoStreamTheora.new()
		vs.file = vpath
		video.stream = vs
		layer.visible = true
		video.play()
	get_tree().create_timer(0.9).timeout.connect(func(): embers2d.emitting = false)
	_flash_to(0.0, FLASH_OUT)
	var length := video.get_stream_length() if has else 0.0
	var marks := {0.15: "02_video_start", 0.5: "03_video_middle", 0.85: "04_video_end"}
	while has and video.is_playing() and not skip_requested:
		await get_tree().process_frame
		t = (Time.get_ticks_msec() - t0) / 1000.0
		if length > 0.0:
			for k in marks.keys():
				if video.stream_position >= length * float(k):
					_mark(String(marks[k]))
					marks.erase(k)
			if video.stream_position >= length - EXIT_LEAD:
				break
	if not has:
		await get_tree().create_timer(0.3).timeout
	# out: a shimmer and embers rise over the end of the video, the flash floods in, she is back where she was
	_exiting = true
	_sfx("px_shimmer_1", -3.0)
	_sfx("release_a", -2.0)
	embers2d.restart()
	embers2d.emitting = true
	await _flash_to(1.0, 0.28)
	_mark("05_flash_out")
	video.stop()
	layer.visible = false
	video.stream = null
	_swap_to_form()
	c.remove_meta("transforming")
	continuity_report = _cont.restore(main, c, true) if _cont else {}
	embers3d.global_position = c.global_position + Vector3(0, 2.2, 0)
	embers3d.restart()
	embers3d.emitting = true
	_sfx("land_a", -6.0)
	await _flash_to(0.0, FLASH_OUT)
	t = (Time.get_ticks_msec() - t0) / 1000.0
	_mark("06_back_in_the_world")
	await get_tree().create_timer(0.15).timeout         # the restored moment holds as the flash clears, then life goes on
	if _cont:
		_cont.release_camera(main)
		_cont = null
	get_tree().create_timer(1.2).timeout.connect(func(): embers2d.emitting = false)
	get_tree().create_timer(2.8).timeout.connect(func(): embers3d.emitting = false)
	_prefetched.erase(_form_path)
	prefetch.call_deferred()                            # and the form after this one
	return _finish(opts, has)


## Behind the video (or the flash) she takes her new form; nothing moves her.
func _swap_to_form() -> void:
	if _swapped:
		return
	_swapped = true
	if c.avatar_path != _form_path:
		var ps: PackedScene = _prefetched.get(_form_path) if _prefetched.has(_form_path) else ResourceLoader.load_threaded_get(_form_path) as PackedScene
		if ps:
			c.swap_avatar(_form_path, ps)
		else:
			c.swap_avatar(_form_path)
	c.set_physics_process(false)


func _finish(opts: Dictionary, had_video: bool) -> Dictionary:
	var res := {"ok": _swapped, "who": playing, "level": level, "mode": "video" if had_video else "flash",
		"video": video_path(playing, level).get_file() if had_video else "", "skipped": skip_requested, "skip_by": skip_by,
		"seconds": snappedf(t, 0.01), "avatar": c.avatar_path.get_file(),
		"placeholder": bool(target_avatar(playing, level).get("placeholder", false)), "title": String(fs.get("title", "")),
		"continuity": continuity_report}
	if not bool(opts.get("preview", false)):
		var m := WorldState.mind(playing)
		var sn: Dictionary = m.progress.get("tfseq_seen", {})
		sn[str(level)] = true
		m.progress["tfseq_seen"] = sn
		res["weapon_unlocked"] = WeaponArsenal.unlock(playing, level)
	var who := playing
	playing = ""
	if director:
		director.playing = ""
	log.append(res)
	if log.size() > 200:
		log = log.slice(log.size() - 200)
	finished.emit(who, res)
	return res


func describe() -> Dictionary:
	return {"playing": playing, "level": level, "t": snappedf(t, 0.01), "skip_requested": skip_requested,
		"video": video_path(playing, level).get_file() if playing != "" else "", "recent": log.slice(maxi(0, log.size() - 6))}
