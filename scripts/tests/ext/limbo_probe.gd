extends RefCounted
## LimboAI 1.8.1 (GDExtension) in our Godot 4.7.2: the classes exist, a BehaviorTree built in code with a custom
## GDScript BTAction runs on a BTPlayer and writes the blackboard, and a LimboHSM switches states on an event.

static func run(t) -> void:
	for cls in ["BTPlayer", "BehaviorTree", "BTAction", "BTSequence", "BTSelector", "LimboHSM", "LimboState", "Blackboard", "BBParam"]:
		t._check(ClassDB.class_exists(cls), "LimboAI class %s" % cls)
	var host := Node.new()
	t.main.add_child(host)
	var bt := BehaviorTree.new()
	var seq := BTSequence.new()
	var task: BTAction = load("res://scripts/anime/combat/brain/bt_probe_task.gd").new()
	seq.add_child(task)
	bt.root_task = seq
	var player := BTPlayer.new()
	player.behavior_tree = bt
	host.add_child(player)
	for i in 6:
		await t.get_tree().process_frame
	var ticks: int = player.blackboard.get_var(&"ticks", 0)
	t._check(ticks >= 3, "behaviour tree ran a GDScript task (%d ticks)" % ticks)
	var hsm := LimboHSM.new()
	var a := LimboState.new()
	a.name = "Range"
	var b := LimboState.new()
	b.name = "Close"
	hsm.add_child(a)
	hsm.add_child(b)
	hsm.add_transition(a, b, &"rush")
	host.add_child(hsm)
	hsm.initialize(host)
	hsm.set_active(true)
	var s0 := String(hsm.get_active_state().name)
	hsm.dispatch(&"rush")
	await t.get_tree().process_frame
	t._check(s0 == "Range" and String(hsm.get_active_state().name) == "Close", "state machine: %s -> %s on 'rush'" % [s0, hsm.get_active_state().name])
	host.queue_free()
