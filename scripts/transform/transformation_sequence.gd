class_name TransformationSequence
extends Node
## The transformation, played in REAL TIME in the world (2026-10-17: "always the same 3D Mika") - _realtime():
##   1 build-up   her line, wind and petals spiralling round her, light gathering, sparkling mist; the other mage
##                turns, surprised, and speaks; the lens orbits slowly (wide / medium, never a face shot)
##   2 rise       she lifts a few metres off the ground, arms opening, hair and sleeves flowing upward
##   3 light      her whole body turns to light (body_light.gdshader, her colours), rings of light and star flowers
##                spin round her, slow motion
##   4 swap       inside the light the outfit changes: the old one, frozen in light, burns away (burn_dissolve) while
##                the new one stands in the same light under it
##   5 burst      bass hit, an impact frame, a white star flash opening from her (screen_transition), a shockwave along
##                the ground, petals and stars thrown out; the light dissolves away from head to toe (the new outfit)
##   6 reveal     a held pose in the air, then a slow descent among sparkles to the exact spot, a soft landing; the
##                other mage runs over and both react
## Effects: TransformFX (built from the spell system's masks and element colours, pre-warmed before it starts).
## A sound on every beat. data "use_video": true (or opts.video) plays the old video cutscene below instead.
##
## The video cutscene (unused fallback): a full-screen video per form (made outside this project, converted with
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
const EXIT_LEAD := 0.45                         # (legacy: the old flash out started this long before the video ended)
const FADE_BLACK := 0.7                         # the world fades to black into the video's own black opening
const FADE_WHITE := 0.9                         # from the video's closing white back to the world
const BUILD_UP_S := 5.0
const LAUNCH_H := 30.0                          # how high she shoots up before the flash (out of the top of the frame)
const LAUNCH_S := 1.0
const DESCEND_H := 9.0                          # out of the white she is this high above the spot she left
const DESCEND_S := 5.0
const SHOT_DIST := 5.0                          # the wide shot: her whole body ~1/3 of the frame, her face ~5% (never a close-up)
## Her words as it begins, the other mage's reaction, and both after it (voiced lines, prefetched when the level-up
## queues the transformation - no LLM, no waiting on TTS in the middle of the scene).
const LINES := {
	"mika": {"feel": "Luna... I feel something happening.", "see": "Luna? Your hands... they're glowing!",
		"after": "Luna... look at me. Is this really me?", "after_weapon": "Luna, look... the %s. It came with me.",
		"react": "Luna... you look incredible!", "react_weapon": "Luna, you look incredible. And the %s!"},
	"luna": {"feel": "Mika... something is happening to me.", "see": "Mika? Your hands... they're glowing!",
		"after": "...So this is what it feels like.", "after_weapon": "...So this is what it feels like. And the %s.",
		"react": "Mika... that's beautiful. Really.", "react_weapon": "Mika... that's beautiful. And the %s suits you."},
}

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
var burst_rect: ColorRect
var _tfx: TransformFX
var _realtime_on := true


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
	burst_rect = ColorRect.new()                        # the burst's white star opening from her (real-time form)
	burst_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	burst_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burst_rect.color = Color(1, 1, 1, 0.0)
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/vfx/screen_transition.gdshader")
	bm.set_shader_parameter("transition_type", 2)
	bm.set_shader_parameter("edges", 8)
	bm.set_shader_parameter("shape_feather", 0.35)
	bm.set_shader_parameter("invert", true)
	bm.set_shader_parameter("use_sprite_alpha", true)
	bm.set_shader_parameter("progress", 0.0)
	burst_rect.material = bm
	top.add_child(burst_rect)
	top.move_child(burst_rect, 0)
	for i in 8:
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
			_prebuild(path)


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
	var path := name if name.begins_with("res://") else SOUND_DIR + name + ".ogg"
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
	if _realtime_on and _rt_t0 > 0:
		t = (Time.get_ticks_msec() - _rt_t0) / 1000.0
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
	_weapon_unlocked = ""
	_preview = bool(opts.get("preview", false))
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
	# the moment is HERS: the camera turns to her before the moment is saved (and so, restored after the video, the
	# shot is her - not whatever it was filming when she levelled up, e.g. the other mage's dance)
	var cam_dir = main.get("director")
	if main.get("performance") and main.performance.busy():
		main.performance.interrupt("a transformation")
	# the wide shot is set up BEFORE the moment is saved: continuity puts this very framing back after the video, so
	# the white fades straight into her new form from the front (not into the follow camera behind her)
	_lift = {"y": 0.0, "t": 0.0}
	_scene_shot = _wide_shot(c.global_position, _other_near(who), SHOT_DIST)
	_rt_cam = {}
	_realtime_on = not (bool(data.get("use_video", false)) or bool(opts.get("video", false)))
	if _realtime_on:
		_rt_prepare(who)                                # its effects built and drawn once while the lens settles
	if cam_dir and c.visible:
		cam_dir.set_subject(c)
		var base0 := c.global_position
		var sh: Dictionary = _scene_shot
		var lift: Dictionary = _lift
		cam_dir.begin_scene(func(delta: float) -> Dictionary:
			if _realtime_on and not _rt_cam.is_empty():
				return _rt_camera(delta)
			lift.t += delta
			# launch: the lens stays and tilts up after her; descent ("follow"): it rides down with her, level with her
			var ride: float = float(lift.y) * 0.8 if bool(lift.get("follow", false)) else 0.0
			var lk: Vector3 = (Vector3(sh.look) + Vector3(0, 1.15 + float(lift.y) * 0.6, 0)) if not bool(lift.get("follow", false)) else (c.global_position + Vector3(0, 1.1, 0))
			return {"pos": sh.pos + sh.side * (0.03 * minf(float(lift.t), 8.0)) + Vector3(0, ride, 0), "look": lk,
				"fov": 50.0, "rate": 3.0, "cut": float(lift.t) < 0.05, "exact": true})
		await get_tree().create_timer(1.2).timeout
	prefetch_lines(who, lvl)
	var cam_now := get_viewport().get_camera_3d()
	print("[tfseq] wide shot %.1f m from her (lens %.1f m away at capture)" % [Vector3(_scene_shot.pos).distance_to(c.global_position + Vector3(0, 1.15, 0)),
		cam_now.global_position.distance_to(c.global_position + Vector3(0, 1.15, 0)) if cam_now else -1.0])
	_cont = TfContinuity.capture(main)
	_cont.freeze(main)
	c.stop_action()
	c.set_meta("transforming", true)
	started.emit(who, lvl, mode)
	var vpath := video_path(who, lvl)
	var has := FileAccess.file_exists(vpath)
	if not has:
		print("[tfseq] %s L%d: no video at %s - the flash and her new outfit only" % [who, lvl, vpath])
	var t0 := Time.get_ticks_msec()
	if shots_dir != "":                               # the untouched moment, before anything starts
		await _shot("%s/%s_L%d_%02d_00_before_flash.png" % [shots_dir, playing, level, _shot_n])
		_shot_n += 1
	log.append({"t": 0.0, "beat": "00_before_flash"})
	beat.emit("00_before_flash", 0.0)
	if _realtime_on:
		await _realtime(who, lvl, t0)
		_swap_to_form()                                   # (already done inside the light; a no-op)
		c.remove_meta("transforming")
		var tr0 := Time.get_ticks_usec()
		continuity_report = _cont.restore(main, c, true) if _cont else {}
		continuity_report["video"] = "realtime"
		var tr1 := Time.get_ticks_usec()
		t = (Time.get_ticks_msec() - t0) / 1000.0
		_mark("06_back_in_the_world")
		await get_tree().create_timer(0.15).timeout
		var tr2 := Time.get_ticks_usec()
		if _cont:
			_cont.release_camera(main)
			_cont = null
		var tr3 := Time.get_ticks_usec()
		print("[tfseq] restore %.0f ms, release %.0f ms" % [(tr1 - tr0) / 1000.0, (tr3 - tr2) / 1000.0])
		await _after(who, lvl)
		_mark("07_reactions_done")
		_prefetched.erase(_form_path)
		prefetch.call_deferred()
		return _finish(opts, false)
	# 1 build-up in the world (~5 s): her line, wind round her, glow gathering in her hands; a wide shot
	await _build_up(who, lvl)
	_mark("01_build_up_done")
	# 2 launch: she shoots straight up into the night sky (~1 s) trailing stars and petals; the lens tilts up after
	#   her, the other mage looks up. The video opens in the sky above the clouds - she has flown there.
	await _launch(who)
	_mark("02_launch")
	# 3 a bright flash at the top; the video starts at once under it (its own black opening stays hidden under the
	#   white until its first real frame), and her outfit changes behind it
	flash.color = Color(FLASH, 0.0)
	await _flash_to(1.0, 0.12)
	_mark("03_flash")
	_fx_off()
	_swap_to_form()                                    # under the white: any hitch is never seen
	var how := "flash"
	if has:
		# 4 the video full screen; chat replies wait (director.playing); back on its finished signal, or its length
		#   + 2 s if that never comes; a viewer's "skip" (after the first showing) cuts to the end
		var vs := VideoStreamTheora.new()
		vs.file = vpath
		video.stream = vs
		layer.visible = true
		video.play()
		var lead := video_lead_in(who, lvl)
		var tw0 := Time.get_ticks_msec()
		while video.stream_position < lead and (Time.get_ticks_msec() - tw0) / 1000.0 < lead + 1.0:
			await get_tree().process_frame
		_flash_to(0.0, 0.25)                           # into the video's own white flash
		var length := video.get_stream_length()
		var ended := {"v": false}
		var on_end := func(): ended.v = true
		video.finished.connect(on_end, CONNECT_ONE_SHOT)
		var tv := Time.get_ticks_msec()
		var limit := (length if length > 0.0 else 30.0) + 2.0
		var marks := {0.15: "04_video_start", 0.5: "04_video_middle", 0.85: "04_video_end"}
		while not ended.v and not skip_requested and (Time.get_ticks_msec() - tv) / 1000.0 < limit:
			await get_tree().process_frame
			t = (Time.get_ticks_msec() - t0) / 1000.0
			if length > 0.0:
				for k in marks.keys():
					if video.stream_position >= length * float(k):
						_mark(String(marks[k]))
						marks.erase(k)
		if video.finished.is_connected(on_end):
			video.finished.disconnect(on_end)
		how = "finished" if ended.v else ("skipped" if skip_requested else "timeout")
		print("[tfseq] %s L%d: video %s after %.2f s (length %.2f s)" % [who, lvl, how, (Time.get_ticks_msec() - tv) / 1000.0, length])
		# the video ends on white: Godot holds the same white
		flash.color = Color(FLASH, 1.0)
		video.stop()
		layer.visible = false
		video.stream = null
	else:
		_sfx("px_tfburst_3", -2.0)
		await get_tree().create_timer(0.35).timeout
	_mark("05_white")
	_swap_to_form()
	# 5 out of the white she is high in the air above the very spot she left, in her new form; she drifts down slowly,
	#   petals and sparkles round her, hair and sleeves floating; the lens follows her down; a soft landing exactly
	#   where she stood. Then everyone is put back exactly (TfContinuity) - she is already there.
	await _descend(who)
	_mark("05_landed")
	c.remove_meta("transforming")
	continuity_report = _cont.restore(main, c, true) if _cont else {}
	continuity_report["video"] = how
	t = (Time.get_ticks_msec() - t0) / 1000.0
	_mark("06_back_in_the_world")
	await get_tree().create_timer(0.15).timeout
	if _cont:
		_cont.release_camera(main)
		_cont = null
	# 6 the other mage runs over; both react to her new form (and its weapon from Level 20 on)
	await _after(who, lvl)
	_mark("07_reactions_done")
	_prefetched.erase(_form_path)
	prefetch.call_deferred()                            # and the form after this one
	return _finish(opts, has)


# ------------------------------------------------------------------ the real-time transformation
const RISE_H := 3.2                             # how high she floats up (m)
const RISE_S := 3.0
const SLOW := 0.42                              # slow motion while she is light
const RT_DESCEND_S := 4.6
const SYN := "res://assets/audio/synth/"
var _rt_cam := {}
var _rt_t0 := 0
var _rt_base := Vector3.ZERO
var _rt_hitches: Array = []                     # frames over 50 ms during the scene: [t, ms, beat]


## Real seconds (slow motion does not stretch the scene's own timing).
func _rt(secs: float) -> void:
	await get_tree().create_timer(secs, true, false, true).timeout


func _rtw() -> Tween:
	return create_tween().set_ignore_time_scale(true)


func _fam(el: Dictionary) -> String:
	return String(el.get("sound", "arcane"))


## Before the moment is saved: her effects are built and drawn once out of sight (every pipeline compiled), the light
## overlay laid on her at zero (its shader compiled too) and the burst flash drawn invisibly.
func _rt_prepare(who: String) -> void:
	if _tfx and is_instance_valid(_tfx):
		_tfx.queue_free()
	_tfx = TransformFX.make(who)
	main.world.add_child(_tfx)
	_tfx.light_mat.set_shader_parameter("cover", 0.0)
	_tfx.light_mat.set_shader_parameter("reveal_y", 1000.0)
	_tfx.light_on(c.avatar, true)
	(burst_rect.material as ShaderMaterial).set_shader_parameter("progress", 0.0)
	burst_rect.color = Color(1, 1, 1, 0.003)
	if SpellFX.instance:
		SpellFX.instance.prewarm(TransformFX.elements_of(who), 2)
	await _tfx.prewarm(c.global_position - Vector3(0, 3.0, 0))
	burst_rect.color = Color(1, 1, 1, 0.0)


## The scene's lens: a slow orbit round the spot she rises from - wide or medium, never closer than 5 m (her face
## stays ~5% of the frame), rising with her, looking at her; it never stands in the other mage.
func _rt_camera(delta: float) -> Dictionary:
	var k := _rt_cam
	k.t = float(k.t) + delta
	k.yaw = float(k.yaw) + delta * float(k.rate) * float(k.sign)
	k.chk = float(k.get("chk", 0.0)) + delta
	if float(k.chk) > 0.25:
		k.chk = 0.0
		var dd := Vector3(sin(float(k.yaw)), 0.0, cos(float(k.yaw)))
		var lf := maxf(c.global_position.y - _rt_base.y, 0.0)
		if _rt_blocked(_rt_base + dd * float(k.dist) + Vector3(0, float(k.h) + lf * 0.45, 0), c.global_position + Vector3(0, 1.1, 0)):
			k.sign = -float(k.sign)                     # something came between: orbit back the other way
	var d := Vector3(sin(float(k.yaw)), 0.0, cos(float(k.yaw)))
	var lift := maxf(c.global_position.y - _rt_base.y, 0.0)
	# below her as she rises (looking up at her: the rings read as rings, not lines)
	var p := _rt_base + d * float(k.dist) + Vector3(0, float(k.h) + lift * 0.45, 0)
	var other := _other_near(playing)
	if other:
		# never near the other mage (her head would fill a corner of the frame): turn the orbit back before 3 m, and
		# never closer than 2.5 m
		var off := Vector2(p.x - other.global_position.x, p.z - other.global_position.z)
		if off.length() < 3.0 and float(k.get("flip_cd", 0.0)) <= 0.0:
			var ahead := Vector3(sin(float(k.yaw) + 0.05 * float(k.sign)), 0.0, cos(float(k.yaw) + 0.05 * float(k.sign)))
			var pa := _rt_base + ahead * float(k.dist)
			if Vector2(pa.x - other.global_position.x, pa.z - other.global_position.z).length() < off.length():
				k.sign = -float(k.sign)
				k.flip_cd = 2.0
		k.flip_cd = float(k.get("flip_cd", 0.0)) - delta
		if off.length() < 2.5:
			var n := off.normalized() if off.length() > 0.05 else Vector2(d.x, d.z)
			p = Vector3(other.global_position.x + n.x * 2.5, p.y, other.global_position.z + n.y * 2.5)
	return {"pos": p, "look": c.global_position + Vector3(0, float(k.look_h), 0), "fov": float(k.fov), "rate": 3.0,
		"cut": float(k.t) < 0.05, "exact": true}


func _rt_cam_to(key: String, v: float, dur: float) -> void:
	_rtw().tween_method(func(x: float): _rt_cam[key] = x, float(_rt_cam[key]), v, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The orbit starts where the wide shot stood and turns toward the open side (no wall, tree or rock in the way).
func _rt_cam_start() -> void:
	var sh: Dictionary = _scene_shot
	var v: Vector3 = Vector3(sh.pos) - _rt_base
	var yaw := atan2(v.x, v.z)
	var dist := clampf(Vector2(v.x, v.z).length(), 4.8, 5.6)      # medium-wide: her face ~5% of the frame
	# every 10 degrees round her: is she in clear view from there - standing (chest) and risen (chest + RISE_H)?
	var clear: Array = []
	for i in 36:
		var a := TAU * i / 36.0
		var ok := true
		for lift in [0.0, RISE_H]:
			var cam := _rt_base + Vector3(sin(a), 0, cos(a)) * dist + Vector3(0, 1.55 + lift * 0.45, 0)
			if _rt_blocked(cam, _rt_base + Vector3(0, 1.1 + lift, 0)) or _rt_blocked(cam, _rt_base + Vector3(0, 0.4 + lift, 0)):
				ok = false
		clear.append(ok)
	# the start nearest the wide shot from which a whole 60-degree arc stays clear, turning either way
	var i0 := posmod(int(round(yaw / (TAU / 36.0))), 36)
	var best := 1.0
	var found := false
	for off in 19:
		for sg in [1, -1]:
			for sd in [1, -1]:
				var st := posmod(i0 + sd * off, 36)
				var arc_ok := true
				for k in 7:
					if not bool(clear[posmod(st + sg * k, 36)]):
						arc_ok = false
				if arc_ok and not found:
					found = true
					yaw = TAU * st / 36.0
					best = float(sg)
	if not found:
		print("[tfseq] no fully clear orbit round her here - starting from the wide shot")
	_rt_cam = {"t": 0.0, "yaw": yaw, "dist": dist, "h": 1.55, "look_h": 1.1, "fov": 50.0,
		"rate": 0.05, "sign": best}


## The lens for the reactions: side-on to the line between her and the other mage (who runs across the frame to her,
## never past the lens), 5.6 m off, clear to both; else the orbit's last place.
func _rt_after_shot(other: WorldCharacter) -> Dictionary:
	var last: Dictionary = _rt_camera(0.0)
	var dirs: Array = []
	if other:
		var a := Vector3(other.global_position.x - _rt_base.x, 0, other.global_position.z - _rt_base.z)
		if a.length() > 0.3:
			a = a.normalized()
			var perp := Vector3(-a.z, 0, a.x)
			var ld := Vector3(Vector3(last.pos).x - _rt_base.x, 0, Vector3(last.pos).z - _rt_base.z)
			if perp.dot(ld) < 0.0:
				perp = -perp                           # the side the lens is already on first (a smaller cut)
			dirs = [perp, -perp, (perp - a * 0.4).normalized(), (-perp - a * 0.4).normalized()]
	for d: Vector3 in dirs:
		var mid := _rt_base.lerp(Vector3(other.global_position.x, _rt_base.y, other.global_position.z), 0.3) if other else _rt_base
		var p := mid + d * 5.6 + Vector3(0, 1.6, 0)
		if not _rt_blocked(p, _rt_base + Vector3(0, 1.1, 0)) and not _rt_blocked(p, other.global_position + Vector3(0, 1.1, 0)):
			return {"pos": p, "look": mid, "mid": mid, "side": Vector3(-d.z, 0, d.x)}
	return {"pos": last.pos, "look": _rt_base, "mid": _rt_base, "side": Vector3.RIGHT}


## Is anything solid (walls, pedestals, trees; not the mages) between the lens and her?
func _rt_blocked(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var ex: Array[RID] = []
	for w in main.characters:
		var ch = main.characters[w]
		if ch is CollisionObject3D:
			ex.append((ch as CollisionObject3D).get_rid())
	q.exclude = ex
	return not c.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _rt_frame_watch(t0: int) -> void:
	_rt_hitches.clear()
	var last := Time.get_ticks_usec()
	while playing != "":
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		if ms > 50.0:
			var b := String(log.back().get("beat", "")) if not log.is_empty() and log.back() is Dictionary else ""
			_rt_hitches.append([snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.01), snappedf(ms, 0.1), b])


func _realtime(who: String, lvl: int, t0: int) -> void:
	var fx := _tfx
	var other := _other_near(who)
	_rt_t0 = t0
	_rt_base = c.global_position
	fx.ground = _rt_base
	fx.global_position = _rt_base
	fx.follow = c
	var e1: Dictionary = fx.el1
	var e2: Dictionary = fx.el2
	_rt_cam_start()
	_rt_frame_watch(t0)
	_rt_instantiate_form()
	var lines := {}
	# ---- 1 build-up (~6 s): her line, light gathering, wind and petals spiralling round her, mist; the other reacts
	_mark("01_build_up")
	_sfx(SYN + "spell_%s_charge.ogg" % _fam(e1), -4.0)
	_sfx(SYN + "spell_%s_gather_loop.ogg" % _fam(e1), -7.0)
	c.play_gesture("spell_casting", 0.5, 0.6)
	_say_async(who, String(LINES[who].feel), lines, "feel")
	fx.emit(fx.gather, true)
	fx.set_mist(1.0, 2.5)
	await _rt(0.9)
	fx.emit(fx.spiral, true)
	_sfx(SYN + "spell_%s_activation.ogg" % _fam(e1), -6.0)
	_rt_cam_to("dist", float(_rt_cam.dist) - 0.3, 5.0)
	await _rt(1.1)
	if other:
		var to := Vector3(_rt_base.x - other.global_position.x, 0, _rt_base.z - other.global_position.z)
		var tw2 := create_tween()
		tw2.tween_property(other, "rotation:y", other.rotation.y + wrapf(atan2(-to.x, -to.z) - other.rotation.y, -PI, PI), 0.6).set_trans(Tween.TRANS_SINE)
		other.look_head_at(c.chest.global_position if c.chest else _rt_base + Vector3(0, 1.4, 0))
		if other.has_method("set_expression"):
			other.set_expression("surprised", 0.7)
	await _rt(1.0)
	_sfx("tf_riser", -5.0)
	_sfx(SYN + "spell_%s_gather_loop.ogg" % _fam(e2), -8.0)
	if other:
		var tl := Time.get_ticks_msec()
		while not bool(lines.get("feel", true)) and Time.get_ticks_msec() - tl < 2500:
			await get_tree().process_frame
		_say_async(other.character_id, String(LINES[other.character_id].see), lines, "see")
	var t_end := Time.get_ticks_msec() + 2400
	while Time.get_ticks_msec() < t_end or (lines.values().has(false) and Time.get_ticks_msec() < t_end + 2600):
		await get_tree().process_frame
	# ---- 2 rise (~3 s): off the ground, arms opening, hair and sleeves flowing up
	_mark("02_rise")
	c.end_gesture()
	c.play_gesture("tf_arms_open", 0.8, 0.5)
	_float_springs(true)
	_sfx(SYN + "portal_whoosh.ogg", -5.0)
	_sfx("px_flyby_1", -8.0)
	_rt_cam_to("dist", float(_rt_cam.dist) + 0.6, RISE_S)
	_rt_cam_to("look_h", 1.0, RISE_S)
	var tw := _rtw()
	tw.tween_property(c, "global_position:y", _rt_base.y + RISE_H, RISE_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tl2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tl2 < int(RISE_S * 1000.0):
		if other:
			other.look_head_at(c.global_position + Vector3(0, 1.3, 0))
		await get_tree().process_frame
	# ---- 3 body of light (slow motion): her whole body turns to light; rings and star flowers spin round her
	_mark("03_body_of_light")
	_sfx("tf_light_choir", -2.0)
	_sfx("px_shimmer_1", -6.0)
	_sfx(SYN + "spell_%s_activation.ogg" % _fam(e2), -4.0)
	fx.emit(fx.gather, false)
	fx.set_rings(true)
	_rtw().tween_method(func(v: float): fx.light_mat.set_shader_parameter("cover", v), 0.0, 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	_rtw().tween_method(func(v: float): Engine.time_scale = v, 1.0, SLOW, 0.5).set_delay(0.3)
	await _rt(1.3)
	# ---- 4 the swap, inside the light: the old outfit (frozen in light) burns away over the new one
	_mark("04_swap")
	_float_springs(false)
	var ts0 := Time.get_ticks_usec()
	var ghost := _swap_in_light(fx)
	print("[tfseq] swap inside the light: %.0f ms" % ((Time.get_ticks_usec() - ts0) / 1000.0))
	c.play_gesture("tf_arms_open", 0.0, 0.5)
	_float_springs(true)
	_sfx(SYN + "spell_%s_rune.ogg" % _fam(e1), -5.0)
	if ghost:
		fx.burn_mat.set_shader_parameter("dissolve_amount", 0.0)
		var twb := _rtw()
		twb.tween_method(func(v: float): fx.burn_mat.set_shader_parameter("dissolve_amount", v), 0.0, 1.05, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		twb.tween_callback(ghost.queue_free)
	await _rt(1.55)
	# ---- 5 burst: bass hit, impact frame, a white star opening from her, shockwave, petals and stars thrown out
	Engine.time_scale = 1.0
	_mark("05_burst")
	var chest := c.global_position + Vector3(0, 1.15, 0)
	_sfx("tf_bass_hit", 0.0)
	_sfx("px_tfburst_3", -3.0)
	fx.set_rings(false)
	fx.emit(fx.spiral, false)
	fx.set_mist(0.0, 1.2)
	fx.shockwave(Vector3(_rt_base.x, _rt_base.y, _rt_base.z))
	fx.explode_at(chest)
	if SpellFX.instance:
		SpellFX.instance.burst(chest, String(e1.id), 2.6, false)
	if ImpactFrame.instance:                             # flash + speed lines, element tint, hit stop (no negative)
		var cam0 := get_viewport().get_camera_3d()
		var sp := Vector2(0.5, 0.5)
		if cam0 and not cam0.is_position_behind(chest):
			sp = cam0.unproject_position(chest) / get_viewport().get_visible_rect().size
		ImpactFrame.instance.hit(String(e1.id), sp, false)
	_burst_flash(chest)
	_rt_cam_to("dist", float(_rt_cam.dist) + 0.5, 0.5)
	await _rt(0.45)
	# the light dissolves away from her head to her toes: the new outfit
	_sfx(SYN + "spell_%s_dissipate.ogg" % _fam(e2), -4.0)
	var top_y := c.global_position.y + 1.95
	var foot_y := c.global_position.y - 0.15
	fx.light_mat.set_shader_parameter("reveal_y", top_y)
	var twr := _rtw()
	twr.tween_method(func(v: float): fx.light_mat.set_shader_parameter("reveal_y", c.global_position.y + v), top_y - c.global_position.y, foot_y - c.global_position.y, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await twr.finished
	fx.light_on(c.avatar, false)
	# ---- 6 reveal pose in the air, then a slow descent among sparkles to the exact spot
	_mark("06_reveal")
	fx.emit(fx.sparkle, true)
	_sfx("px_shimmer_1", -7.0)
	if other and other.has_method("set_expression"):
		other.set_expression("happy", 0.6)
	await _rt(1.4)
	_mark("06_descend")
	if not c.play_gesture("idle", 0.9, 0.5):            # floating down upright and calm (not a fall pose)
		c.end_gesture()
	_rt_cam_to("dist", float(_rt_cam.dist) - 0.6, RT_DESCEND_S)
	_rt_cam_to("look_h", 1.15, RT_DESCEND_S)
	var twd := _rtw()
	twd.tween_property(c, "global_position:y", _rt_base.y, RT_DESCEND_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tl3 := Time.get_ticks_msec()
	var landed := false
	while Time.get_ticks_msec() - tl3 < int(RT_DESCEND_S * 1000.0):
		if other:
			other.look_head_at(c.global_position + Vector3(0, 1.3, 0))
		if not landed and Time.get_ticks_msec() - tl3 > int((RT_DESCEND_S - 0.4) * 1000.0):
			landed = true
			c.play_gesture("land_soft", 0.25, 0.4)
		await get_tree().process_frame
	c.global_position = _rt_base
	_sfx("land_a", -6.0)
	fx.emit(fx.sparkle, false)
	_float_springs(false)
	if other:
		other.look_head_at(null)
	_scene_shot = _rt_after_shot(other)                  # the reactions: side-on to the two of them
	_rt_cam = {}
	_mark("06_landed")
	print("[tfseq] %s L%d real time: %.1f s to the landing, %d frames over 50 ms %s" % [who, lvl, (Time.get_ticks_msec() - t0) / 1000.0, _rt_hitches.size(), str(_rt_hitches)])


## Long before her transformation (when her next form is prefetched): that form instantiated and its clip library
## built on a worker thread, kept ready - the scene itself then builds nothing (no slow frames at its start).
var _ready_forms := {}                  # avatar path -> {task, inst, lib}


func _prebuild(path: String) -> void:
	if _ready_forms.has(path) or RenderProfile.options.has("tf-no-thread"):
		return
	var ps: PackedScene = _prefetched.get(path)
	if ps == null:
		return
	var box := {}
	_ready_forms[path] = box
	box["task"] = WorkerThreadPool.add_task(func():
		var inst := ps.instantiate()
		box["inst"] = inst
		box["lib"] = WorldCharacter.prebuild_library(inst))


## Her new outfit is instantiated on a worker thread during the build-up (off the tree: safe), so the swap inside the
## light only attaches it - no long frame.
var _form_box := {}


func _rt_instantiate_form() -> void:
	_form_box = {}
	if c.avatar_path == _form_path or RenderProfile.options.has("tf-no-thread"):
		return
	if _ready_forms.has(_form_path):
		_form_box = _ready_forms[_form_path]            # built long ago (prefetch)
		_ready_forms.erase(_form_path)
		return
	var ps: PackedScene = _prefetched.get(_form_path) if _prefetched.has(_form_path) else ResourceLoader.load_threaded_get(_form_path) as PackedScene
	if ps == null:
		return
	_prefetched[_form_path] = ps
	var box := _form_box
	# the avatar, then its clip library (a new skeleton = a library not yet built: ~0.7 s if left to the swap)
	box["task"] = WorkerThreadPool.add_task(func():
		var inst := ps.instantiate()
		box["inst"] = inst
		box["lib"] = WorldCharacter.prebuild_library(inst))


## Her new outfit, taken inside the light: the new avatar wears the light the instant it exists (never seen
## uncovered); the old one stays a moment as burning light on its last pose. Returns that ghost (or null).
func _swap_in_light(fx: TransformFX) -> Node3D:
	if _swapped:
		return null
	_swapped = true
	var ghost: Node3D = null
	if c.avatar_path != _form_path:
		var ps: PackedScene = _prefetched.get(_form_path) if _prefetched.has(_form_path) else ResourceLoader.load_threaded_get(_form_path) as PackedScene
		c.released_avatar = null
		var inst: Node3D = null
		if _form_box.has("task"):
			WorkerThreadPool.wait_for_task_completion(int(_form_box.task))
			inst = _form_box.get("inst") as Node3D
			WorldCharacter.adopt_library(_form_box.get("lib", []))
			_form_box = {}
		var ok := c.swap_avatar(_form_path, ps, inst, true) if (ps or inst) else c.swap_avatar(_form_path, null, null, true)
		if ok and c.released_avatar:
			ghost = c.released_avatar
			c.released_avatar = null
			ghost.process_mode = Node.PROCESS_MODE_DISABLED
			main.world.add_child(ghost)
			ghost.global_transform = ghost.get_meta("released_xf", c.global_transform)
			fx.burn_on(ghost)
		fx.light_on(c.avatar, true)
	c.set_physics_process(false)
	return ghost


## The burst's flash: a white eight-point star opening from her on screen (Universal Transition Shader, CC0), then
## fading - after the impact frame's first beat.
func _burst_flash(at: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	var uv := Vector2(0.5, 0.5)
	if cam and not cam.is_position_behind(at):
		uv = cam.unproject_position(at) / get_viewport().get_visible_rect().size
	var m := burst_rect.material as ShaderMaterial
	m.set_shader_parameter("position", uv)
	m.set_shader_parameter("progress", 0.0)
	await _rt(0.12)
	burst_rect.color = Color(1, 1, 1, 1.0)
	var tw := _rtw()
	tw.tween_method(func(v: float): m.set_shader_parameter("progress", v), 0.0, 3.2, 0.28).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.1)
	tw.tween_property(burst_rect, "color:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	m.set_shader_parameter("progress", 0.0)


# ------------------------------------------------------------------ build-up and reactions (in the world)
var _fx: Array = []
var _weapon_unlocked := ""
var _preview := false
var _scene_shot := {}
var _lift := {}


func _voice_of(w: String) -> String:
	return String(Progression.mages.get(w, {}).get("voice", w))


func _other_near(who: String) -> WorldCharacter:
	for w in main.characters:
		if w != who and LINES.has(w):
			var o: WorldCharacter = main.characters[w]
			if o.visible and c and o.global_position.distance_to(c.global_position) < 18.0:
				return o
	return null


static func weapon_name(who: String, lvl: int) -> String:
	return String(WeaponArsenal.table(who).get(str(lvl), {}).get("name", ""))


## Her lines and the other mage's are synthesised ahead (the level-up queues this; playing it again is free).
func prefetch_lines(who: String, lvl: int) -> void:
	if main.get("voice") == null or not LINES.has(who):
		return
	var wn := weapon_name(who, lvl)
	main.voice.prefetch(_voice_of(who), String(LINES[who].feel))
	main.voice.prefetch(_voice_of(who), (String(LINES[who].after_weapon) % wn) if wn != "" else String(LINES[who].after))
	for w in LINES:
		if w != who:
			main.voice.prefetch(_voice_of(w), String(LINES[w].see))
			main.voice.prefetch(_voice_of(w), (String(LINES[w].react_weapon) % wn) if wn != "" else String(LINES[w].react))


func _say_async(w: String, text: String, box: Dictionary, key: String) -> void:
	box[key] = false
	await main.voice.say(_voice_of(w), text)
	box[key] = true


func _wide_shot(base: Vector3, other: WorldCharacter, dist := 7.0) -> Dictionary:
	var fwd := -c.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	if other and Vector2(other.global_position.x - base.x, other.global_position.z - base.z).length() > 8.0:
		other = null                         # too far apart for one wide shot: frame her alone
	var mid := base if other == null else base.lerp(other.global_position, 0.45)
	if other:
		dist = clampf(Vector2(other.global_position.x - base.x, other.global_position.z - base.z).length() * 0.9 + 2.6, dist, 9.0)
	var axis := fwd if other == null else Vector3(other.global_position.x - base.x, 0, other.global_position.z - base.z).normalized()
	var side := Vector3(-axis.z, 0, axis.x)
	if other:
		fwd = side if side.dot(fwd) >= 0.0 else -side       # (a two-shot: from the side of the pair she faces)
	if side.dot(fwd) < 0.0:
		side = -side                         # the side she faces: her face, her hands, the glow
	var space := c.get_world_3d().direct_space_state
	# in front of her and to the side, ~dist away, a little above eye level; the open side wins (nothing solid between)
	for d: Vector3 in [(side * 0.75 + fwd * 0.66).normalized(), (side * 0.3 + fwd).normalized(), (-side * 0.75 + fwd * 0.66).normalized(), side, -side]:
		var from := mid + Vector3(0, 1.4, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + d * (dist + 0.6) + Vector3(0, 0.5, 0), 1)
		var p := mid + d * dist + Vector3(0, 1.9, 0)
		if space.intersect_ray(q).is_empty() and Vector2(p.x - base.x, p.z - base.z).length() >= SHOT_DIST * 0.9:
			return {"pos": p, "mid": mid, "side": Vector3(-d.z, 0, d.x), "look": mid}
	return {"pos": mid + side * dist + Vector3(0, 1.9, 0), "mid": mid, "side": Vector3(-side.z, 0, side.x), "look": mid}


## 1: in the world, a wide shot (~5 s): her line, wind round her, glow gathering in her hands; the other mage notices.
func _build_up(who: String, _lvl: int) -> void:
	var other := _other_near(who)
	var base := c.global_position
	var spec: Dictionary = load_data().get("characters", {}).get(who, {})
	var g: Array = spec.get("glow", [0.6, 0.8, 1.0])
	var g2: Array = spec.get("glow2", g)
	var col := Color(g[0], g[1], g[2])
	var acc := Color(g2[0], g2[1], g2[2])
	var element := String(spec.get("element", "arcane"))
	var lines := {}
	_sfx("px_flyby_1", -6.0)
	c.play_gesture("wide_arm_spell", 0.5, 0.6)
	_say_async(who, String(LINES[who].feel), lines, "feel")
	for h in [c.left_hand, c.right_hand]:           # glow gathering in her hands
		if h:
			var gp := FX.particles(28, 0.7, FX.pm_motes(element, "gather"), FX.mote_mesh(0.05, true), true)
			gp.emitting = true
			h.add_child(gp)
			_fx.append(gp)
	await get_tree().create_timer(0.6).timeout
	var wind := LookFX.make("wind", col, acc, 1.3)    # the wind rising round her
	main.world.add_child(wind)
	wind.global_position = base + Vector3(0, 0.9, 0)
	LookFX.set_on(wind, true)
	_fx.append(wind)
	await get_tree().create_timer(1.4).timeout
	if other:
		var to := Vector3(base.x - other.global_position.x, 0, base.z - other.global_position.z)
		var tw2 := create_tween()
		tw2.tween_property(other, "rotation:y", other.rotation.y + wrapf(atan2(-to.x, -to.z) - other.rotation.y, -PI, PI), 0.6).set_trans(Tween.TRANS_SINE)
		other.look_head_at(c.chest.global_position if c.chest else base + Vector3(0, 1.4, 0))
		if other.has_method("set_expression"):
			other.set_expression("surprised", 0.7)
		var tl := Time.get_ticks_msec()
		while not bool(lines.get("feel", true)) and Time.get_ticks_msec() - tl < 3000:
			await get_tree().process_frame
		_say_async(other.character_id, String(LINES[other.character_id].see), lines, "see")
	var t_end := Time.get_ticks_msec() + int(BUILD_UP_S * 1000.0) - 2000
	while Time.get_ticks_msec() < t_end or (lines.values().has(false) and Time.get_ticks_msec() < t_end + 3500):
		await get_tree().process_frame


## 2: up into the night sky in about a second, a trail of stars and petals behind her; the lens tilts up after her
## and the other mage's eyes follow her.
func _launch(who: String) -> void:
	var other := _other_near(who)
	var base := c.global_position
	var spec: Dictionary = load_data().get("characters", {}).get(who, {})
	var element := String(spec.get("element", "arcane"))
	var g: Array = spec.get("glow", [0.6, 0.8, 1.0])
	var g2: Array = spec.get("glow2", g)
	_sfx("px_flyby_1", -2.0)
	# the trail: world-space emitters riding on her (the stars and petals stay behind as she rises)
	for kind in ["stars", "petals"]:
		var tr: Node3D
		if kind == "stars":
			tr = FX.particles(90, 1.4, FX.pm_motes(element, "trail"), FX.mote_mesh(0.09, true))
		else:
			tr = LookFX.make("petals", Color(g[0], g[1], g[2]), Color(g2[0], g2[1], g2[2]), 1.6)
		c.add_child(tr)
		tr.position = Vector3(0, 0.9, 0)
		if tr is GPUParticles3D:
			(tr as GPUParticles3D).emitting = true
		else:
			LookFX.set_on(tr, true)
		_fx.append(tr)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(c, "global_position:y", base.y + LAUNCH_H, LAUNCH_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(func(v: float): _lift.y = v, 0.0, LAUNCH_H, LAUNCH_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var tl := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tl < int(LAUNCH_S * 1000.0):
		if other:
			other.look_head_at(c.global_position + Vector3(0, 1.4, 0))
		await get_tree().process_frame
	if other:
		other.look_head_at(null)


## 5: high above the very spot she left, in her new form, she drifts down - petals and sparkles round her, her hair and
## sleeves floating - and lands softly exactly there. The lens follows her down (wide).
func _descend(who: String) -> void:
	var land: Vector3 = (_cont.chars[who].pos if _cont and _cont.chars.has(who) else c.global_position - Vector3(0, LAUNCH_H, 0))
	var other := _other_near(who)
	var spec: Dictionary = load_data().get("characters", {}).get(who, {})
	var element := String(spec.get("element", "arcane"))
	var g: Array = spec.get("glow", [0.6, 0.8, 1.0])
	var g2: Array = spec.get("glow2", g)
	if main.get("teleport_guard") and main.teleport_guard:
		main.teleport_guard.allow(c)
	c.global_position = land + Vector3(0, DESCEND_H, 0)
	if _cont and _cont.chars.has(who):
		c.global_transform.basis = _cont.chars[who].basis
	_lift.y = DESCEND_H
	_lift["follow"] = true
	_float_springs(true)
	for kind in ["petals", "sparkles"]:
		var n := LookFX.make(kind, Color(g[0], g[1], g[2]), Color(g2[0], g2[1], g2[2]), 1.1)
		c.add_child(n)
		n.position = Vector3(0, 1.0, 0)
		LookFX.set_on(n, true)
		_fx.append(n)
	var motes := FX.particles(40, 1.2, FX.pm_motes(element, "rise"), FX.mote_mesh(0.05, true))
	c.add_child(motes)
	motes.position = Vector3(0, 0.6, 0)
	motes.emitting = true
	_fx.append(motes)
	embers3d.global_position = land + Vector3(0, DESCEND_H + 1.0, 0)
	embers3d.restart()
	embers3d.emitting = true
	_sfx("px_shimmer_1", -5.0)
	await _flash_to(0.0, FADE_WHITE)
	_mark("05_descending")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(c, "global_position:y", land.y, DESCEND_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(v: float): _lift.y = v, DESCEND_H, 0.0, DESCEND_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tl := Time.get_ticks_msec()
	var landed := false
	while Time.get_ticks_msec() - tl < int(DESCEND_S * 1000.0):
		if other:
			other.look_head_at(c.global_position + Vector3(0, 1.4, 0))
		if not landed and Time.get_ticks_msec() - tl > int((DESCEND_S - 0.35) * 1000.0):
			landed = true
			c.play_gesture("land_soft", 0.25, 0.4)
		await get_tree().process_frame
	c.global_position = land
	_lift["follow"] = false
	_sfx("land_a", -6.0)
	_fx_off()
	_float_springs(false)
	get_tree().create_timer(2.0).timeout.connect(func(): embers3d.emitting = false)
	if other:
		other.look_head_at(null)


## Her hair, sleeves and skirt float while she descends (their gravity turned slightly upward, softer); put back after.
var _springs_saved = null


func _float_springs(on: bool) -> void:
	var sec := c.avatar.find_child("secondary", true, false) if c and c.avatar else null
	if sec == null or sec.get("spring_bones") == null:
		return
	if on and _springs_saved == null:
		_springs_saved = sec.spring_bones
		var kept = _springs_saved.duplicate()
		kept.clear()
		for sb in _springs_saved:
			var d: Resource = (sb as Resource).duplicate()
			var cm := String(sb.comment)
			if cm.begins_with("Hair") or cm.begins_with("Skirt") or cm.begins_with("Sleeve") or cm.begins_with("Cape") or cm.begins_with("Sash"):
				d.set("gravity_scale", float(d.get("gravity_scale")) * -0.3)
				d.set("stiffness_scale", float(d.get("stiffness_scale")) * 0.55)
				d.set("drag_force_scale", clampf(float(d.get("drag_force_scale")) * 0.6, 0.05, 1.0))
			kept.append(d)
		sec.spring_bones = kept
	elif not on and _springs_saved != null:
		sec.spring_bones = _springs_saved
		_springs_saved = null
	if sec.has_method("_on_recreate_collider"):
		sec._on_recreate_collider()


## Seconds of black at the start of a video (the AI videos open on ~1.2 s of black): hidden under the white flash.
static func video_lead_in(who: String, lvl: int) -> float:
	return float(load_data().get("video_lead_in_s", {}).get("%s_%d" % [who, lvl], 0.0))


## Before nightfall, while her transformation waits: a brief glow in her hands, wind or petals swirling round her for a
## few seconds - and, if the other mage is near and neither is busy, she notices it aloud and they say a word about it.
const FORESHADOW := {
	"mika": {"notice": ["Luna... your hands were glowing again just now.", "That wind again, Luna. Only around you.", "Luna, you're shimmering. Is it happening again?"],
		"answer": ["I feel it too. Like something is waiting for the night.", "I know. It keeps coming back, stronger each time.", "It's nothing yet. I think it wants the dark."]},
	"luna": {"notice": ["Mika... your hands were glowing again just now.", "That wind again. Only around you, Mika.", "Mika, you're shimmering. Something's coming, isn't it?"],
		"answer": ["I feel it too... like something is waiting for the night.", "I know. It keeps getting stronger.", "Not yet, I think. It wants the stars."]},
}


func foreshadow(who: String) -> void:
	var ch: WorldCharacter = main.characters.get(who)
	if ch == null or not ch.visible or ch.casting or playing != "" or (main.get("performance") and main.performance.busy()):
		return
	var spec: Dictionary = load_data().get("characters", {}).get(who, {})
	var element := String(spec.get("element", "arcane"))
	var g: Array = spec.get("glow", [0.6, 0.8, 1.0])
	var g2: Array = spec.get("glow2", g)
	var made: Array = []
	for h in [ch.left_hand, ch.right_hand]:
		if h:
			var gp := FX.particles(22, 0.7, FX.pm_motes(element, "gather"), FX.mote_mesh(0.045, true), true)
			gp.emitting = true
			h.add_child(gp)
			made.append(gp)
	var kind := "wind" if randf() < 0.5 else "petals"
	var n := LookFX.make(kind, Color(g[0], g[1], g[2]), Color(g2[0], g2[1], g2[2]), 0.8)
	ch.add_child(n)
	n.position = Vector3(0, 0.9, 0)
	LookFX.set_on(n, true)
	made.append(n)
	print("[transform] %s: foreshadowing (%s) - her transformation waits for the night" % [who, kind])
	get_tree().create_timer(3.5).timeout.connect(func():
		for x in made:
			if is_instance_valid(x):
				if x is GPUParticles3D:
					(x as GPUParticles3D).emitting = false
				else:
					LookFX.set_on(x, false, 0.6)
				get_tree().create_timer(2.5).timeout.connect((x as Node).queue_free))
	# the other mage notices it (only when she is near, free, and no one is mid-conversation)
	var other: WorldCharacter = null
	for w in main.characters:
		if w != who and FORESHADOW.has(w):
			var o: WorldCharacter = main.characters[w]
			if o.visible and o.global_position.distance_to(ch.global_position) < 14.0:
				other = o
	if other == null or (main.get("voice") and main.voice.busy()) or (main.get("mage_talk") and main.mage_talk.busy()):
		return
	var ob = main.mage_brains.get(other.character_id)
	if ob and String(ob.current.get("kind", "")) in ["meet", "converse", "together", "duel"]:
		return
	await get_tree().create_timer(1.2).timeout
	other.look_at_point(ch.global_position)
	var nl: Array = FORESHADOW[other.character_id].notice
	await main.voice.say(_voice_of(other.character_id), String(nl[randi() % nl.size()]))
	var al: Array = FORESHADOW[who].answer
	await main.voice.say(_voice_of(who), String(al[randi() % al.size()]))


func _fx_off() -> void:
	for n in _fx:
		if is_instance_valid(n):
			if n is GPUParticles3D:
				(n as GPUParticles3D).emitting = false
			else:
				LookFX.set_on(n, false, 0.2)
			get_tree().create_timer(3.0).timeout.connect((n as Node).queue_free)
	_fx.clear()
	if c:
		c.end_gesture()                   # (her raised-arms pose of the build-up)


## 5: back in the world in her new form. The weapon this form brings (from Level 20 on) appears in her hand; she says
## so, the other mage answers; both held where they are meanwhile, a wide shot of the two of them.
func _after(who: String, lvl: int) -> void:
	var other := _other_near(who)
	var holds := []
	for w in [who, other.character_id if other else ""]:
		var b = main.mage_brains.get(w) if w != "" else null
		if b:
			b.hold = true
			holds.append(b)
	_weapon_unlocked = WeaponArsenal.unlock(who, lvl) if not _preview else ""
	var wn := weapon_name(who, lvl) if (not _preview or WeaponArsenal.unlocked(who).has(String(WeaponArsenal.table(who).get(str(lvl), {}).get("id", "")))) else ""
	var cam_dir = main.get("director")
	var shot: Dictionary = _scene_shot if not _scene_shot.is_empty() else _wide_shot(c.global_position, other, SHOT_DIST)
	var look := Vector3(shot.get("look", c.global_position)) + Vector3(0, 1.15, 0)
	if cam_dir:
		cam_dir.begin_scene(func(_d: float) -> Dictionary: return {"pos": shot.pos, "look": look, "fov": 50.0, "rate": 2.0, "exact": true})
	var drawn := false
	if wn != "" and c.sword and c.sword.available:
		var wid := String(WeaponArsenal.table(who).get(str(lvl), {}).get("id", ""))
		if wid != "":
			c.sword.summon(wid)
		await c.sword.draw()
		drawn = true
	if other and other.global_position.distance_to(c.global_position) > 2.2:
		# the other mage runs over to her
		var away := Vector3(other.global_position.x - c.global_position.x, 0, other.global_position.z - c.global_position.z)
		# beside her as the lens sees them (both in profile, facing each other), on the side she comes from - never
		# between the lens and her
		var view := Vector3(c.global_position.x - Vector3(shot.pos).x, 0, c.global_position.z - Vector3(shot.pos).z).normalized()
		var side := Vector3(-view.z, 0, view.x)
		if side.dot(away) < 0.0:
			side = -side
		var spot := c.global_position + (side if view.length() > 0.1 else (away.normalized() if away.length() > 0.1 else Vector3.FORWARD)) * 1.6
		other.navigate_to(NavigationServer3D.map_get_closest_point(c.get_world_3d().navigation_map, spot), true)
		var tr := Time.get_ticks_msec()
		while other.current_action == "navigate_to" and Time.get_ticks_msec() - tr < 6000:
			await get_tree().process_frame
		other.stop_action()
	if other:
		other.look_at_point(c.global_position)
		c.look_at_point(other.global_position)
		await get_tree().create_timer(0.4).timeout
	var lines := {}
	await _say_async(who, (String(LINES[who].after_weapon) % wn) if wn != "" else String(LINES[who].after), lines, "after")
	if other:
		other.look_head_at(c.chest.global_position if c.chest else look)
		await _say_async(other.character_id, (String(LINES[other.character_id].react_weapon) % wn) if wn != "" else String(LINES[other.character_id].react), lines, "react")
		other.look_head_at(null)
		if other.has_method("set_expression"):
			other.set_expression("happy", 0.6)
	await get_tree().create_timer(0.8).timeout
	if drawn:
		c.sword.sheathe()
	if cam_dir:
		cam_dir.end_scene()
	for b in holds:
		b.hold = false


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
	Engine.time_scale = 1.0
	_rt_t0 = 0
	if _tfx and is_instance_valid(_tfx):
		if c:
			_tfx.light_on(c.avatar, false)
		_tfx.queue_free()
	_tfx = null
	var res := {"ok": _swapped, "who": playing, "level": level, "mode": "realtime" if _realtime_on and not had_video else ("video" if had_video else "flash"),
		"video": video_path(playing, level).get_file() if had_video else "", "skipped": skip_requested, "skip_by": skip_by,
		"seconds": snappedf(t, 0.01), "avatar": c.avatar_path.get_file(),
		"placeholder": bool(target_avatar(playing, level).get("placeholder", false)), "title": String(fs.get("title", "")),
		"continuity": continuity_report}
	if not bool(opts.get("preview", false)):
		var m := WorldState.mind(playing)
		TransformationDirector.clear_pending(playing, level)
		var sn: Dictionary = m.progress.get("tfseq_seen", {})
		sn[str(level)] = true
		m.progress["tfseq_seen"] = sn
		res["weapon_unlocked"] = _weapon_unlocked if _weapon_unlocked != "" else WeaponArsenal.unlock(playing, level)
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
