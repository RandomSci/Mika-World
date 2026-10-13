class_name SpellFusion
extends Node
## Elemental fusion prototype: when two DIFFERENT mages land hits of complementary elements on the same
## creature within a short window, the energies meet inside it and detonate. Nothing is scripted: it only
## happens when they actually fight the same creature at the same moment. Recipes are data (RECIPES); each
## participant records the discovery in her OWN mind ("fusion:<id>"), so both learn it, separately.

signal fused(fusion: Dictionary)

const WINDOW_S := 2.5
const RECIPES := {
	"eclipse_convergence": {"name": "Eclipse Convergence", "elements": ["arcane", "umbral"], "bonus": 0.9, "element": "eclipse"},
}

var main: Node
var _last := {}           # monster id -> {who, element, t}
var log: Array = []
var last_check := {}       # the most recent pairing considered (for tests / the dev overlay)


func setup(m: Node) -> void:
	main = m


## Called by MagicSystem after a judged hit on a creature. Returns the fusion that fired, or {}.
func on_hit(who: String, spell_id: String, m: Monster, at: Vector3) -> Dictionary:
	var el := String(MagicSystem.spell(spell_id).get("element", ""))
	var now := Time.get_ticks_msec() / 1000.0
	var prev: Dictionary = _last.get(m.id, {})
	_last[m.id] = {"who": who, "element": el, "t": now}
	if not prev.is_empty():
		last_check = {"monster": m.id, "first": [prev.who, prev.element], "second": [who, el], "gap_s": snappedf(now - float(prev.t), 0.01)}
	if prev.is_empty() or prev.who == who or now - float(prev.t) > WINDOW_S or prev.element == el:
		return {}
	for rid in RECIPES:
		var r: Dictionary = RECIPES[rid]
		if (r.elements as Array).has(el) and (r.elements as Array).has(prev.element):
			_last.erase(m.id)
			return _detonate(rid, r, [prev.who, who], m, at)
	return {}


func _detonate(rid: String, r: Dictionary, mages: Array, m: Monster, at: Vector3) -> Dictionary:
	var host: Node = main.world
	ImpactFX.play(host, at, "eclipse", 1.5, true)
	ImpactFX.shockwave(host, at + Vector3(0, -0.3, 0), Color(0.62, 0.42, 1.0), 5.0)
	var sig := FX.quad("res://shaders/magic/sigil.gdshader", 3.2, {"color": Color(1.0, 0.85, 0.45), "sides": 12, "intensity": 3.5, "draw_progress": 1.0, "spin": 1.2, "seed": 3.0}, true)
	host.add_child(sig)
	sig.global_position = Vector3(at.x, m.global_position.y + 0.06, at.z)
	var tw := sig.create_tween()
	tw.tween_method(func(v: float): (sig.material_override as ShaderMaterial).set_shader_parameter("intensity", v), 3.5, 0.0, 1.4)
	tw.tween_callback(sig.queue_free)
	var res := {}
	if m.alive():
		m.last_attacker = main.characters.get(mages[1])
		res = m.apply_damage(float(r.bonus) * 100.0, String(r.element))
		if res.get("effect", "") == "defeated":
			WorldState.record_activity(res.defeat.activity, res.defeat.effects, mages[1])
	var out := {"fusion": rid, "name": r.name, "mages": mages, "monster": m.id, "result": res.get("effect", "none")}
	for who in mages:
		WorldState.record_activity({"id": "fusion:" + rid, "verb": "fuse", "label": "%s with %s" % [r.name, MagicSystem.display_name(mages[0] if who == mages[1] else mages[1])]},
			{"knowledge": {"fusion:" + rid: 1, "ally:" + String(mages[0] if who == mages[1] else mages[1]): 1}}, who)
	if AudioDirector.instance:
		AudioDirector.instance.play3d("fusion_eclipse", at, "SFX", 0.0, "fusion")
	if main.has_method("show_notice"):
		main.show_notice("%s! %s and %s" % [r.name, MagicSystem.display_name(mages[0]), MagicSystem.display_name(mages[1])])
	log.append(out)
	fused.emit(out)
	return out
