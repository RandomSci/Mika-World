class_name AdaptiveQuality
extends Node
## Adaptive 60 (docs/ADAPTIVE_GRAPHICS.md): keeps the world as beautiful as the GPU allows at every moment while
## holding a steady 60 FPS at 1920x1080 - including with a livestream encoder sharing the GPU.
##
## It starts at the best validated quality (the CINEMATIC settings) and, only when frames are measurably over the
## 16.7 ms budget because of the GPU (or the encoder / compositor beside it), gives quality back one small,
## least-noticeable step at a time - distant foliage range, distant shadows, the internal 3D scale (FSR 2
## upscaled to the same 1080p output), the density of big secondary particle emitters, then optional screen-space
## effects. When the scene gets lighter again it restores quality, slowly, one step at a time.
##
## Never touched: the 60 FPS cap, the characters (meshes, textures, LOD - they are kept at full detail), game
## logic, physics, AI, animation. A CPU-bound frame is not "fixed" by lowering graphics: it is reported as such.
## Area loads and shader compilation stalls are recognised and never trigger a downgrade.

signal changed(entry: Dictionary)

var BUDGET_MS := 1000.0 / 60.0           # the frame budget of the profile's cap (60 or 30 FPS), set with the profile
# the ladder: each step changes ONE knob; ordered least noticeable first (validated by measurement, see doc)
# the ladder: each step changes ONE knob, least noticeable first; ordered by MEASURED GPU savings at 1080p
# (--mktest=gfxcal, 2026-10-15; forest / village / ambush, ms saved alone): distant range 52 % -4.9 / -2.8;
# 3D scale 0.83 -3.3 / -2.8 / -3.3, 0.67 -6.2 / -4.8 / -6.4; SSR -0.3 / -0.6 / -2.8; volumetric fog 0 / -0.3 /
# -2.5; mesh LOD 2.5x 0 / -0.3 / -1.9; SSIL -0.3 / -0.9 / -1.1; sun shadow map 4096->2048 -1.9 / -0.3;
# undergrowth density 55 % -0.5 / 0. (The 4096->2048 shadow map saved 1.9 ms in the forest but reallocates the
# shadow atlas - a hitch risk mid-fight - so it is not used.) Shadow distance, SSAO (on/off and quality) and particle density saved
# nothing measurable - so they are NOT on the ladder (shadow reach and spells keep their full look).
const STEPS := [
	{"knob": "distant", "value": 0.82, "label": "distant foliage range 82 %"},
	{"knob": "scale", "value": 0.9, "label": "3D scale 0.90 (FSR; FSR 2 off the stream)"},
	{"knob": "lod", "value": 1.8, "label": "mesh LOD threshold x1.8"},
	{"knob": "distant", "value": 0.66, "label": "distant foliage range 66 %"},
	{"knob": "ssr", "value": 0.0, "label": "screen-space reflections off"},
	{"knob": "scale", "value": 0.83, "label": "3D scale 0.83 (FSR 2)"},
	# the sun's shadow map 4096 -> 2048: -12.4 ms in the ambush (trees' shadows dominate a fight), -1.9 in the
	# forest. It reallocates the shadow atlas, so it is taken at a fight's FIRST moment (the jump below, where the
	# camera cuts to the stand-off anyway) and given back only once the fight is over - never in the middle of one
	{"knob": "shadowmap", "value": 0.5, "label": "sun shadow map 2048", "realloc": true},
	{"knob": "ssil", "value": 0.0, "label": "screen-space indirect light off"},
	{"knob": "distant", "value": 0.52, "label": "distant foliage range 52 %"},
	{"knob": "scale", "value": 0.75, "label": "3D scale 0.75 (FSR 2)"},
	{"knob": "volfog", "value": 0.0, "label": "volumetric fog off"},
	{"knob": "foliage", "value": 0.6, "label": "undergrowth density 60 %"},
	{"knob": "scale", "value": 0.67, "label": "3D scale 0.67 (FSR 2 'Quality')"},
	# fight-specific tail (measured on top of the above in the ambush, where dynamic objects, particles and the
	# characters' contact shading dominate): LOD x2.5 -3.7, secondary particles -2.0, shadow reach -1.3, SSAO
	# -2.3, FSR 1 instead of FSR 2 -2.7 ms. Calm scenes never get this far down.
	{"knob": "lod", "value": 2.5, "label": "mesh LOD threshold x2.5"},
	{"knob": "particles", "value": 0.65, "label": "secondary particles 65 %"},
	{"knob": "shadow", "value": 0.66, "label": "sun shadow distance 66 %"},
	{"knob": "ssao", "value": 0.0, "label": "ambient occlusion off"},
	{"knob": "upscaler", "value": 0.0, "label": "FSR 1 + FXAA (the floor)"},
]
const KNOB_MAX := {"distant": 1.0, "shadow": 1.0, "scale": 1.0, "particles": 1.0, "ssil": 1.0, "ssr": 1.0,
	"volfog": 1.0, "ssao": 1.0, "lod": 1.0, "foliage": 1.0, "shadowmap": 1.0, "ssaoq": 1.0, "upscaler": 1.0}

# decision tuning
const EVAL_EVERY := 0.5
const MIN_GAP_DOWN := 2.5          # s between two downgrades (time to measure the effect of the last one)
const MIN_GAP_DOWN_SEVERE := 1.0   # ... when frames are > 35 % over budget (still one step at a time)
const SETTLED_S := 10.0            # held 60 this long at a level: remembered for this situation
const FIRST_FIGHT_LEVEL := 13      # the first fight of a session (measured: fights settle at level 13-17 at 1080p + NVENC)
const MIN_GAP_UP := 8.0            # s of comfortable headroom before one step of quality comes back
var GPU_HEAVY := BUDGET_MS * 0.82        # (60 FPS) 13.7 ms of GPU work: little room left for spikes / an encoder
var GPU_LIGHT := BUDGET_MS * 0.6         # (60 FPS) 10.0 ms: room to restore a step
const HOLD_AFTER_LOAD := 3.0
# heat and video memory budget (live safety, 2026-10-19): effects must never overheat the laptop or fill VRAM
const HOT_C := 80.0                # CPU package or GPU at/over this: step down even with frames on time
const CRIT_C := 90.0               # CPU (the GPU's: CRIT_GPU_C): faster steps, cinematics no exception
const CRIT_GPU_C := 87.0
const COOL_C := 74.0               # quality comes back only below this
const VRAM_HOT := 0.85
const VRAM_CRIT := 0.92
const VRAM_COOL := 0.78
const SENSE_EVERY := 4.0
const PERF_LOG_EVERY := 60.0

var main: Node
var enabled := false
var level := 0                     # how many ladder steps are applied (0 = full quality)
## The stream's steady floor (30 FPS profile; --gfx-steady=N overrides, 0 = off): it starts there and never restores
## above it. Restoring on every quiet view and dropping again on the next busy one went 175 times in 50 min on stream
## (levels 0-13, 2026-10-17): distant foliage, LOD and the FSR scale switching back and forth = the world popping and
## a shimmer on the characters. Below the floor (a fight) it still steps down and comes back up to the floor.
var steady_floor := 0
var knobs := KNOB_MAX.duplicate()
var history: Array = []            # applied changes (overlay / tests), capped
var step_gain := {}                # step index -> measured GPU ms saved when it was applied
var oscillation := {}              # step index -> times it had to be re-applied soon after being restored
var bottleneck := "ok"
var reason := ""
var stats := {}                    # latest window numbers (overlay)
var stutters := {"compile": 0, "load": 0}

var _frames: Array = []            # [frame_ms, gpu_ms, cpu_ms, compiled] newest last (about 10 s)
var _eval_t := 0.0
var _last_change := -100.0
var _last_restore := {}            # step index -> time restored
var _hold_until := 0.0
var _pending := {}                 # the last change, to measure its effect {step, gpu_before, t}
var _vp_rid: RID
var _comp_prev := 0
var _shadow_size := 0
var _warmed := false
var _diag_hidden: Array = []
var _written := {}                 # the last value this controller wrote, per node (to tell the area's own changes)
var _spike_log := RenderProfile.options.has("gfx-spikes")
var _post_change := 0
var _post_worst := 0.0
var hitchy := {}                   # step index -> the stall its change caused (a hitchy step waits longer)
var _base := {}                    # captured base values per node instance id
var memory := {}                   # situation (area, or area:fight) -> the level that held 60 there
var _sit := ""
var _ok_since := 0.0
var sensors := {"cpu_c": -1.0, "gpu_c": -1.0, "vram_used": -1.0, "vram_total": -1.0, "gpu_util": -1.0}
var pressure := "cool"             # cool / warm / hot / critical (heat or VRAM)
var _cpu_temp_path := ""
var _sense_t := 99.0
var _sensing := false
var _perf_t := 0.0
var _perf_path := ""


## Adaptive at 60 (16.7 ms) or 30 (33.3 ms, the stream profile).
static func is_adaptive(p: String) -> bool:
	return p == RenderProfile.ADAPTIVE_60 or p == RenderProfile.ADAPTIVE_30


func _budget_for(p: String) -> void:
	enabled = is_adaptive(p)
	BUDGET_MS = 1000.0 / (30.0 if p == RenderProfile.ADAPTIVE_30 else 60.0)
	GPU_HEAVY = BUDGET_MS * 0.82
	GPU_LIGHT = BUDGET_MS * 0.6
	steady_floor = int(RenderProfile.options.get("gfx-steady", 9 if p == RenderProfile.ADAPTIVE_30 else 0))


func setup(m: Node) -> void:
	main = m
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_budget_for(RenderProfile.profile)
	RenderProfile.profile_changed.connect(func(p: String):
		_budget_for(p)
		reset_quality())
	if main.get("streaming"):
		main.streaming.before_reveal.append(_warm_area)
		main.streaming.area_activated.connect(func(_a, _r):
			_hold_until = _now() + HOLD_AFTER_LOAD
			if enabled and not _warmed:
				_warmed = true
				_warm_variants()
			else:
				_apply_all())
	get_tree().node_added.connect(_on_node_added)
	_protect_characters()
	_find_cpu_sensor()
	if not RenderProfile.options.has("no-perf-log"):
		_perf_path = String(RenderProfile.options.get("perf-log", "user://perf_log.csv"))
		if not FileAccess.file_exists(_perf_path):
			var f := FileAccess.open(_perf_path, FileAccess.WRITE)
			if f:
				f.store_line("unix,area,fps,avg_ms,p95_ms,gpu_ms,level,pressure,cpu_c,gpu_c,gpu_util,vram_used_mb,vram_total_mb,static_mb,nodes,objects")


# ------------------------------------------------------------------ heat and video memory
## The CPU package temperature file (coretemp / k10temp), read directly: no process to start.
func _find_cpu_sensor() -> void:
	for d in DirAccess.get_directories_at("/sys/class/hwmon"):
		var base := "/sys/class/hwmon/" + d
		var nm := FileAccess.get_file_as_string(base + "/name").strip_edges()
		if nm in ["coretemp", "k10temp", "zenpower"]:
			_cpu_temp_path = base + "/temp1_input"
			return


## Every SENSE_EVERY s: the CPU temperature (a file read) and, on a worker thread, the GPU's temperature, load and
## video memory (nvidia-smi) - never a stall on the frame. --gfx-fake-temp=C / --gfx-fake-vram=F test the budget.
func _sense(delta: float) -> void:
	_sense_t += delta
	if _sense_t < SENSE_EVERY:
		return
	_sense_t = 0.0
	if _cpu_temp_path != "":
		var raw := FileAccess.get_file_as_string(_cpu_temp_path).strip_edges()
		if raw.is_valid_int():
			sensors.cpu_c = float(raw) / 1000.0
	if not _sensing:
		_sensing = true
		WorkerThreadPool.add_task(_read_gpu)
	if RenderProfile.options.has("gfx-fake-temp"):
		sensors.cpu_c = float(RenderProfile.options.get("gfx-fake-temp"))
	if RenderProfile.options.has("gfx-fake-vram"):
		sensors.vram_total = 8151.0
		sensors.vram_used = 8151.0 * float(RenderProfile.options.get("gfx-fake-vram"))
	var vram := float(sensors.vram_used) / float(sensors.vram_total) if float(sensors.vram_total) > 0.0 else 0.0
	var hot := maxf(float(sensors.cpu_c), float(sensors.gpu_c))
	if RenderProfile.options.has("no-heat-budget"):
		pressure = "cool"                                 # (measurement A/B: frame time only, as before)
		return
	if float(sensors.cpu_c) >= CRIT_C or float(sensors.gpu_c) >= CRIT_GPU_C or vram >= VRAM_CRIT:
		pressure = "critical"
	elif hot >= HOT_C or vram >= VRAM_HOT:
		pressure = "hot"
	elif hot >= COOL_C or vram >= VRAM_COOL:
		pressure = "warm"
	else:
		pressure = "cool"


func _read_gpu() -> void:
	var out := []
	var code := OS.execute("nvidia-smi", ["--query-gpu=temperature.gpu,memory.used,memory.total,utilization.gpu", "--format=csv,noheader,nounits"], out)
	if code == 0 and not out.is_empty():
		var parts := String(out[0]).strip_edges().split(",")
		if parts.size() >= 4:
			sensors.gpu_c = float(parts[0])
			sensors.vram_used = float(parts[1])
			sensors.vram_total = float(parts[2])
			sensors.gpu_util = float(parts[3])
	_sensing = false


## One line a minute: what the stream's machine is doing (fps, frame times, quality level, heat, memory) - leaks and
## creeping heat show up here long before they crash anything.
func _perf_log(delta: float) -> void:
	_perf_t += delta
	if _perf_path == "" or _perf_t < PERF_LOG_EVERY:
		return
	_perf_t = 0.0
	var w := window(10.0)
	var f := FileAccess.open(_perf_path, FileAccess.READ_WRITE)
	if f == null or w.is_empty():
		return
	f.seek_end()
	f.store_line("%d,%s,%.1f,%.1f,%.1f,%.1f,%d,%s,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%d,%d" % [int(Time.get_unix_time_from_system()), _situation(),
		Performance.get_monitor(Performance.TIME_FPS), float(w.avg_ms), float(w.p95_ms), float(w.gpu_ms), level, pressure,
		float(sensors.cpu_c), float(sensors.gpu_c), float(sensors.gpu_util), float(sensors.vram_used), float(sensors.vram_total),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT))])


## Behind the travel card, every travel: the new area drawn once under the ladder's extremes (full quality; the
## floor with FSR 1) so ITS materials' pipeline variants compile now, hidden, not in front of the viewers later.
func _warm_area() -> void:
	if not enabled:
		return
	var keep := knobs.duplicate()
	var fl := floor_knobs()
	for k in [fl, {}]:
		apply_knobs(k)
		for i in 3:
			await get_tree().process_frame
	knobs = keep
	_apply_all()
	await get_tree().process_frame


## Every on/off the ladder can make (SSR, SSIL, volumetric fog, the two upscalers) compiles its GPU pipelines the
## first time it is drawn - a stall. Draw each once now, during start-up (behind the boot / first travel card),
## so no change made later in a fight costs a compile.
func _warm_variants() -> void:
	await get_tree().process_frame
	var fl := floor_knobs()
	fl["upscaler"] = 0.0
	for k in [fl, {}, {"upscaler": 0.0}, {}]:
		apply_knobs(k)
		for i in 3:
			await get_tree().process_frame
	_recompute_knobs()
	_apply_all()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ------------------------------------------------------------------ measuring
func _process(delta: float) -> void:
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	# CPU: the render thread's own work plus the physics step (Performance.TIME_PROCESS is the WHOLE frame, not CPU work)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var comp_total := 0
	for k in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		comp_total += RenderingServer.get_rendering_info(k)
	# new pipeline compilations this frame (works whether the counters are per frame or running totals)
	var comp := comp_total - _comp_prev if comp_total >= _comp_prev else comp_total
	_comp_prev = comp_total
	var loading: bool = main != null and main.get("streaming") != null and main.streaming.state != "idle"
	if loading:
		_hold_until = _now() + HOLD_AFTER_LOAD
	if comp > 0 and delta * 1000.0 > BUDGET_MS * 1.5:
		stutters.compile += 1
	if loading and delta * 1000.0 > BUDGET_MS * 1.5:
		stutters.load += 1
	_frames.append([delta * 1000.0, gpu, cpu, comp > 0 or loading])
	if _spike_log and delta * 1000.0 > BUDGET_MS * 1.5:
		print("[gfx-spike] t=%.2f frame=%.1f gpu=%.1f cpu_render=%.1f physics=%.1f compiles=%d loading=%s level=%d draws=%d" % [_now(), delta * 1000.0, gpu,
			RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			comp, loading, level, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	if _post_change > 0:
		_post_change -= 1
		_post_worst = maxf(_post_worst, delta * 1000.0)
		if _post_change == 0 and not history.is_empty():
			history.back()["hitch_ms"] = snappedf(_post_worst, 0.1)
			if _post_worst > BUDGET_MS * 2.5:
				hitchy[int(history.back().get("idx", -1))] = snappedf(_post_worst, 0.1)
	if _frames.size() > 640:
		_frames.pop_front()
	_sense(delta)
	_perf_log(delta)
	_eval_t += delta
	if _eval_t >= EVAL_EVERY:
		_eval_t = 0.0
		_evaluate()


## Window statistics over the last `seconds` (frames flagged as compile / load stalls left out).
func window(seconds: float) -> Dictionary:
	var fs := []
	var t := 0.0
	for i in range(_frames.size() - 1, -1, -1):
		var f: Array = _frames[i]
		t += float(f[0])
		if t > seconds * 1000.0:
			break
		if not bool(f[3]):
			fs.append(f)
	if fs.size() < 10:
		return {}
	var ft := fs.map(func(f): return float(f[0]))
	ft.sort()
	var n1 := maxi(1, int(ft.size() * 0.01))
	var worst := 0.0
	for i in n1:
		worst += float(ft[ft.size() - 1 - i])
	# the average leaves out isolated big stalls (over 2x the budget): one 140 ms hitch must not read as "slow".
	# A genuinely slow scene has all its frames late (~20 ms), so it is still caught; the stalls are counted
	var gsum := 0.0
	var csum := 0.0
	var fsum := 0.0
	var nk := 0
	for f in fs:
		gsum += float(f[1])
		csum += float(f[2])
		if float(f[0]) <= BUDGET_MS * 2.0:
			fsum += float(f[0])
			nk += 1
	var spikes := ft.filter(func(x): return float(x) > BUDGET_MS * 1.5).size()
	return {"n": fs.size(), "avg_ms": fsum / maxi(nk, 1), "p95_ms": float(ft[int(ft.size() * 0.95)]), "p99_ms": float(ft[int(ft.size() * 0.99)]), "spikes": spikes,
		"low1_fps": 1000.0 / (worst / n1), "gpu_ms": gsum / fs.size(), "cpu_ms": csum / fs.size()}


# ------------------------------------------------------------------ deciding
func _evaluate() -> void:
	var w3 := window(3.0)
	var w8 := window(8.0)
	if w3.is_empty():
		return
	stats = w3
	# what limits the frame
	# SUSTAINED lateness only (the average over budget, or more than 5 % of frames late). An isolated spike - a
	# script hiccup, a streaming read, the OS - is counted but never answered with lower graphics: it would not help
	# (at the 30 FPS cap frames average 33.7-33.8 ms however light the GPU is - timer jitter at the cap: "+0.3 ms" took
	# that for lateness and stepped 9 <-> 13 with the GPU at 16 ms, 2026-10-17. The margin grows with the budget.)
	var over: bool = float(w3.avg_ms) > BUDGET_MS + maxf(0.3, BUDGET_MS * 0.03) or float(w3.p95_ms) > BUDGET_MS * 1.12
	stats["spikes"] = int(w3.get("spikes", 0))
	if float(w3.cpu_ms) > BUDGET_MS * 0.85 and float(w3.gpu_ms) < GPU_HEAVY:
		bottleneck = "cpu"
	elif float(w3.gpu_ms) >= GPU_HEAVY:
		bottleneck = "gpu"
	elif over and float(w3.gpu_ms) >= BUDGET_MS * 0.55:
		bottleneck = "contention"        # the GPU is busy and frames still slip: an encoder / the compositor beside it
	elif over:
		bottleneck = "other"             # late frames with the GPU half idle: not a graphics problem - left alone
	else:
		bottleneck = "ok"
	# the effect of the last change, measured once it has settled
	if not _pending.is_empty() and _now() - float(_pending.t) > 2.0:
		var gain := float(_pending.gpu_before) - float(w3.gpu_ms)
		if int(_pending.dir) > 0:
			step_gain[int(_pending.step)] = snappedf(gain, 0.01)
		_pending = {}
	if not enabled or _now() < _hold_until:
		return
	if level < steady_floor:
		while level < steady_floor:
			_step(1, "the stream's steady floor (no quality going back and forth)", w3, level < steady_floor - 1)
		return
	# a situation already met (this place; this place in a fight): go straight to what held 60 here last time
	var sit := _situation()
	if sit != _sit:
		_sit = sit
		_ok_since = _now()
		# a fight never seen here: start from what fights needed elsewhere (or a measured first guess) instead of
		# stepping down through 20 s of a heavy fight; measurement refines it from there
		var known := int(memory.get(sit, -1))
		if known < 0 and sit.ends_with(":fight"):
			known = int(memory.get("*:fight", FIRST_FIGHT_LEVEL))
		if known > level:
			var target := known
			var why0 := "remembered: %s held 60 FPS at level %d" % [sit, target] if memory.has(sit) else "a fight begins: starting from level %d" % target
			while level < target:
				_step(1, why0, w3, level < target - 1)
			return
	if over:
		_ok_since = _now()
	elif _now() - _ok_since > SETTLED_S and pressure in ["cool", "warm"]:
		memory[sit] = level
		if sit.ends_with(":fight"):
			memory["*:fight"] = level
	var cinematic: bool = main.get("director") != null and String(main.director.mode) in ["scene", "signature", "performance", "stargaze"] and not in_fight()
	var since := _now() - _last_change
	var gap := MIN_GAP_DOWN_SEVERE if float(w3.avg_ms) > BUDGET_MS * 1.35 else MIN_GAP_DOWN
	var fighting := in_fight()
	# heat / video memory over budget: one step down even with the frames on time (fewer pixels, particles and
	# shadows = less heat and memory), faster when critical; nothing comes back until it is cool again
	if pressure in ["hot", "critical"] and level < STEPS.size():
		var crit := pressure == "critical"
		# (a cinematic - a dance with all its effects - is where heat builds most: it steps there too, only slower)
		if since >= (MIN_GAP_DOWN_SEVERE if crit else MIN_GAP_DOWN * (3.0 if cinematic else 2.0)):
			if fighting and bool(STEPS[level].get("realloc", false)) and not crit:
				return
			_step(1, "%s: CPU %.0f C, GPU %.0f C, VRAM %.0f / %.0f MB" % [pressure, float(sensors.cpu_c), float(sensors.gpu_c), float(sensors.vram_used), float(sensors.vram_total)], w3)
			_ok_since = _now()
		return
	if over and bottleneck in ["gpu", "contention"] and level < STEPS.size() and since >= gap:
		if cinematic and float(w3.low1_fps) > 50.0:
			return                       # a cut mid-cinematic only when it is really struggling
		if fighting and bool(STEPS[level].get("realloc", false)):
			_step(1, "%s-bound (a reallocating step: taken now, in one go)" % bottleneck, w3, true)     # rare: a fight that started light
		_step(1, "%s-bound: avg %.1f ms, p95 %.1f ms, 1%% low %.0f fps, GPU %.1f ms" % [bottleneck, w3.avg_ms, w3.p95_ms, w3.low1_fps, w3.gpu_ms], w3)
		return
	if over and bottleneck in ["cpu", "other"]:
		reason = ("CPU-bound (%.1f ms of CPU work per frame)" % w3.cpu_ms if bottleneck == "cpu" else
			"late frames with the GPU at %.1f ms (not graphics: scripts / streaming / the OS)" % w3.gpu_ms) + ": graphics changes would not help"
		return
	if level > steady_floor and not cinematic and not w8.is_empty() and pressure == "cool":
		# restore only with clear headroom, one step at a time, more patiently for a step that keeps coming back;
		# quickly when the scene has become much lighter (a calm place after a fight)
		var osc := float(oscillation.get(level - 1, 0))
		var expected_cost := maxf(float(step_gain.get(level - 1, 0.8)), 0.0)
		var plenty := float(w8.gpu_ms) + expected_cost < BUDGET_MS * 0.5 and osc == 0.0
		var gap_up := (3.0 if plenty else MIN_GAP_UP) * (1.0 + osc) * (2.0 if hitchy.has(level - 1) else 1.0)
		var need := GPU_LIGHT - 0.6 * osc
		var realloc_step := bool(STEPS[level - 1].get("realloc", false))
		if realloc_step and fighting:
			return                          # the shadow map comes back after the fight, not during it
		if since >= gap_up and float(w8.gpu_ms) + expected_cost < need and float(w8.p95_ms) <= BUDGET_MS * 1.04 and float(w8.avg_ms) <= BUDGET_MS + 0.2:
			_step(-1, "headroom: GPU %.1f ms (+%.1f expected) over 8 s, p95 %.1f ms" % [w8.gpu_ms, expected_cost, w8.p95_ms], w8)


func _situation() -> String:
	var a := String(main.streaming.current_id) if main and main.get("streaming") else ""
	return a + (":fight" if in_fight() else "")


## A fight: an ambush in progress, the director's combat framing, or a creature going for one of the mages.
func in_fight() -> bool:
	if main == null:
		return false
	if main.get("ambush") != null and bool(main.ambush.busy):
		return true
	if main.get("director") != null and String(main.director.mode) == "combat":
		return true
	if main.get("spawner") != null:
		for m in main.spawner.alive:
			if is_instance_valid(m) and m.target_mage != null and String(m.mstate) in ["chase", "attack", "windup", "strike", "recover"]:
				return true
	return false


func _step(dir: int, why: String, w: Dictionary, quiet := false) -> void:
	var idx := level if dir > 0 else level - 1
	var st: Dictionary = STEPS[idx]
	if dir > 0 and _last_restore.has(idx) and _now() - float(_last_restore[idx]) < 20.0:
		oscillation[idx] = int(oscillation.get(idx, 0)) + 1        # restored too eagerly: wait longer next time
	level += dir
	if dir < 0:
		_last_restore[idx] = _now()
	_recompute_knobs()
	if quiet:
		return                           # part of a remembered jump: applied once, at its last step
	_apply_all()
	_last_change = _now()
	_pending = {"step": idx, "dir": dir, "gpu_before": w.get("gpu_ms", 0.0), "t": _now()}
	reason = why
	_post_change = 30
	_post_worst = 0.0
	var e := {"t": snappedf(_now(), 0.1), "idx": idx, "level": level, "dir": "down" if dir > 0 else "up", "step": String(st.label), "why": why,
		"area": String(main.streaming.current_id) if main.get("streaming") else ""}
	history.append(e)
	if history.size() > 60:
		history.pop_front()
	print("[gfx] ", "quality %s -> level %d (%s): %s" % ["down" if dir > 0 else "up", level, st.label, why])
	changed.emit(e)


func _recompute_knobs() -> void:
	knobs = KNOB_MAX.duplicate()
	for i in level:
		var st: Dictionary = STEPS[i]
		knobs[st.knob] = float(st.value)


## The knobs at the bottom of the ladder (calibration from the floor).
func floor_knobs() -> Dictionary:
	var k := {}
	for st in STEPS:
		k[st.knob] = float(st.value)
	return k


## Calibration / diagnostics: set knobs directly (the ladder is not used). Diagnostic-only keys (never on the
## ladder): x_veg (all vegetation multimeshes hidden), x_fx (all particles hidden), x_shadow (sun shadows off),
## x_trees (tree chunks only hidden) - a GPU cost breakdown, not a quality setting.
func apply_knobs(k: Dictionary) -> void:
	knobs = KNOB_MAX.duplicate()
	knobs.merge(k, true)
	_apply_all()
	# diagnostics only: hide categories, remembering exactly what was visible, and put back only what we hid
	for node in _diag_hidden:
		if is_instance_valid(node):
			if node is DirectionalLight3D:
				(node as DirectionalLight3D).shadow_enabled = true
			else:
				(node as Node3D).visible = true
	_diag_hidden.clear()
	var diag := k.has("x_veg") or k.has("x_trees") or k.has("x_fx") or k.has("x_shadow")
	var w = main.get("world") if main else null
	if w == null or not diag:
		return
	for mmi in (w as Node).find_children("*", "MultiMeshInstance3D", true, false):
		var is_tree := String((mmi as Node).name).to_lower().contains("tree")
		if (mmi as Node3D).visible and (k.has("x_veg") or (k.has("x_trees") and is_tree)):
			(mmi as Node3D).visible = false
			_diag_hidden.append(mmi)
	if k.has("x_fx"):
		for pr in get_tree().get_nodes_in_group("adaptive_particles"):
			if is_instance_valid(pr) and (pr as GPUParticles3D).visible:
				(pr as GPUParticles3D).visible = false
				_diag_hidden.append(pr)
	var sun = w.get("sun")
	if k.has("x_shadow") and sun is DirectionalLight3D and (sun as DirectionalLight3D).shadow_enabled:
		(sun as DirectionalLight3D).shadow_enabled = false
		_diag_hidden.append(sun)


func reset_quality() -> void:
	level = 0
	_recompute_knobs()
	_apply_all()


# ------------------------------------------------------------------ applying (cheap, runtime-safe changes only)
func _apply_all() -> void:
	var vp := get_viewport()
	if is_adaptive(RenderProfile.profile) and not RenderProfile.options.has("aa"):
		var keep_msaa: bool = bool(RenderProfile.SETTINGS[RenderProfile.profile].get("keep_msaa", false))
		if keep_msaa and float(knobs.scale) >= 0.999:
			# native scale: MSAA, no temporal jitter (the stream profile's choice)
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.msaa_3d = RenderProfile.SETTINGS[RenderProfile.profile].get("msaa", Viewport.MSAA_2X)
		else:
			# FSR 2 (temporal, best quality per pixel); at the very bottom FSR 1 + FXAA (much cheaper, a little softer).
			# The stream (keep_msaa) never gets FSR 2: its per-frame jitter is the "trembling" the developer picked MSAA
			# against (2026-10-16) - but every scale step switched it back on, nearly all of the 2026-10-17 stream.
			# There a lower scale is FSR 1 (spatial, no jitter) with the profile's MSAA kept.
			var fsr2 := float(knobs.upscaler) >= 0.5 and not keep_msaa
			vp.msaa_3d = RenderProfile.SETTINGS[RenderProfile.profile].get("msaa", Viewport.MSAA_2X) if keep_msaa else Viewport.MSAA_DISABLED
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if fsr2 else Viewport.SCALING_3D_MODE_FSR
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if fsr2 or keep_msaa else Viewport.SCREEN_SPACE_AA_FXAA
			vp.scaling_3d_scale = float(knobs.scale)
			vp.fsr_sharpness = 0.25           # faces stay crisp at < 1.0 scale
	var w = main.get("world") if main else null
	if w == null:
		return
	# distant foliage: every scattered vegetation chunk fades out sooner (VISIBILITY_RANGE_FADE_SELF: no popping)
	for mmi in (w as Node).find_children("*", "MultiMeshInstance3D", true, false):
		var g := mmi as GeometryInstance3D
		var key := g.get_instance_id()
		if not _base.has(key):
			if g.visibility_range_end <= 0.0:
				continue
			_base[key] = [g.visibility_range_end, g.visibility_range_begin]
		var b: Array = _base[key]
		g.visibility_range_end = float(b[0]) * float(knobs.distant)
		if float(b[1]) > 0.0:
			g.visibility_range_begin = float(b[1]) * float(knobs.distant)      # far-LOD stand-ins take over sooner
	# the sun's shadow distance (and its splits follow): distant shadows are the cheapest to lose
	var sun = w.get("sun")
	if sun is DirectionalLight3D:
		var sk := (sun as Node).get_instance_id()
		var cur := (sun as DirectionalLight3D).directional_shadow_max_distance
		# the area's own value is the base; adopt a new one only if the area changed it (not our last write)
		if not _base.has(sk) or absf(cur - float(_written.get(sk, -1.0))) > 0.001:
			_base[sk] = [cur]
		var v := float(_base[sk][0]) * float(knobs.shadow)
		(sun as DirectionalLight3D).directional_shadow_max_distance = v
		_written[sk] = v
	var env = w.get("env")
	if env is Environment and is_adaptive(RenderProfile.profile):
		var e := env as Environment
		e.ssil_enabled = bool(RenderProfile.get_setting("ssil")) and knobs.ssil > 0.5
		e.ssr_enabled = bool(RenderProfile.get_setting("ssr")) and knobs.ssr > 0.5
		e.ssao_enabled = bool(RenderProfile.get_setting("ssao")) and knobs.ssao > 0.5
		# from the profile itself, never a captured value (the warm-up behind the travel card runs before the area's
		# environment receives its profile settings - a captured "off" once hid the fog for good)
		e.volumetric_fog_enabled = bool(RenderProfile.get_setting("volumetric_fog")) and not RenderProfile.is_compatibility_renderer() and knobs.volfog > 0.5
	if is_adaptive(RenderProfile.profile):
		vp.mesh_lod_threshold = float(RenderProfile.get_setting("lod_threshold")) * float(knobs.lod)
		# the sun's shadow map: 4096 -> 2048 (a one-off reallocation; only ever changed outside a fight's first seconds)
		var want := int(RenderProfile.get_setting("shadow_size")) if float(knobs.shadowmap) >= 0.999 else int(RenderProfile.get_setting("shadow_size")) / 2
		if want != _shadow_size:
			_shadow_size = want
			RenderingServer.directional_shadow_atlas_set_size(want, true)
		if env is Environment:
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM if float(knobs.ssaoq) >= 0.999 else RenderingServer.ENV_SSAO_QUALITY_LOW,
				true, 0.5, 2, 50, 300)
	# undergrowth / understory density: dense scattered chunks draw only a share of their (randomly placed)
	# instances - the trees (small chunk counts) and the characters never change
	for mmi2 in (w as Node).find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = (mmi2 as MultiMeshInstance3D).multimesh
		if mm == null or mm.instance_count < 6 or String((mmi2 as Node).name).to_lower().contains("tree"):
			continue
		mm.visible_instance_count = -1 if float(knobs.foliage) >= 0.999 else maxi(1, int(mm.instance_count * float(knobs.foliage)))
	for p in get_tree().get_nodes_in_group("adaptive_particles"):
		_particles(p as GPUParticles3D)


## Big secondary emitters (motes, sparks, leaves, rain) thin out; small or defining emitters never change. A spell's
## shape, timing, colour and light are untouched: only how many of its many specks are drawn.
func _particles(p: GPUParticles3D) -> void:
	if p == null or not is_instance_valid(p):
		return
	if p.has_meta("hero") or p.amount < 48:
		return
	var key := p.get_instance_id()
	if not _base.has(key):
		_base[key] = [p.amount_ratio]
	p.amount_ratio = float(_base[key][0]) * float(knobs.particles)


func _on_node_added(n: Node) -> void:
	if n is GPUParticles3D and not n.has_meta("managed_ratio"):
		n.add_to_group("adaptive_particles")
		if float(knobs.particles) < 1.0:
			_particles.call_deferred(n)
	elif n is MultiMeshInstance3D and float(knobs.distant) < 1.0:
		_apply_all.call_deferred()


## Mika, Luna and everyone with a face: full mesh detail whatever the LOD threshold does to the scenery.
func _protect_characters() -> void:
	for who in main.characters:
		for g in (main.characters[who] as Node).find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).lod_bias = 4.0


func describe() -> Dictionary:
	return {"enabled": enabled, "level": level, "of": STEPS.size(), "knobs": knobs, "bottleneck": bottleneck, "reason": reason, "hitchy": hitchy.duplicate(),
		"pressure": pressure, "sensors": sensors.duplicate(),
		"stats": stats.duplicate(), "stutters": stutters.duplicate(), "step_gain": step_gain.duplicate(),
		"last": history.back() if not history.is_empty() else {}}
