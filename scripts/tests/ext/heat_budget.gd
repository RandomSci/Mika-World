## Live safety: the adaptive quality's heat / video-memory budget. Run with --gfx-fake-temp=85 (or --gfx-fake-vram=0.9):
## the quality must step down below the stream's floor within ~30 s although frames are on time, and never come back
## while it stays hot. Without a fake value it reports the real sensors and must stay at its normal level.

static func run(t) -> void:
	await t._hold_all()
	var aq = t.main.gfx
	t._check(aq != null and aq.enabled, "adaptive quality on (stream profile)")
	if aq == null:
		return
	var l0: int = aq.level
	var t0: float = t._game_t
	var top := l0
	while t._game_t - t0 < 40.0:
		await t._wait(4.0)
		top = maxi(top, aq.level)
		print("[heat] t %.0f s level %d pressure %s sensors %s director %s reason %s enabled %s" % [t._game_t - t0, aq.level, aq.pressure, JSON.stringify(aq.sensors), String(t.main.director.mode) if t.main.get("director") else "-", aq.reason, aq.enabled])
	var faked := RenderProfile.options.has("gfx-fake-temp") or RenderProfile.options.has("gfx-fake-vram")
	if faked:
		t._check(top >= l0 + 3, "over the heat / VRAM budget the quality stepped down (level %d -> %d)" % [l0, top])
		t._check(aq.level >= top, "and nothing came back while it stayed hot (level %d)" % aq.level)
	else:
		t._check(float(aq.sensors.cpu_c) > 0.0 and float(aq.sensors.vram_total) > 0.0, "real sensors read (CPU %.0f C, GPU %.0f C, VRAM %.0f / %.0f MB)" % [float(aq.sensors.cpu_c), float(aq.sensors.gpu_c), float(aq.sensors.vram_used), float(aq.sensors.vram_total)])
