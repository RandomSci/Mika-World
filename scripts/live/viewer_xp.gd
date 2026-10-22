class_name ViewerXP
extends Node
## Viewers help the mages grow (Selwyn, 2026-10-21: "A chat message they reply to gives a small bonus, a new subscriber
## or member gives a bigger one, a Super Chat gives the most, and each viewer lantern gives XP. Show it on screen as a
## short thank-you line with the viewer's name (no spam, grouped if many). Propose the rates.")
## The rates are data (progression.json "viewer", proposed 23 Oct, waiting for Selwyn's OK). XP is paid the usual way:
## a recorded activity ("viewer:<kind>:<name>") that Progression prices, so it is banked by the stream pacing like
## every other XP. Caps: one paid chat reply per viewer per 10 minutes and a ceiling an hour, so chat cannot farm it.
## The thank-you line on the overlay groups everyone thanked within GROUP_S into one line.

const GROUP_S := 20.0

var main: Node
var _last_chat := {}                # viewer -> unix of the last paid chat reply
var _hour := {"start": 0.0, "xp": 0.0}
var _pending: Array = []            # [name, kind, xp]
var _flush_at := 0.0


func setup(m: Node) -> void:
	main = m
	name = "ViewerXP"


static func rates() -> Dictionary:
	Progression.load_data()
	return Progression.data.get("viewer", {})


## A viewer did something for the stream. kind: chat_reply | subscriber | member | superchat | lantern.
## `who` is the girl it goes to ("" both). Returns the XP paid to each (0 when capped).
func award(kind: String, viewer: String, amount := 0.0, who := "") -> float:
	var r := rates()
	if r.is_empty() or viewer.strip_edges() == "":
		return 0.0
	var now := Time.get_unix_time_from_system()
	var xp := 0.0
	match kind:
		"chat_reply":
			var caps: Dictionary = r.get("caps", {})
			if now - float(_last_chat.get(viewer, 0.0)) < float(caps.get("chat_per_viewer_s", 600.0)):
				return 0.0
			if now - float(_hour.start) > 3600.0:
				_hour = {"start": now, "xp": 0.0}
			if float(_hour.xp) >= float(caps.get("chat_per_hour", 30.0)):
				return 0.0
			_last_chat[viewer] = now
			xp = float(r.get("chat_reply", 2.0))
			_hour.xp = float(_hour.xp) + xp
		"superchat":
			var sc: Dictionary = r.get("superchat", {})
			xp = clampf(float(sc.get("base", 25.0)) + float(sc.get("per_unit", 1.0)) * maxf(amount, 0.0), float(sc.get("base", 25.0)), float(sc.get("max", 75.0)))
		_:
			xp = float(r.get(kind, 0.0))
	if xp <= 0.0:
		return 0.0
	var ids := [who] if who != "" else ["mika", "luna"]
	for id in ids:
		if not WorldState.minds.has(id) and id != "mika":
			continue
		WorldState.record_activity({"id": "viewer:%s:%s" % [kind, viewer.to_lower().left(40)], "verb": "viewer", "label": "%s from %s" % [kind.replace("_", " "), viewer],
			"xp": xp}, {}, id)
	_pending.append([viewer, kind, xp])
	if _flush_at == 0.0:
		_flush_at = now + GROUP_S
	return xp


func _process(_d: float) -> void:
	if _flush_at == 0.0 or Time.get_unix_time_from_system() < _flush_at:
		return
	_flush_at = 0.0
	var line := thanks_line(_pending)
	_pending.clear()
	if line != "" and main.get("overlay_ui") and main.overlay_ui:
		main.overlay_ui.note(line)
	print("[viewerxp] %s" % line)


## "Thank you Aya, Ren and 3 more, +21 XP": names once each, the biggest gift first.
static func thanks_line(items: Array) -> String:
	if items.is_empty():
		return ""
	var by := {}
	for it in items:
		by[String(it[0])] = float(by.get(String(it[0]), 0.0)) + float(it[2])
	var names := by.keys()
	names.sort_custom(func(a, b): return float(by[a]) > float(by[b]))
	var total := 0.0
	for n in names:
		total += float(by[n])
	var shown := names.slice(0, 2)
	var rest := names.size() - shown.size()
	var who := ", ".join(shown) if rest == 0 and shown.size() < 2 else (" and ".join(shown) if rest == 0 else "%s and %d more" % [", ".join(shown), rest])
	return "Thank you %s, +%d XP" % [who, int(round(total))]
