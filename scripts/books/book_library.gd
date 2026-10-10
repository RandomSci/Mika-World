class_name BookLibrary
extends RefCounted
## data/books.json access + per-book reading progress (pages actually read are tracked in WorldState).

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/books.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
	return _data


static func book(id: String) -> Dictionary:
	return data().books.get(id, {})


static func pages_read(id: String) -> Array:
	return WorldState.knowledge.get("read:" + id, [])


static func summary(id: String) -> Dictionary:
	var b := book(id)
	return {"id": id, "title": b.get("title", id), "style": b.get("style", "book"), "location": b.get("location", ""),
		"pages": b.get("pages", []).size(), "pages_read": pages_read(id).size()}
