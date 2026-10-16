class_name StreamDay
## "Day N" of the stream, from Mika-Live's data/launch_days.json (its path: --launch-days=<file>, passed by the stage
## launcher). Day 1 is the calendar day (Asia/Manila) of the first public broadcast; every calendar day after counts,
## streamed or not. 0 = unknown (no file, or no public broadcast yet). Read again at most once a minute.

const ZONE_OFFSET_S := 8 * 3600
static var _first_day := -1          # days since the epoch of the launch date (local)
static var _read_at := -1e9


static func day() -> int:
	var now := Time.get_unix_time_from_system()
	if now - _read_at > 60.0:
		_read_at = now
		_first_day = -1
		var path := String(RenderProfile.options.get("launch-days", ""))
		if path != "" and FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			var first := String(d.get("first_launch", "")) if d is Dictionary else ""
			if first.length() >= 10:
				_first_day = int(Time.get_unix_time_from_datetime_string(first.left(10) + "T00:00:00") / 86400)
	if _first_day < 0:
		return 0
	return int((now + ZONE_OFFSET_S) / 86400) - _first_day + 1
