class_name SignatureCast
extends RefCounted
## A mage's SIGNATURE cast (Milestone J): her own signature spell (data/mages.json "signature_spell"),
## channelled fully - a deliberate stance, an original formation, a fuller release - with a short
## cinematic camera (CameraDirector "signature" beats). It is the SAME spell through the SAME truthful
## pipeline (MagicSystem.cast: range, line of sight, swept flight, judged hit, resistances); what changes:
##   * it is only possible once she has really mastered the spell (Adept tier or better),
##   * it costs energy and vigor and has a cooldown,
##   * the fuller channel adds power (+0.3, capped like every other bonus).
## Nothing is granted: a novice cannot do it, and a preview (F-key / test) never changes progress.

const COOLDOWN_S := 75.0
const POWER_BONUS := 0.3
const ENERGY_COST := 0.15
const VIGOR_COST := 0.05

static var _ready_at := {}          # who -> seconds (engine time) when it can be used again


static func spell_for(who: String) -> String:
	return String(Progression.mages.get(who, {}).get("signature_spell", ""))


static func can(main: Node, who: String, target: Node) -> Dictionary:
	var sid := spell_for(who)
	if sid == "":
		return {"ok": false, "reason": "no signature spell"}
	var cc: Dictionary = main.magic.can_cast(sid, who)
	if not cc.get("ok", false):
		return {"ok": false, "reason": String(cc.get("reason", "cannot cast"))}
	var adept := 1.5
	for t in MagicSystem.load_catalog().mastery_tiers:
		if t.name == "Adept":
			adept = float(t.min)
	var m: float = main.magic.mastery(sid, who)
	if m < adept:
		return {"ok": false, "reason": "%s is not mastered enough for a signature cast (%.2f < %.2f)" % [sid, m, adept]}
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_ready_at.get(who, 0.0)):
		return {"ok": false, "reason": "signature cooling down (%.0f s)" % (float(_ready_at[who]) - now)}
	var mind := WorldState.mind(who)
	if mind.vigor < 0.45:
		return {"ok": false, "reason": "not enough vigor (%d%%)" % int(mind.vigor * 100)}
	if target == null or not is_instance_valid(target) or not (target is Monster) or not (target as Monster).alive():
		return {"ok": false, "reason": "a signature cast is for a creature she is fighting"}
	return {"ok": true, "spell": sid, "mastery": m}


## Perform it. `preview` = a showcase that changes nothing (no award, no cooldown, no costs).
static func perform(main: Node, c: WorldCharacter, target: Monster, preview := false) -> Dictionary:
	var who := c.character_id
	var chk := can(main, who, target) if not preview else {"ok": true, "spell": spell_for(who)}
	if not chk.ok:
		return {"ok": false, "outcome": "refused", "reason": chk.reason}
	var sid: String = chk.spell
	c.set_meta("signature", true)
	c.set_meta("signature_power", POWER_BONUS)
	if main.director:
		main.director.begin_signature(c, target)
	var res: Dictionary = await main.magic.cast(c, sid, target.id)
	c.remove_meta("signature")
	c.remove_meta("signature_power")
	if main.director:
		main.director.end_signature(c)
	res["signature"] = true
	res["preview"] = preview
	if res.get("ok", false) and not preview:
		_ready_at[who] = Time.get_ticks_msec() / 1000.0 + COOLDOWN_S
		var mind := WorldState.mind(who)
		mind.vigor = clampf(mind.vigor - VIGOR_COST, 0.0, 1.0)
		var b = main.mage_brains.get(who)
		if b:
			b.needs.energy = clampf(b.needs.energy - ENERGY_COST, 0.0, 1.0)
		if not mind.knowledge.has("signature:" + sid):
			WorldState.record_activity({"id": "signature:" + sid, "verb": "channel", "label": "First signature cast: %s" % MagicSystem.spell(sid).get("name", sid)},
				{"knowledge": {"signature:" + sid: 1}}, who)
	return res
