class_name LyingSprings
## Hair and dress physics while she lies on the ground (ported from env-test's Starfall Hill, _ground_springs).
## Standing, the springs hang from her body along world gravity; lying down that pulls skirts, sleeves and hair
## straight through and round her, so they spiked up and flailed. While she lies:
##   * a ground collider under her (one big sphere per chain, its top ~2 cm below the grass after the chain's own
##     joint radius) - every joint rests on the grass instead of sinking or being shoved up
##   * hair: a little firmer and well damped - it settles in one smooth fan on the grass, no jitter
##   * skirt / cape / sash: soft and heavy - the fabric sinks and lies flat round her
##   * sleeves (and sheer drapes): soft, extra weight - they fall loosely toward the grass
##   * everything else (tassels, pendants, ribbons): just damped
## get_up() puts her own chains back exactly as they were.

const R := 40.0


static func apply(c: WorldCharacter) -> void:
	if c == null or c.avatar == null or c.has_meta("lying_springs"):
		return
	var sec := c.avatar.find_child("secondary", true, false)
	if sec == null or sec.get("spring_bones") == null:
		return
	var original = sec.spring_bones
	var kept = original.duplicate()
	kept.clear()
	for sb in original:
		var cm := String(sb.comment)
		var d: Resource = (sb as Resource).duplicate()
		d.set("collider_groups", (sb.collider_groups as Array).duplicate())
		if cm.begins_with("Hair") and not cm.begins_with("HairRibbon"):
			d.set("stiffness_scale", float(d.get("stiffness_scale")) * 1.25)
			d.set("drag_force_scale", clampf(float(d.get("drag_force_scale")) * 1.5, 0.0, 0.85))
			d.set("gravity_scale", float(d.get("gravity_scale")) * 0.9)
		elif cm.begins_with("Skirt") or cm.begins_with("Cape") or cm.begins_with("Sash"):
			d.set("stiffness_scale", float(d.get("stiffness_scale")) * 0.45)
			d.set("drag_force_scale", 0.88)
			d.set("gravity_scale", float(d.get("gravity_scale")) * 1.4)
		elif cm.begins_with("Sleeve"):
			d.set("stiffness_scale", float(d.get("stiffness_scale")) * 0.08)
			d.set("drag_force_scale", 0.65)
			d.set("gravity_scale", float(d.get("gravity_scale")) * 3.0)
		elif not cm.begins_with("Ear"):
			d.set("drag_force_scale", clampf(float(d.get("drag_force_scale")) * 1.5, 0.0, 0.85))
		kept.append(d)
	# the ground under her (she lies on it: her root is on the ground)
	var surf := c.global_position
	var balls: Array = []
	var n := 0
	for sb in kept:
		var hr: PackedFloat64Array = sb.hit_radius
		var rmax := 0.0
		for v in hr:
			rmax = maxf(rmax, v)
		rmax = float(sb.hit_radius_scale) * (rmax if not hr.is_empty() else 1.0)
		var ball := Node3D.new()
		ball.name = "LyingGround_%d" % n
		c.add_child(ball)
		# addons/vrm/vrm_secondary.gd hands a node-attached collider the skeleton transform where the inverse is
		# expected (S * S * node instead of S^-1 * S * ...): placing it at S^-1 * S^-1 * (the point meant) cancels that
		# (env-test's measured fix; the skeleton stays put while she lies)
		var want := Transform3D(Basis.IDENTITY, surf + Vector3.UP * (0.02 - rmax - R))
		var s_inv := c.skeleton.global_transform.affine_inverse()
		ball.global_transform = s_inv * s_inv * want
		var col = load("res://addons/vrm/vrm_collider.gd").new()
		col.radius = R
		col.node_path = ball.get_path()
		var grp = load("res://addons/vrm/vrm_collider_group.gd").new()
		grp.colliders.append(col)
		sb.collider_groups.append(grp)
		balls.append(ball)
		n += 1
	c.set_meta("lying_springs", original)
	c.set_meta("lying_balls", balls)
	sec.spring_bones = kept
	if sec.has_method("_on_recreate_collider"):
		sec._on_recreate_collider()


## Seated on a solid seat (a stone bench). Two faults on stream (2026-10-17): the skirt's chains hung straight down
## through the stone, and with a row of seat-filling spheres they were shoved out sideways into flat spikes (the
## standing tuning keeps a seated skirt stiff and pointing out from her hips). Now, like a real dress on a bench:
##   * the seat's TOP is a soft bolster: a row of large spheres along the bench whose tops are exactly the seat
##     surface - the cloth rests on the seat under and beside her, and its rounded front lets the dress fall
##     over the edge in front of her knees (nothing fills the space her legs and hips are in)
##   * skirt / cape / sash: softer and heavier, well damped - the fabric drapes over her thighs and the seat
##     instead of holding its standing shape
## Undone by restore().
const SEAT_BALL_R := 0.25


static func apply_seat(c: WorldCharacter, seat: CollisionShape3D) -> void:
	if c == null or c.avatar == null or seat == null or not (seat.shape is BoxShape3D) or c.has_meta("lying_springs"):
		return
	var sec := c.avatar.find_child("secondary", true, false)
	if sec == null or sec.get("spring_bones") == null:
		return
	var size: Vector3 = (seat.shape as BoxShape3D).size
	var xf := seat.global_transform
	var pts: Array[Vector3] = []
	var count := maxi(2, ceili(size.x / 0.15) + 1)
	var rows := 1 if size.z < 0.6 else ceili((size.z - 0.3) / 0.25) + 1     # a deep seat (the Still Stone) gets rows
	for i in count:
		var lx := lerpf(-size.x * 0.5 + 0.1, size.x * 0.5 - 0.1, float(i) / float(count - 1))
		for k in rows:
			var lz := 0.0 if rows == 1 else lerpf(-size.z * 0.5 + 0.15, size.z * 0.5 - 0.15, float(k) / float(rows - 1))
			pts.append(xf * Vector3(lx, size.y * 0.5 - SEAT_BALL_R, lz))
	var original = sec.spring_bones
	var kept = original.duplicate()
	kept.clear()
	var balls: Array = []
	var s_inv := c.skeleton.global_transform.affine_inverse()
	var grp = null
	for sb in original:
		var d: Resource = (sb as Resource).duplicate()
		d.set("collider_groups", (sb.collider_groups as Array).duplicate())
		var cm := String(sb.comment)
		if cm.begins_with("Skirt") or cm.begins_with("Cape") or cm.begins_with("Sash"):
			d.set("stiffness_scale", float(d.get("stiffness_scale")) * 0.3)
			d.set("drag_force_scale", 0.85)
			d.set("gravity_scale", float(d.get("gravity_scale")) * 2.4)
		if cm.begins_with("Skirt") or cm.begins_with("Cape") or cm.begins_with("Sash") or cm.begins_with("Hair"):
			if grp == null:
				grp = load("res://addons/vrm/vrm_collider_group.gd").new()
				for p in pts:
					var ball := Node3D.new()
					ball.name = "SeatCollider_%d" % balls.size()
					c.add_child(ball)
					ball.global_transform = s_inv * s_inv * Transform3D(Basis.IDENTITY, p)     # (see apply: the addon's transform)
					var col = load("res://addons/vrm/vrm_collider.gd").new()
					col.radius = SEAT_BALL_R
					col.node_path = ball.get_path()
					grp.colliders.append(col)
					balls.append(ball)
			d.collider_groups.append(grp)
		kept.append(d)
	c.set_meta("lying_springs", original)
	c.set_meta("lying_balls", balls)
	sec.spring_bones = kept
	if sec.has_method("_on_recreate_collider"):
		sec._on_recreate_collider()


static func restore(c: WorldCharacter) -> void:
	if c == null or not c.has_meta("lying_springs"):
		return
	var sec := c.avatar.find_child("secondary", true, false) if c.avatar else null
	if sec:
		sec.spring_bones = c.get_meta("lying_springs")
		if sec.has_method("_on_recreate_collider"):
			sec._on_recreate_collider()
	for b in c.get_meta("lying_balls", []):
		if is_instance_valid(b):
			(b as Node).queue_free()
	c.remove_meta("lying_springs")
	c.remove_meta("lying_balls")
