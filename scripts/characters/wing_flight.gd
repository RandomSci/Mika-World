class_name WingFlight
extends RefCounted
## Real flight for a winged form (any look whose appearance profile has "wings"; profile.wings.flight = false opts
## out). She beats her wings to take off, climbs, glides along with slow strong wingbeats, banks into turns, hovers
## with fast beats and flares to land - the wings carry her, not a spell. Built so later regions can have flying
## creatures: `airborne`, `altitude()`, `hover_at()` and casting while hovering are the hooks for fights in the air.
##
##   fly_to(point)      take off, fly over whatever is in the way (open-sky check with her capsule), land at point
##   take_off(height)   rise straight up and hover there
##   hover_at(point)    fly to a point in the air and hover
##   land()             set down on the ground below her
## Each returns {ok, detail}. While airborne the character's physics hands her body to physics() below.

const CRUISE := 6.5            # m/s level flight
const CLIMB := 2.6             # m/s straight up (take-off, hover moves)
const SINK := 2.2              # m/s settling down to land
const CLEAR := 3.2             # m above the highest ground along the way
const MAX_ALT := 28.0          # m above where she took off
const ACCEL := 4.0             # m/s^2
const PITCH_MAX := 34.0        # degrees nose-down at full cruise
const BANK_MAX := 28.0         # degrees into a turn

var c: WorldCharacter
var airborne := false
var state := "ground"          # ground / takeoff / hover / cruise / landing
var vel := Vector3.ZERO
var _path: Array = []          # world points still to fly through
var _hover_point := Vector3.INF
var _pitch := 0.0
var _bank := 0.0
var _yaw_rate := 0.0
var _last_yaw := 0.0
var _beat_snd := 0.0
var _busy := false
var flown_m := 0.0
var _foot_guard_was := true
var _glide_t := 0.0


static func supported(ch: WorldCharacter) -> bool:
	if ch.wing_layer == null:
		return false
	return bool(ch.stage_profile().get("wings", {}).get("flight", true))


func _init(ch: WorldCharacter) -> void:
	c = ch


func altitude() -> float:
	var g := _ground_y(c.global_position)
	return c.global_position.y - g if g > -INF else 0.0


# ------------------------------------------------------------------ public actions
func fly_to(target: Vector3) -> Dictionary:
	if _busy:
		return {"ok": false, "detail": "already flying somewhere"}
	if c.casting or (c.reaction and c.reaction.blocks_actions()):
		return {"ok": false, "detail": "busy"}
	var land_at := target
	var gy := _ground_y(target)
	if gy == -INF:
		return {"ok": false, "detail": "no ground to land on there"}
	land_at.y = gy
	var from := c.global_position
	var alt := _cruise_altitude(from, land_at)
	if alt == INF:
		return {"ok": false, "detail": "no open sky that way"}
	_busy = true
	if not airborne:
		await _take_off(minf(alt - from.y, 2.5))
	var top_a := Vector3(c.global_position.x, alt, c.global_position.z)
	var top_b := Vector3(land_at.x, alt, land_at.z)
	_path = [top_a, top_b, land_at + Vector3(0, 1.4, 0)]
	state = "cruise"
	while not _path.is_empty() and airborne:
		await c.get_tree().physics_frame
	var r := await _land()
	_busy = false
	r["metres"] = snappedf(flown_m, 0.1)
	return r


func take_off(height := 4.0) -> Dictionary:
	if airborne:
		return {"ok": false, "detail": "already in the air"}
	if not c.is_on_floor() or c.casting:
		return {"ok": false, "detail": "not now"}
	var room := _sky_room(c.global_position, height + 1.0)
	if room < 1.5:
		return {"ok": false, "detail": "no room above her to take off"}
	_busy = true
	await _take_off(minf(height, room - 0.6))
	_busy = false
	return {"ok": true, "detail": "in the air, %.1f m up" % altitude()}


func hover_at(p: Vector3) -> Dictionary:
	if not airborne:
		var r := await take_off(2.5)
		if not r.ok:
			return r
	if not _segment_clear(c.global_position, p):
		return {"ok": false, "detail": "something in the way"}
	_path = [p]
	state = "cruise"
	while not _path.is_empty() and airborne:
		await c.get_tree().physics_frame
	return {"ok": true, "detail": "hovering"}


func land() -> Dictionary:
	if not airborne:
		return {"ok": false, "detail": "already on the ground"}
	return await _land()


# ------------------------------------------------------------------ phases
func _take_off(height: float) -> void:
	c.stop_action()
	state = "takeoff"
	c.play_gesture("fly_takeoff" if c.has_clip("fly_takeoff") else "lift_off", 0.15, 0.25)
	_gust(1.0)
	await c.get_tree().create_timer(0.3).timeout
	airborne = true
	_foot_guard_was = c.foot_guard.enabled if c.foot_guard else false
	if c.foot_guard:
		c.foot_guard.enabled = false             # nothing to stand on up there
	c.velocity = Vector3.ZERO
	vel = Vector3.ZERO
	_hover_point = c.global_position + Vector3(0, maxf(height, 1.2), 0)
	c.play_gesture("fly_hover" if c.has_clip("fly_hover") else "combat_idle", 0.35, 0.5)
	var t0 := Time.get_ticks_msec()
	while c.global_position.distance_to(_hover_point) > 0.25 and Time.get_ticks_msec() - t0 < 8000:
		await c.get_tree().physics_frame
	state = "hover"


func _land() -> Dictionary:
	var g := _ground_y(c.global_position)
	if g == -INF:
		return {"ok": false, "detail": "no ground below her"}
	state = "landing"
	_path = []
	_hover_point = Vector3(c.global_position.x, g, c.global_position.z)
	var t0 := Time.get_ticks_msec()
	while c.global_position.y - g > 0.02 and Time.get_ticks_msec() - t0 < 12000:
		await c.get_tree().physics_frame
	airborne = false
	state = "ground"
	if c.foot_guard:
		c.foot_guard.enabled = _foot_guard_was
	_hover_point = Vector3.INF
	c.global_position.y = g + 0.02
	c.velocity = Vector3.ZERO
	vel = Vector3.ZERO
	_set_body_tilt(0.0, 0.0)
	c.play_gesture("fly_land" if c.has_clip("fly_land") else "land_soft", 0.1, 0.45)
	_gust(0.8)
	return {"ok": true, "detail": "landed"}


# ------------------------------------------------------------------ physics (called by the character while airborne)
func physics(dt: float) -> void:
	var p := c.global_position
	var want := Vector3.ZERO
	var speed_cap := CRUISE
	if not _path.is_empty():
		var goal: Vector3 = _path[0]
		var to := goal - p
		var last := _path.size() == 1
		var arrive := 0.6 if not last else 0.25
		if to.length() < arrive:
			_path.pop_front()
			if _path.is_empty():
				_hover_point = goal
		else:
			# slow down into the last point (and into a climb or a descent)
			var vertical := absf(to.y) > Vector2(to.x, to.z).length()
			speed_cap = CLIMB if vertical else CRUISE
			var brake := sqrt(2.0 * ACCEL * maxf(to.length() - arrive, 0.0)) if last else speed_cap
			want = to.normalized() * minf(speed_cap, brake)
	if _path.is_empty() and _hover_point != Vector3.INF:
		var to2 := _hover_point - p
		var sp := CLIMB if state != "landing" else SINK
		if state == "landing":
			sp = clampf(to2.length() * 1.6, 0.35, SINK)          # flare: slow at the very end
		want = to2.normalized() * minf(sp, to2.length() * 2.5) if to2.length() > 0.01 else Vector3.ZERO
	vel = vel.move_toward(want, ACCEL * dt * (2.0 if want.length() < vel.length() else 1.0))
	# never into geometry: stop the part of the motion that would hit something
	var step := vel * dt
	if step.length() > 0.0005:
		var col := c.move_and_collide(step, true)
		if col:
			var n := col.get_normal()
			step = step - n * minf(step.dot(n), 0.0)
			vel = vel - n * minf(vel.dot(n), 0.0)
		c.global_position += step
		flown_m += step.length()
	# face where she flies; nose down with speed, bank into turns
	var h := Vector2(vel.x, vel.z)
	if h.length() > 0.4:
		var yaw := atan2(-vel.x, -vel.z)
		var dy := wrapf(yaw - c.rotation.y, -PI, PI)
		c.rotation.y = lerp_angle(c.rotation.y, yaw, 1.0 - exp(-3.5 * dt))
		_yaw_rate = lerpf(_yaw_rate, dy / maxf(dt, 1e-3) * 0.05, 1.0 - exp(-4.0 * dt))
	else:
		_yaw_rate = lerpf(_yaw_rate, 0.0, 1.0 - exp(-4.0 * dt))
	var tp := clampf(h.length() / CRUISE, 0.0, 1.0) * PITCH_MAX
	var tb := clampf(_yaw_rate * 20.0, -BANK_MAX, BANK_MAX)
	_pitch = lerpf(_pitch, tp, 1.0 - exp(-2.5 * dt))
	_bank = lerpf(_bank, tb, 1.0 - exp(-2.5 * dt))
	_set_body_tilt(_pitch, _bank)
	# body clip: hovering / climbing upright, gliding when moving along
	var gliding := h.length() > 2.5
	var clip := "fly_glide" if gliding and c.has_clip("fly_glide") else ("fly_hover" if c.has_clip("fly_hover") else "combat_idle")
	if String((c.anim_tree.tree_root as AnimationNodeBlendTree).get_node("cast_anim").animation) != "mx/" + clip and state != "takeoff":
		c.play_gesture(clip, 0.45, 0.5)
	# wings: hard beats to climb or hover, slow deep beats with glides when cruising
	if c.wing_layer:
		c.wing_layer.flying = true
		var climbing := vel.y > 0.6
		# hover / climb: small quick beats; cruising: a few deep beats, then a glide with the wings held open and still
		_glide_t += dt
		var burst := fmod(_glide_t, 4.0) < 1.7
		if climbing or not gliding:
			c.wing_layer.beat = 0.55 if not climbing else 0.85
			c.wing_layer.beat_hz = 2.3 if not climbing else 1.9
		else:
			c.wing_layer.beat = 1.0 if burst else 0.0
			c.wing_layer.beat_hz = 1.25
		_beat_snd -= dt
		if _beat_snd <= 0.0 and c.wing_layer.beat > 0.5:
			_beat_snd = 1.0 / c.wing_layer.beat_hz * 2.0
			_gust(0.35)
	c.anim_tree.set("parameters/loco/blend_position", 0.0)


## Pitch / bank of her visible body about her middle (the physics capsule stays upright).
var _base := Transform3D.IDENTITY
var _base_taken := false


func _set_body_tilt(pitch_deg: float, bank_deg: float) -> void:
	if c.avatar == null:
		return
	if not _base_taken:
		_base = c.avatar.transform
		_base_taken = true
	if not airborne:
		c.avatar.transform = _base
		_base_taken = false
		return
	var pivot := Vector3(0, 0.95, 0)
	var r := Basis(Vector3.RIGHT, deg_to_rad(-pitch_deg)) * Basis(Vector3.FORWARD, deg_to_rad(bank_deg))
	var bob := Vector3(0, c.wing_layer.stroke * 0.07, 0) if c.wing_layer else Vector3.ZERO     # each downstroke lifts her
	c.avatar.transform = Transform3D(r * _base.basis, pivot - r * pivot + _base.origin + bob)


# ------------------------------------------------------------------ the sky around her
func _ground_y(p: Vector3) -> float:
	var space := c.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 60.0, p.z), Vector3(p.x, p.y - 60.0, p.z), 1)
	q.exclude = [c.get_rid()]
	var r := space.intersect_ray(q)
	return (r.position as Vector3).y if not r.is_empty() else -INF


## Free height above a point (up to `want`).
func _sky_room(p: Vector3, want: float) -> float:
	var space := c.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.7, 0), p + Vector3(0, 1.7 + want, 0), 1)
	q.exclude = [c.get_rid()]
	var r := space.intersect_ray(q)
	return want if r.is_empty() else (r.position as Vector3).y - p.y - 1.7


## Lowest safe cruising height for the way from a to b, or INF.
func _cruise_altitude(a: Vector3, b: Vector3) -> float:
	var hi := maxf(a.y, b.y)
	var n := maxi(2, int(Vector2(b.x - a.x, b.z - a.z).length() / 1.5))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		var g := _ground_y(p + Vector3(0, 40, 0))       # roofs and treetops count as ground here
		if g > -INF:
			hi = maxf(hi, g)
	var alt := hi + CLEAR
	while alt <= a.y + MAX_ALT:
		if _segment_clear(Vector3(a.x, alt, a.z), Vector3(b.x, alt, b.z)) and _segment_clear(a + Vector3(0, 0.3, 0), Vector3(a.x, alt, a.z)) \
				and _segment_clear(Vector3(b.x, alt, b.z), b + Vector3(0, 0.3, 0)):
			return alt
		alt += 2.0
	return INF


func _segment_clear(a: Vector3, b: Vector3) -> bool:
	var space := c.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.75                      # her body with the wings half open
	cap.height = 1.8
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.collision_mask = 1
	sq.exclude = [c.get_rid()]
	var n := maxi(1, int(a.distance_to(b) / 0.6))
	for k in n + 1:
		sq.transform = Transform3D(Basis.IDENTITY, a.lerp(b, float(k) / n) + Vector3(0, 0.95, 0))
		if not space.intersect_shape(sq, 1).is_empty():
			return false
	return true


func _gust(vol: float) -> void:
	var host: Node = c.get_parent()
	if AudioDirector.instance:
		AudioDirector.instance.play3d("phoenix_wing_gust", c.global_position, "SFX", linear_to_db(vol) - 8.0, "wingbeat", randf_range(0.9, 1.1))
	if vol > 0.7 and host:
		var fx := FX.particles(34, 1.2, FX.pm_leaves("lift"), FX.leaf_mesh(0.08), true)
		fx.emitting = true
		host.add_child(fx)
		fx.global_position = Vector3(c.global_position.x, _ground_y(c.global_position) + 0.1, c.global_position.z)
		c.get_tree().create_timer(2.5).timeout.connect(func(): if is_instance_valid(fx): fx.queue_free())
