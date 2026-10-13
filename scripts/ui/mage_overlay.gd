class_name MageOverlay
extends CanvasLayer
## Two small overlays built from verified state only.
##   Viewer (always on, compact, bottom-left): the mage in the spotlight - name, level + title, XP bar,
##   what she is doing, her current objective (from her own knowledge), and the latest notable event
##   (level, victory, discovery, fusion, transformation) for both mages.
##   Developer (F2, top-right): per mage - chosen action + utility + reasons, target, spell state, battle
##   state (vigor, threat), latest memory update, plus creatures alive, FPS and LLM status.

var main: Node
var viewer: PanelContainer
var v_name: Label
var v_bar: ProgressBar
var v_doing: Label
var v_goal: Label
var v_event: Label
var dev: Label
var dev_on := false
var events: Array = []          # {t, text}
var _acc := 0.0


func setup(m: Node) -> void:
	main = m
	layer = 5
	viewer = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.55)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	viewer.add_theme_stylebox_override("panel", sb)
	viewer.anchor_top = 1.0
	viewer.anchor_bottom = 1.0
	viewer.position = Vector2(18, -150)
	viewer.custom_minimum_size = Vector2(360, 0)
	add_child(viewer)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	viewer.add_child(box)
	v_name = _label(box, 18, Color(1.0, 0.94, 0.85))
	v_bar = ProgressBar.new()
	v_bar.custom_minimum_size = Vector2(330, 6)
	v_bar.show_percentage = false
	v_bar.max_value = 1.0
	box.add_child(v_bar)
	v_doing = _label(box, 14, Color(0.9, 0.92, 0.98))
	v_goal = _label(box, 13, Color(0.75, 0.85, 1.0))
	v_event = _label(box, 13, Color(1.0, 0.85, 0.6))
	dev = Label.new()
	dev.anchor_left = 1.0
	dev.anchor_right = 1.0
	dev.position = Vector2(-560, 70)
	dev.custom_minimum_size = Vector2(540, 0)
	dev.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dev.add_theme_font_size_override("font_size", 12)
	dev.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	dev.add_theme_constant_override("outline_size", 4)
	dev.visible = false
	add_child(dev)
	if main.progression:
		main.progression.leveled.connect(func(w, l): note("%s reached Level %d" % [MagicSystem.display_name(w), l]))
		main.progression.gate_blocked.connect(func(w, l, miss): note("%s stands at the Orbit Gate (Level %d): %s" % [MagicSystem.display_name(w), l, ", ".join(miss)]))
	if main.spawner:
		main.spawner.monster_defeated.connect(func(m, by): if by != "": note("%s defeated %s" % [MagicSystem.display_name(by), m.label]))
	if main.magic and main.magic.fusion:
		main.magic.fusion.fused.connect(func(f): note("%s!" % f.name))
	if main.transformer:
		main.transformer.finished.connect(func(w, r): if not r.get("preview", false): note("%s took the %s" % [MagicSystem.display_name(w), String(r.form).capitalize() + " form"]))
	WorldState.mage_event.connect(_on_mage_event)


func _label(parent: Node, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(330, 0)
	parent.add_child(l)
	return l


func note(text: String) -> void:
	events.append({"t": Time.get_ticks_msec() / 1000.0, "text": VoiceService.clean(text)})
	if events.size() > 20:
		events.pop_front()


func _on_mage_event(who: String, kind: String, data) -> void:
	if kind == "trial":
		note("%s completed a trial: %s" % [MagicSystem.display_name(who), data.name])
	elif kind == "activity":
		var id := String(data.get("activity", {}).get("id", ""))
		if id.begins_with("collect:") and (data.changes as Dictionary).keys().any(func(k): return String(k).begins_with("knowledge.material:") and data.changes[k][0] == 0):
			note("%s found %s" % [MagicSystem.display_name(who), String(data.activity.get("label", id.trim_prefix("collect:"))).trim_prefix("Collected ")])


func toggle_dev() -> void:
	dev_on = not dev_on
	dev.visible = dev_on


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.25 or main.world == null:
		return
	_acc = 0.0
	var subject: WorldCharacter = main.director.mika if main.director else main.characters["mika"]
	if main.transformer and main.transformer.playing != "":
		subject = main.characters[main.transformer.playing]      # whoever is transforming has the stage
	var who := subject.character_id
	var pd := Progression.describe(who)
	var brain = main.mage_brains.get(who)
	var form := " · %s" % TransformationDirector.appearance(who).capitalize() if main.transformer and main.transformer.is_transformed(who) else ""
	if main.transformer and main.transformer.has_surge(who):
		form += " (Orbit Surge)"
	v_name.text = "%s  ·  Level %d %s%s" % [MagicSystem.display_name(who), pd.level, ("(" + pd.title + ")") if pd.title != "" else "", form]
	v_bar.value = pd.fraction
	var doing := String(brain.current.get("label", "")) if brain and brain.enabled else ""
	var where := ""
	if main.world:
		var sid := SanctuaryBrain.sub_area(main.world, subject.global_position)
		where = String(WorldState.sanctuary.sub_areas[sid].name) if sid != "" else String(WorldState.locations.get(main.world.location_at(subject.global_position), {}).get("name", ""))
	v_doing.text = (("Now: " + doing) if doing != "" else "Now: taking a moment") + ((" · " + where) if where != "" else "")
	if main.performance and main.performance.busy() and String(main.performance.active.get("who", "")) == who:
		var pa: Dictionary = main.performance.active
		v_doing.text = "♪ %s · %s%s" % [pa.title, "Singing & dancing" if pa.get("singing", false) else "Dancing", " (special performance)" if pa.mode == "special" else ""]
	v_goal.text = "Goal: " + _objective(who, pd)
	var recent := events.filter(func(e): return Time.get_ticks_msec() / 1000.0 - float(e.t) < 90.0)
	v_event.text = ("Latest: " + String(recent[-1].text)) if not recent.is_empty() else ""
	viewer.visible = not RenderProfile.tour
	if dev_on:
		dev.text = _dev_text()


func _objective(who: String, pd: Dictionary) -> String:
	var g: Dictionary = pd.gate
	if pd.level % 10 == 9 and g.defined and not g.met:
		var miss: Array = g.requirements.filter(func(r): return not r.met)
		if not miss.is_empty():
			return "the Orbit Gate: " + String(miss[0].label)
	if who == "mika" and main.story:
		return main.story.objective().trim_prefix("Next: ")
	return "Level %d, then the first Aether Orbit" % (pd.level + 1) if pd.level < 10 else "grow toward the second orbit"


func _dev_text() -> String:
	var ld: Dictionary = main.llm.describe() if main.llm else {}
	var lines := ["DEV  fps %.0f  |  LLM %s (%d calls/h)  |  creatures %d  |  forms %s  |  focus %s%s" % [Engine.get_frames_per_second(), ld.get("provider", "-"), int(ld.get("calls_last_hour", 0)),
		main.spawner.alive.size() if main.spawner else 0, JSON.stringify(main.transformer.describe().transformed) if main.transformer else "-", main.focus, " (locked)" if main.focus_locked else ""]]
	var sc := StreamContext.describe(main)
	lines.append("stream: %s live=%s  pending %s" % [sc.mode, sc.live, JSON.stringify(sc.pending_comments)])
	if main.performance and main.performance.busy():
		var pa: Dictionary = main.performance.active
		lines.append("music: %s by %s [%s] t=%.1f s  seg %s  clip speed %s  stage %s" % [pa.song, pa.who, pa.mode, main.performance.music_time(), JSON.stringify(pa.get("segment", {})), str(pa.get("speed", 1.0)), pa.stage])
	for who in main.mage_brains:
		var b = main.mage_brains[who]
		var m := WorldState.mind(who)
		var d: Dictionary = b.last_decision
		var last_mem := ""
		if not m.activity_log.is_empty():
			var e: Dictionary = m.activity_log[-1]
			last_mem = "%s %s" % [e.activity.get("id", ""), str((e.changes as Dictionary).keys()).left(80)]
		var c: WorldCharacter = main.characters[who]
		lines.append("— %s [%s]  L%d xp %.0f  vigor %.0f%%  energy %.0f%%  coverage %d cells  anim %s  %s" % [MagicSystem.display_name(who), main.sim_mode(who), m.level(), float(m.progress.xp), m.vigor * 100.0,
			b.needs.energy * 100.0, int(b.explore_map.coverage()) if b.explore_map else 0,
			String((c.anim_tree.tree_root as AnimationNodeBlendTree).get_node("cast_anim").animation).get_file() if c.anim_tree else "-", "CASTING" if c.casting else ""])
		lines.append("   doing: %s [%s]  stage: %s" % [b.current.get("label", "-"), b.current.get("kind", ""), b.current.get("stage", "")])
		lines.append("   chose: %s  u=%s  why: %s" % [d.get("label", "-"), str(d.get("utility", "")), ", ".join(d.get("why", []))])
		lines.append("   threat: %s  |  memory: %s" % [b.threat.id if b.threat and is_instance_valid(b.threat) else "-", last_mem])
	if main.spawner:
		lines.append("creatures: " + ", ".join(main.spawner.alive.map(func(x): return "%s(%s %.0fhp)" % [x.id, x.mstate, x.hp])))
	return "\n".join(lines)
