extends Node
## Autoload "MagicEvents": the world-wide bus for magic. Spells announce their phases (audio, camera,
## lip/expression), reactive objects announce what magic actually did (wildlife flee, NPCs notice,
## story clues). Nothing here decides outcomes; it only reports engine facts to listeners.

## A spell phase: activation, rune, gather, charge, release, impact, dissipate (+ blocked / missed).
signal spell_phase(caster: Node, spell_id: String, phase: String, element: String, position: Vector3)
## Magic that reached the world: effect is what the object reported ("flare", "extinguished", "none"...).
signal magic_event(position: Vector3, element: String, power: float, effect: String, object_id: String)

var recent: Array = []   # last 20 magic events (for observation / tests)


func emit_phase(caster: Node, spell_id: String, phase: String, element: String, position: Vector3) -> void:
	spell_phase.emit(caster, spell_id, phase, element, position)


func emit_magic(position: Vector3, element: String, power: float, effect: String, object_id: String) -> void:
	recent.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01), "element": element, "power": snappedf(power, 0.01),
		"effect": effect, "object": object_id, "position": [snappedf(position.x, 0.1), snappedf(position.y, 0.1), snappedf(position.z, 0.1)]})
	if recent.size() > 20:
		recent.pop_front()
	magic_event.emit(position, element, power, effect, object_id)
