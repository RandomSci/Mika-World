class_name Highlights
extends RefCounted
## Moments worth a Short (23 Oct, Selwyn: "highlight Shorts, max 2 a day"). The game only names the moment and how
## good it is; Mika-Live marks it (CLIPS.mark), saves OBS's replay buffer a little after it and later cuts the best
## two of the day to 9:16 for Selwyn to look at. Nothing is uploaded from here.
## Weights: 5 a rare event (the phoenix, the lake dance), 4 a dance or a level up, 3 a first visit, the boat or
## stargazing together, 2 a smaller first (a new path).

const KEEP := 200
static var log: Array = []


static func moment(main: Node, kind: String, text: String, weight := 3.0) -> void:
	if main == null:
		return
	var m := {"type": "world-moment", "kind": kind, "text": text.left(140), "weight": weight,
		"area": String(main.streaming.current_id) if main.get("streaming") and main.streaming else "", "unix": Time.get_unix_time_from_system()}
	log.append(m)
	if log.size() > KEEP:
		log.pop_front()
	print("[moment] %s (%.0f): %s frame %d" % [kind, weight, m.text, Engine.get_frames_drawn()])
	if main.get("live_link") and main.live_link:
		main.live_link._send(m)
