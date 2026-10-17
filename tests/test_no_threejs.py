"""The live server serves only the Godot world: no Three.js code, library, page or asset may come back (the old
Three.js world lives in the separate archive repository)."""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILE_RE = re.compile(r"(^|/)three(\.module|\.core|\.min)?\.js$|(^|/)three/|three[._-]?js", re.I)
CODE_RE = re.compile(r"from ['\"]three['\"]|import \* as THREE|three\.module\.js|new THREE\.|three\.js|threejs|THREE\.[A-Z]", re.I)
SELF = "tests/test_no_threejs.py"


def _tracked() -> list[str]:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split("\n")
    return [f for f in out if f and f != SELF]


def test_no_threejs_files():
    assert [f for f in _tracked() if FILE_RE.search(f)] == []


def test_no_threejs_code():
    hits = []
    for f in _tracked():
        p = ROOT / f
        if not p.is_file() or p.stat().st_size > 2_000_000:
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        if CODE_RE.search(text):
            hits.append(f)
    assert hits == []


def test_the_launcher_has_no_other_renderer():
    text = (ROOT / "mika-live.sh").read_text(encoding="utf-8")
    assert "--threejs" not in text and "renderer=godot" in text
