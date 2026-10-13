class_name BookReader
extends Node
## Real reading. Mika at a lectern / desk / inscription:
##   open the physical book (or scroll / tablet) -> read each page for as long as its text takes
##   (her head follows the page) -> read Latin lines aloud through VoiceService -> learn exactly what that
##   page grants (WorldState) -> turn the page -> close the book.
## The camera director frames the page; the overlay shows the same page legibly for viewers.
## Returns the pages read, what was learned and the incantations spoken. Interruptible via stop().

signal page_shown(book_id: String, page: int, data: Dictionary)
signal reading_finished(book_id: String, result: Dictionary)

static var instance: BookReader

const WORDS_PER_SECOND := 3.2

var main: Node
var current := {}            # {"book": id, "page": n, "pages": total, "anchor": Vector3} while reading
var _stop := false
var _book: OpenBook
var _hands := false


func setup(m: Node) -> void:
	main = m
	instance = self


func stop() -> void:
	_stop = true


## Page turn with her hand: reach the outer corner, lift it over with the leaf, return to rest.
func _turn_page(c: WorldCharacter, first_page: int) -> void:
	var corner := _book.turn_corner()
	var rest: Vector3 = c.handler.target.global_position
	if _hands:
		c.gaze_to(corner, 0.25)
		await c.handler.move_right(corner, 0.4)
	_book.turn_to.call(first_page, 0.9)   # runs alongside the hand motion
	if _hands:
		var over: Vector3 = _book.global_transform * Vector3(0.0, 0.16, OpenBook.H * 0.3)
		await c.handler.move_right(over, 0.45)
		await c.handler.move_right(rest, 0.45)
	while _book.turning:
		await get_tree().process_frame


func reading() -> bool:
	return not current.is_empty()


func status() -> Dictionary:
	if current.is_empty():
		return {"reading": false}
	var b := BookLibrary.book(current.book)
	var p: Dictionary = b.pages[current.page] if current.page < b.pages.size() else {}
	return {"reading": true, "book": current.book, "title": b.get("title", ""), "page": current.page + 1, "pages": b.pages.size(),
		"heading": p.get("heading", ""), "text": p.get("text", ""), "latin": p.get("latin", [])}


## anchor: Transform3D (world) where the open book lies (pages face +Y, reader on +Z), or null for
## inscriptions/scrolls that are read where they stand.
func read(c: WorldCharacter, book_id: String, anchor, opts := {}) -> Dictionary:
	var b := BookLibrary.book(book_id)
	if b.is_empty():
		return {"ok": false, "detail": "no such book '%s'" % book_id}
	if not current.is_empty():
		return {"ok": false, "detail": "someone else is reading right now (%s)" % current.get("reader", "?")}
	var who := c.character_id
	var m := WorldState.mind(who)
	var voice_id := String(Progression.mages.get(who, {}).get("voice", who))
	_stop = false
	var style: String = b.get("style", "book")
	# pages can be hidden until something in the world has happened (e.g. the awakened Heartstone)
	var pages: Array = (b.get("pages", []) as Array).filter(func(pg): return not pg.has("requires_knowledge") or m.knowledge.has(pg.requires_knowledge))
	var res := {"ok": true, "book": book_id, "title": b.title, "pages_read": [], "learned": [], "spoken": [], "interrupted": false}
	var look_at: Vector3 = (anchor as Transform3D).origin if anchor != null else c.global_position + -c.global_transform.basis.z * 1.0 + Vector3(0, 1.4, 0)
	current = {"book": book_id, "page": 0, "pages": pages.size(), "anchor": look_at, "reader": who}
	c.look_head_at(look_at)
	if anchor != null and style != "inscription":
		_book = OpenBook.new()
		_book.name = "OpenBook_" + book_id
		main.world.add_child(_book)
		_book.global_transform = anchor
		_book.reader = who
		_book.build(book_id)
		MagicEvents.emit_phase(c, "book", "book_open", style, look_at)
		await _book.open_book(0.9)
		# rest both hands lightly on the lower corners of the book (only when she can comfortably reach)
		var lh: Vector3 = _book.global_transform * Vector3(-OpenBook.W * 0.82, 0.02, OpenBook.H * 0.42)
		var rh: Vector3 = _book.global_transform * Vector3(OpenBook.W * 0.82, 0.02, OpenBook.H * 0.42)
		_hands = c.handler.can_reach(rh) and c.handler.can_reach(lh) and c.handler.held == null
		if _hands:
			await c.handler.rest_hands(lh, rh, 0.7)
	var overlay: BookOverlay = main.book_overlay
	var already: Array = BookLibrary.pages_read(book_id, who).duplicate()
	# the page card is for viewers: shown when the camera is on this reader
	var show_card: bool = main.director == null or main.director.mika == c
	for i in pages.size():
		if _stop:
			res.interrupted = true
			break
		var p: Dictionary = pages[i]
		current.page = i
		if _book and i > 0 and i % 2 == 0:
			MagicEvents.emit_phase(c, "book", "page_turn", style, look_at)
			await _turn_page(c, i)
		for l in p.get("latin", []):
			main.voice.prefetch(voice_id, String(l.text))
		if show_card:
			overlay.show_page(style, String(b.title), p, i, pages.size())
		page_shown.emit(book_id, i, p)
		var words := String(p.get("text", "")).split(" ", false).size() + String(p.get("heading", "")).split(" ", false).size()
		var t := clampf(words / WORDS_PER_SECOND + 1.5, 4.5, 18.0) * float(opts.get("time_scale", 1.0))
		var t_end := Time.get_ticks_msec() / 1000.0 + t
		# read the Latin aloud partway through the page (her own discovery, so it is spoken)
		for l in p.get("latin", []):
			await get_tree().create_timer(minf(2.5, t * 0.3)).timeout
			if _stop:
				break
			var spoken: Dictionary = await main.voice.say(voice_id, String(l.text), {"latin": true})
			res.spoken.append({"latin": l.text, "translation": l.translation, "audio": spoken.get("audio", false), "seconds": spoken.get("seconds", 0)})
		# her eyes travel down the page she is reading, line by line, with small pauses
		var side := i % 2
		var t_start := Time.get_ticks_msec() / 1000.0
		var next_glance := 0.0
		while Time.get_ticks_msec() / 1000.0 < t_end and not _stop:
			await get_tree().process_frame
			var now := Time.get_ticks_msec() / 1000.0
			if now >= next_glance:
				var prog := clampf((now - t_start) / maxf(t_end - t_start, 0.1), 0.0, 1.0)
				var gp: Vector3
				if _book:
					gp = _book.read_point(side, prog) + Vector3(randf_range(-0.03, 0.03), 0, 0)
				else:
					gp = look_at + Vector3(randf_range(-0.25, 0.25), 0.3 - prog * 0.6, 0)
				c.gaze_to(gp, 0.3)
				next_glance = now + randf_range(0.9, 1.8)
		if _stop:
			res.interrupted = true
			break
		# learned only now that the page has actually been read
		var know := {}
		for k in p.get("knowledge", []):
			know[k] = 1
		if not already.has(i):
			already.append(i)
		m.knowledge["read:" + book_id] = already.duplicate()
		var ch := WorldState.record_activity({"id": "read:%s:%d" % [book_id, i], "verb": "read", "label": "%s, page %d" % [b.title, i + 1]}, {"knowledge": know}, who)
		for k in know:
			res.learned.append(k)
		res.pages_read.append({"page": i + 1, "heading": p.get("heading", ""), "changes": ch})
	if show_card:
		overlay.hide_page()
	if _hands:
		await c.handler.release_hands(0.5)
		_hands = false
	if _book:
		MagicEvents.emit_phase(c, "book", "book_close", style, look_at)
		await _book.close_book(0.6)
		_book.queue_free()
		_book = null
	c.look_head_at(null)
	current = {}
	res["complete"] = res.pages_read.size() == pages.size()
	reading_finished.emit(book_id, res)
	return res
