class_name AudioBuses
extends RefCounted
## Audio bus layout (built in code, version-controlled):
##   Master <- Music, Ambience, SFX, UI, Voice, Cinematic
## Voice has priority: Ambience, SFX and Music carry a sidechain compressor keyed on the Voice bus, so
## when anyone speaks the world ducks a few dB and comes back smoothly afterwards. Cinematic (the Phoenix's great
## moments: her nova, her transformation, its music cue) plays in stereo over the world, which ducks under it too.

const BUSES := {"Music": -14.0, "Ambience": -10.0, "SFX": -6.0, "UI": -8.0, "Voice": -1.0, "Cinematic": -3.0}


static func ensure() -> void:
	if AudioServer.get_bus_index("Voice") != -1:
		return
	for name in BUSES:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, BUSES[name])
	for name in ["Ambience", "SFX", "Music"]:
		var comp := AudioEffectCompressor.new()
		comp.sidechain = "Voice"
		comp.threshold = -30.0
		comp.ratio = 4.0
		comp.attack_us = 20000.0
		comp.release_ms = 450.0
		comp.gain = 0.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(name), comp)
		var duck := AudioEffectCompressor.new()
		duck.sidechain = "Cinematic"
		duck.threshold = -28.0
		duck.ratio = 3.0
		duck.attack_us = 15000.0
		duck.release_ms = 700.0
		duck.gain = 0.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(name), duck)
	# a gentle limiter on Master keeps stacked spell layers from clipping
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, lim)
	# V3 Part X: the Phoenix's true form speaks through a subtle resonance (same voice, a little depth and air;
	# nothing that distorts the words). Feeds the Voice bus, so the world still ducks under her.
	var pi := AudioServer.bus_count
	AudioServer.add_bus(pi)
	AudioServer.set_bus_name(pi, "VoicePhoenix")
	AudioServer.set_bus_send(pi, "Voice")
	AudioServer.set_bus_volume_db(pi, 0.0)
	var shelf := AudioEffectLowShelfFilter.new()
	shelf.cutoff_hz = 240.0
	shelf.gain = 2.5
	AudioServer.add_bus_effect(pi, shelf)
	var dly := AudioEffectDelay.new()
	dly.dry = 1.0
	dly.tap1_active = true
	dly.tap1_delay_ms = 34.0
	dly.tap1_level_db = -15.0
	dly.tap1_pan = -0.15
	dly.tap2_active = true
	dly.tap2_delay_ms = 61.0
	dly.tap2_level_db = -19.0
	dly.tap2_pan = 0.15
	dly.feedback_active = false
	AudioServer.add_bus_effect(pi, dly)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.62
	rev.damping = 0.55
	rev.predelay_msec = 22.0
	rev.wet = 0.2
	rev.dry = 1.0
	rev.spread = 0.6
	AudioServer.add_bus_effect(pi, rev)


static func describe() -> Dictionary:
	var out := {}
	for i in AudioServer.bus_count:
		out[AudioServer.get_bus_name(i)] = {"volume_db": snappedf(AudioServer.get_bus_volume_db(i), 0.1), "send": AudioServer.get_bus_send(i),
			"effects": range(AudioServer.get_bus_effect_count(i)).map(func(e): return AudioServer.get_bus_effect(i, e).get_class())}
	return out
