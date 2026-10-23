extends RefCounted
## --mktest=shadowreach (2026-10-23, Selwyn: "a weird shadow in Mika's front when she's walking", the canyon at
## Crystal Entrance): the caverns ask for a longer sun shadow reach, and area_base gives it to the sun.

static func run(t) -> void:
	var base: Script = load("res://scripts/world/area_base.gd")
	var cc: Script = load("res://scripts/areas/crystal_caverns.gd")
	var a = cc.new()
	var p: Dictionary = a.env_preset()
	print("[shadowreach] area_base ok %s, caverns preset reach %s fade %s, stream reach %s" % [base != null,
		p.get("shadow_distance"), p.get("shadow_fade_start"), RenderProfile.get_setting("shadow_distance")])
	a.free()
