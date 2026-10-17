class_name SanctuaryDayCycle
extends Node
## The sanctuary's day follows the world clock (the real clock in normal play / live): the sun climbs from the east
## after dawn, stands high at midday, sinks warm and low in the west, and at dusk the sanctuary turns to night
## (Sanctuary.set_night: lanterns lit, moonlight, the Milky Way of Starfall Hill), back again at dawn. Exposure eases
## through dusk and dawn so the change is never a jump. The sanctuary's own set_night() stays the authority for
## everything night-specific; this only drives when, and the sun in between.

var main: Node
var world: Node
var _acc := 99.0
var _night := false


static func attach(m: Node, w: Node) -> SanctuaryDayCycle:
	var c := SanctuaryDayCycle.new()
	c.name = "SanctuaryDayCycle"
	c.main = m
	c.world = w
	w.add_child(c)
	return c


func _ready() -> void:
	process_priority = 900        # before the weather (950: it dims what this writes) and the stream grade (1000)
	_night = not (WorldState.daylight() >= 0.15)
	WorldState.night = _night
	if world.has_method("set_night"):
		world.set_night(_night)
	_apply()


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.5:
		return
	_acc = 0.0
	var dl := WorldState.daylight()
	# hysteresis: night below 0.12 daylight, day above 0.18 (no flicker at the threshold)
	var want := _night
	if _night and dl > 0.18:
		want = false
	elif not _night and dl < 0.12:
		want = true
	if want != _night:
		_night = want
		WorldState.night = _night
		world.set_night(_night)
		print("[daycycle] %s (%s)" % ["night falls" if _night else "morning", WorldState.time_phrase()])
	_apply()


func _apply() -> void:
	var sun = world.get("sun")
	var env: Environment = world.get("env")
	if sun == null or env == null:
		return
	var h := WorldState.hour_f()
	var dl := WorldState.daylight()
	if _night:
		# the sanctuary's moonlight; only ease the exposure in the half hour around dusk / dawn
		env.tonemap_exposure = lerpf(1.25, 1.05, clampf(dl / 0.12, 0.0, 1.0))
		return
	# day: the sun's path, 06:00 east -> 12:00 high -> 18:00 west
	var t := clampf((h - 6.0) / 12.0, 0.0, 1.0)
	var elev := lerpf(6.0, 58.0, sin(t * PI))
	var az := lerpf(-100.0, 100.0, t)
	(sun as DirectionalLight3D).rotation_degrees = Vector3(-elev, az, 0)
	var low := 1.0 - smoothstep(10.0, 40.0, elev)          # low sun: warmer, softer
	(sun as DirectionalLight3D).light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.72, 0.5), low)
	(sun as DirectionalLight3D).light_energy = lerpf(0.5, 2.4, dl) * lerpf(1.0, 0.8, low)
	env.tonemap_exposure = lerpf(1.2, 0.92, dl)
	env.background_energy_multiplier = lerpf(0.35, 0.7, dl)
	env.ambient_light_energy = lerpf(0.75, 1.0, dl)
