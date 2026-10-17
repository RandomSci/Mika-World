"""Mika's magic training: a finite spellbook, persisted progress, real outcomes.

Fictional fantasy magic as a hobby. Every lesson is executed physically on the
Stage: she walks to the sanctuary, puts the
phone on the tripod, reads the glowing book, speaks the incantation, performs
a retargeted casting clip and the effect fires at the clip's release moment.
The Stage reports what was actually shown; only that is recorded.

Progress (data/mika-magic.json) is long-term: the five-hour activity pool
never resets it. Lessons unlock in order; a lesson passes after enough
successful casts. A lesson passed this cycle is not repeated automatically.
Incantations are fixed per spell (short Latin, real words where possible).
"""

from __future__ import annotations

import json
import random
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

PROGRESS_FILE = Path("data") / "mika-magic.json"


@dataclass(frozen=True)
class Spell:
    id: str
    incantation: str          # displayed text
    meaning: str              # what the Latin means (for her own understanding)
    effect: str               # what a success looks like (frontend handler)
    difficulty: float         # 0..1


SPELLS = {s.id: s for s in [
    Spell("lux_surgat", "Lux surgat.", "let light rise", "a burst of sparks from her hand", .15),
    Spell("orbis_lucis", "Orbis lucis.", "orb of light", "a glowing orb held between her hands, then released", .3),
    Spell("circulus_arcanus", "Circulus arcanus.", "hidden circle", "a rune circle spinning on the floor around her", .35),
    Spell("vertex_lucis", "Vertex lucis.", "peak of light", "a standing rune disc in front of her hands with sparks", .4),
    Spell("flamma_lenis", "Flamma lenis.", "gentle flame", "a soft illusion of flame rising from her hand", .45),
    Spell("glacies", "Glacies, veni.", "ice, come", "a spray of frost-like glitter", .5),
    Spell("ventus_lenis", "Ventus lenis.", "gentle wind", "a spiral of wind-like light around her", .5),
    Spell("astra_lucent", "Astra lucent.", "the stars shine", "rune circle, light trails and a bright orb together", .65),
]}


@dataclass(frozen=True)
class Lesson:
    id: str
    level: int
    title: str
    spells: tuple             # cast in order, repeating, during attempts
    attempts: int
    needed: int               # successes to pass
    book: str                 # what the book page says (fiction)


LESSONS = [
    Lesson("l1_sparks", 1, "Level 1: Small sparks", ("lux_surgat",), 4, 2,
           "Point your hand, breathe out, say the words and let the light jump."),
    Lesson("l2_orb", 2, "Level 2: Floating orb", ("orbis_lucis",), 3, 2,
           "Gather the light between both hands and hold it steady before you let it go."),
    Lesson("l3_circle", 3, "Level 3: Arcane circle", ("circulus_arcanus", "vertex_lucis"), 4, 2,
           "Open the arms wide; the circle forms where your feet stand, then before your hands."),
    Lesson("l4_flame", 4, "Level 4: Elemental illusions I, flame", ("flamma_lenis",), 3, 2,
           "A flame that warms nothing: keep it small, keep it gentle."),
    Lesson("l4_frost", 4, "Level 4: Elemental illusions II, frost", ("glacies",), 3, 2,
           "Frost is light that falls. Push it out with both hands."),
    Lesson("l4_wind", 4, "Level 4: Elemental illusions III, wind", ("ventus_lenis",), 3, 2,
           "Wind circles the caster. Open the arms and let it turn."),
    Lesson("l5_combo", 5, "Level 5: Combined spell", ("astra_lucent",), 3, 2,
           "Circle, trails and orb at once. Slow preparation, one clean release."),
    Lesson("l6_sequence", 6, "Level 6: Mastery, the circle sequence", ("circulus_arcanus", "orbis_lucis", "astra_lucent"), 3, 3,
           "Three spells in a row without dropping the light."),
    Lesson("l6_elements", 6, "Level 6: Mastery, the elements", ("flamma_lenis", "glacies", "ventus_lenis"), 3, 3,
           "Fire, frost and wind in turn, each one clean."),
]
LESSONS_BY_ID = {lesson.id: lesson for lesson in LESSONS}


class MagicTraining:
    def __init__(self, path: Optional[Path] = PROGRESS_FILE, clock: Callable[[], float] = time.time, rng=None):
        self.path, self.clock, self.rng = path, clock, rng or random.Random()
        self.state = {"passed": [], "practice": {}, "attempts": [], "unfinished": None, "sessions": 0}
        self.load()

    def load(self) -> None:
        if not self.path:
            return
        try:
            data = json.loads(Path(self.path).read_text())
            if isinstance(data, dict):
                self.state.update(data)
        except Exception:
            pass

    def save(self) -> None:
        if not self.path:
            return
        Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        tmp = Path(str(self.path) + ".tmp")
        tmp.write_text(json.dumps(self.state, indent=1))
        tmp.replace(self.path)

    # ---- progression
    def level(self) -> int:
        passed = set(self.state["passed"])
        return max([LESSONS_BY_ID[i].level for i in passed if i in LESSONS_BY_ID] or [0])

    def next_lesson(self, exclude: tuple = ()) -> Optional[Lesson]:
        """The first lesson not yet passed (lessons unlock in order)."""
        passed = set(self.state["passed"])
        for lesson in LESSONS:
            if lesson.id not in passed and lesson.id not in exclude:
                return lesson
        return None  # everything passed: review mode picks a mastery lesson

    def review_lesson(self) -> Lesson:
        return self.rng.choice([lesson for lesson in LESSONS if lesson.level >= 5])

    def outcome(self, spell_id: str) -> str:
        """success | partial | fail | mishap, from difficulty and her practice."""
        spell = SPELLS[spell_id]
        practice = int(self.state["practice"].get(spell_id, 0))
        p_success = min(.9, .62 - spell.difficulty * .45 + practice * .07)
        roll = self.rng.random()
        if roll < .06 + spell.difficulty * .04:
            return "mishap"
        if roll < .06 + spell.difficulty * .04 + p_success:
            return "success"
        return "partial" if self.rng.random() < .55 else "fail"

    def record_cast(self, lesson: Lesson, report: dict) -> None:
        spell = str(report.get("spell"))
        outcome = str(report.get("outcome"))
        self.state["practice"][spell] = int(self.state["practice"].get(spell, 0)) + 1
        self.state["attempts"].append({"lesson": lesson.id, "spell": spell, "outcome": outcome, "at": self.clock(),
                                       "firedAt": report.get("firedAt"), "effects": report.get("effects")})
        self.state["attempts"] = self.state["attempts"][-300:]
        self.save()

    def finish_lesson(self, lesson: Lesson, successes: int, attempts: int) -> dict:
        passed = successes >= lesson.needed
        if passed and lesson.id not in self.state["passed"]:
            self.state["passed"].append(lesson.id)
        self.state["unfinished"] = None if passed else {"lesson": lesson.id, "successes": successes, "attempts": attempts, "at": self.clock()}
        self.state["sessions"] = int(self.state.get("sessions", 0)) + 1
        self.save()
        return {"lesson": lesson.id, "title": lesson.title, "passed": passed, "successes": successes, "attempts": attempts,
                "level": self.level(), "next": (self.next_lesson() or lesson).title}

    def snapshot(self) -> dict:
        nxt = self.next_lesson()
        return {"level": self.level(), "passed": list(self.state["passed"]), "nextLesson": nxt.title if nxt else "all lessons passed (mastery review)",
                "unfinished": self.state.get("unfinished"), "sessions": self.state.get("sessions", 0),
                "recentCasts": [{k: a[k] for k in ("spell", "outcome")} for a in self.state["attempts"][-6:]]}
