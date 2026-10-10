class_name AudioBuses
extends RefCounted
## Audio bus layout (built in code, version-controlled):
##   Master <- Music, Ambience, SFX, UI, Voice
## Voice has priority: Ambience, SFX and Music carry a sidechain compressor keyed on the Voice bus, so
## when anyone speaks the world ducks a few dB and comes back smoothly afterwards.

const BUSES := {"Music": -14.0, "Ambience": -10.0, "SFX": -6.0, "UI": -8.0, "Voice": -1.0}


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
	# a gentle limiter on Master keeps stacked spell layers from clipping
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, lim)


static func describe() -> Dictionary:
	var out := {}
	for i in AudioServer.bus_count:
		out[AudioServer.get_bus_name(i)] = {"volume_db": snappedf(AudioServer.get_bus_volume_db(i), 0.1), "send": AudioServer.get_bus_send(i),
			"effects": range(AudioServer.get_bus_effect_count(i)).map(func(e): return AudioServer.get_bus_effect(i, e).get_class())}
	return out
