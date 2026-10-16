#!/usr/bin/env bash
# Transformation cutscenes: an AI-generated video per form -> the cutscene the game plays.
#
#   tools/transformations/convert.sh <video> <character> <level>   convert one file
#   tools/transformations/convert.sh --watch                        convert whatever is dropped into the inbox
#
# The inbox is assets/transformations/incoming/ (Godot ignores it). Name the drop <character>_<level>.<ext>, e.g.
# mika_10.mp4 or luna_40.mov. Output: assets/transformations/<character>_<level>.ogv - Ogg Theora video 1920x1080,
# 30 fps (any other size or aspect is scaled to fit and letterboxed in black, never stretched or cropped), Vorbis
# stereo 48 kHz audio (silence is added when the source has none). The source is moved to incoming/done/ after a
# successful conversion; a failed one goes to incoming/failed/ with its log.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="$ROOT/assets/transformations"
INBOX="$OUT_DIR/incoming"

convert_one() {
	local src="$1" who="$2" lvl="$3"
	[[ "$who" =~ ^(mika|luna)$ ]] || { echo "unknown character '$who' (mika or luna)" >&2; return 2; }
	[[ "$lvl" =~ ^[0-9]+$ ]] || { echo "level must be a number, got '$lvl'" >&2; return 2; }
	local out="$OUT_DIR/${who}_${lvl}.ogv" tmp="$OUT_DIR/.${who}_${lvl}.part.ogv"
	local has_audio
	has_audio=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$src" | head -1)
	local amap=(-map 1:a:0) ain=(-f lavfi -t 1 -i anullsrc=r=48000:cl=stereo)
	if [[ -n "$has_audio" ]]; then amap=(-map 0:a:0); ain=(); fi
	ffmpeg -v error -y -i "$src" "${ain[@]}" -map 0:v:0 "${amap[@]}" \
		-vf "scale=1920:1080:force_original_aspect_ratio=decrease:flags=lanczos,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,fps=30,format=yuv420p" \
		-c:v libtheora -q:v 9 -g 30 -c:a libvorbis -q:a 6 -ar 48000 -ac 2 -shortest "$tmp"
	mv -f "$tmp" "$out"
	echo "converted $src -> $out ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out") s)"
}

if [[ "${1:-}" == "--watch" ]]; then
	mkdir -p "$INBOX/done" "$INBOX/failed"
	echo "watching $INBOX (drop <character>_<level>.mp4) - Ctrl+C to stop"
	declare -A seen_size
	while true; do
		for f in "$INBOX"/*; do
			[[ -f "$f" ]] || continue
			base="$(basename "$f")"; name="${base%.*}"
			[[ "$name" =~ ^(mika|luna)_([0-9]+)$ ]] || { [[ "$base" == .* ]] || { echo "skipping $base: name it <character>_<level>.mp4"; mv -f "$f" "$INBOX/failed/"; }; continue; }
			size=$(stat -c %s "$f")
			if [[ "${seen_size[$f]:-}" != "$size" ]]; then seen_size[$f]=$size; continue; fi   # still being written
			if convert_one "$f" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" > "$INBOX/failed/$name.log" 2>&1; then
				cat "$INBOX/failed/$name.log"; rm -f "$INBOX/failed/$name.log"; mv -f "$f" "$INBOX/done/"
			else
				echo "FAILED $base (see incoming/failed/$name.log)"; mv -f "$f" "$INBOX/failed/"
			fi
			unset "seen_size[$f]"
		done
		sleep 3
	done
fi

[[ $# -eq 3 ]] || { sed -n '2,12p' "$0"; exit 2; }
convert_one "$1" "$2" "$3"
