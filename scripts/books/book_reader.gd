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


func setup(m: Node) -> void:
	main = m
	instance = self


func stop() -> void:
	_stop = true


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
	_stop = false
	var style: String = b.get("style", "book")
	var pages: Array = b.get("pages", [])
	var res := {"ok": true, "book": book_id, "title": b.title, "pages_read": [], "learned": [], "spoken": [], "interrupted": false}
	var look_at: Vector3 = (anchor as Transform3D).origin if anchor != null else c.global_position + -c.global_transform.basis.z * 1.0 + Vector3(0, 1.4, 0)
	current = {"book": book_id, "page": 0, "pages": pages.size(), "anchor": look_at}
	c.look_head_at(look_at)
	if anchor != null and style != "inscription":
		_book = OpenBook.new()
		_book.name = "OpenBook_" + book_id
		main.world.add_child(_book)
		_book.global_transform = anchor
		_book.build(book_id)
		MagicEvents.emit_phase(c, "book", "book_open", style, look_at)
		await _book.open_book(0.9)
	var overlay: BookOverlay = main.book_overlay
	var already: Array = BookLibrary.pages_read(book_id)
	for i in pages.size():
		if _stop:
			res.interrupted = true
			break
		var p: Dictionary = pages[i]
		current.page = i
		if _book and i > 0 and i % 2 == 0:
			MagicEvents.emit_phase(c, "book", "page_turn", style, look_at)
			await _book.turn_to(i, 0.7)
		for l in p.get("latin", []):
			main.voice.prefetch("mika", String(l.text))
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
			var spoken: Dictionary = await main.voice.say("mika", String(l.text), {"latin": true})
			res.spoken.append({"latin": l.text, "translation": l.translation, "audio": spoken.get("audio", false), "seconds": spoken.get("seconds", 0)})
		while Time.get_ticks_msec() / 1000.0 < t_end and not _stop:
			await get_tree().process_frame
		if _stop:
			res.interrupted = true
			break
		# learned only now that the page has actually been read
		var know := {}
		for k in p.get("knowledge", []):
			know[k] = 1
		if not already.has(i):
			already.append(i)
		WorldState.knowledge["read:" + book_id] = already.duplicate()
		var ch := WorldState.record_activity({"id": "read:%s:%d" % [book_id, i], "verb": "read", "label": "%s, page %d" % [b.title, i + 1]}, {"knowledge": know})
		for k in know:
			res.learned.append(k)
		res.pages_read.append({"page": i + 1, "heading": p.get("heading", ""), "changes": ch})
	overlay.hide_page()
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
