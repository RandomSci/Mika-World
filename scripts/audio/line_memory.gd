class_name LineMemory
extends RefCounted
## Nobody says the same line twice (Selwyn, 22 Oct): Mika, Luna, every villager and the phoenix. Every line spoken
## in the world is remembered per speaker (her voice), with whom it was said to and when, saved with the game
## (WorldState.npc_state "_lines", so it survives restarts). VoiceService.say refuses a line that was said before
## (the same words, or nearly: 80 % of the same words in a line of 5 or more), authored line pools pick one not said
## yet (fresh), and a generated conversation line that repeats is written again. A short interjection ("Hm.", "Okay!")
## is not a line. Viewer replies and book reading are exempt (opts allow_repeat), and so is the show's own audio.

const KEEP := 800                     # lines remembered per speaker (the oldest are forgotten)
const MIN_CHARS := 12                 # shorter than this is an interjection, not a line


static func _store() -> Dictionary:
	if not WorldState.npc_state.has("_lines"):
		WorldState.npc_state["_lines"] = {}
	return WorldState.npc_state["_lines"]


static func norm(t: String) -> String:
	var s := t.to_lower()
	var out := ""
	for ch in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else " "
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()


static func _similar(a: String, b: String) -> bool:
	if a == b:
		return true
	var wa := a.split(" ", false)
	var wb := b.split(" ", false)
	if wa.size() < 5 or wb.size() < 5:
		return false
	var sa := {}
	for w in wa:
		sa[w] = true
	var common := 0
	var sb := {}
	for w in wb:
		if not sb.has(w):
			sb[w] = true
			if sa.has(w):
				common += 1
	return float(common) / float(maxi(sa.size(), sb.size())) >= 0.8


## The earlier time she said it, or {} if she never has.
static func said_before(speaker: String, text: String) -> Dictionary:
	var n := norm(text)
	if n.length() < MIN_CHARS:
		return {}
	for e in _store().get(speaker, []):
		if _similar(n, String(e.n)):
			return e
	return {}


static func note(speaker: String, text: String, to := "") -> void:
	var n := norm(text)
	if n.length() < MIN_CHARS:
		return
	var st := _store()
	var arr: Array = st.get(speaker, [])
	arr.append({"n": n, "to": to, "t": int(Time.get_unix_time_from_system())})
	if arr.size() > KEEP:
		arr = arr.slice(arr.size() - KEEP)
	st[speaker] = arr


## A line from an authored pool she has not said yet (random among those), or "" when she has said them all.
static func fresh(speaker: String, pool: Array, rng: RandomNumberGenerator = null) -> String:
	var unused := pool.filter(func(l): return said_before(speaker, String(l)).is_empty())
	if unused.is_empty():
		return ""
	var i := rng.randi() % unused.size() if rng else randi() % unused.size()
	return String(unused[i])
