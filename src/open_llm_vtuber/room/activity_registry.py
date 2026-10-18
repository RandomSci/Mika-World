"""Mika's authoritative activity registry and the five-hour objective pool.

Registry: every activity Mika may choose by herself, with the capability that
executes it on the Stage, where it happens, what must be true first, what
counts as done and what happens on failure. Only activities whose Stage
capabilities report ``implemented`` (and whose feature flag is on) are
eligible; book reading and flower picking stay disabled.

Pool: at the start of each five-hour cycle the eligible activities become
the open objectives. A genuinely completed activity leaves the pool; a
failed one stays (with its failure recorded) and rests. When the pool is
empty Mika does not loop: she stays free (chat, small gestures, viewer
requests) until the cycle resets. Viewer requests are never blocked by the
pool. The pool is saved to disk and survives restarts; long-term progress
(magic levels, dance history) lives elsewhere and is never reset here.
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

CYCLE_SECONDS = 5 * 3600
POOL_FILE = Path("data") / "mika-activity-pool.json"


def _flag(name: str, default: str = "1") -> bool:
    return os.environ.get(name, default).strip().lower() in ("1", "true", "yes", "on")


@dataclass(frozen=True)
class Activity:
    id: str                       # == autonomy GoalSpec id
    family: str
    requires: tuple               # Stage capabilities that must be implemented
    region: str                   # where it happens (scene / zone)
    preconditions: str
    completion: str
    on_failure: str
    home_only: bool = False       # needs the bedroom (travel is added when away)
    feature_flag: str = ""        # env flag that must be on ("" = always)
    objective: bool = True        # counts as an objective of the pool
    flag_default: str = "1"       # unfinished features default to off

    def enabled(self) -> bool:
        return not self.feature_flag or _flag(self.feature_flag, self.flag_default)


COMPLETE_STEPS = "every planned step acknowledged as completed by the Stage, dwell finished"
REST = "not counted as done; rests 15-60 min (bounded backoff); a broken route rests its whole zone"

REGISTRY: dict[str, Activity] = {a.id: a for a in [
    Activity("magic_training", "magic", ("magic_lesson",), "SANCTUARY (garden)",
             "sanctuary built, casting clips loaded, an unlocked lesson not yet passed this cycle",
             "lesson finished: casts performed with effects, result recorded in her spellbook progress", REST,
             feature_flag="VR_FEATURE_MAGIC"),
    Activity("dance_practice", "dance", ("dance_session",), "STUDIO",
             "studio reachable, at least two routines enabled", "multi-routine session finished, every routine result recorded", REST),
    Activity("rhythm_challenge", "neon_pulse", ("dance_challenge",), "ARCADE",
             "arcade reachable, challenge routine enabled", "challenge finished with its real score", REST),
    Activity("fresh_air", "exploration", ("visit_gardens",), "GROUNDS", "garden reachable",
             COMPLETE_STEPS, REST),
    Activity("explore", "exploration", ("explore",), "GROUNDS", "garden reachable",
             "reached an unvisited garden spot and stayed there", REST),
    Activity("lantern_walk", "exploration", ("visit_lantern_retreat",), "GROUNDS", "garden reachable",
             COMPLETE_STEPS, REST),
    Activity("atelier", "exploration", ("visit_atelier",), "GROUNDS", "garden reachable", COMPLETE_STEPS, REST),
    Activity("garden_bench", "outdoor_rest", ("sit_bench",), "GROUNDS", "a verified garden bench is free",
             "sat on the bench, rested, stood up again", REST),
    Activity("stargaze", "outdoor_rest", ("quiet_outside",), "GROUNDS", "evening or night", COMPLETE_STEPS, REST),
    Activity("garden_jog", "exercise", ("go_jogging",), "GROUNDS", "daylight preferred; workout outfit",
             "full jog loop and return finished", REST, home_only=True),
    Activity("relax", "indoor", ("sit_chair",), "HOME", "reading chair free", COMPLETE_STEPS, REST, home_only=True),
    Activity("room_tour", "indoor", ("tour_room",), "HOME", "in the bedroom", COMPLETE_STEPS, REST, home_only=True),
    Activity("window", "indoor", ("show_window",), "HOME", "in the bedroom", COMPLETE_STEPS, REST, home_only=True),
    Activity("desk", "indoor", ("show_desk",), "HOME", "in the bedroom", COMPLETE_STEPS, REST, home_only=True),
]}
# Never chosen by herself as an objective (still possible on a viewer request).
NOT_OBJECTIVES = {"head_home", "read", "flower"}


def implemented(reality: dict, name: str) -> bool:
    caps = reality.get("capabilities") or {}
    if name in caps:
        return bool(caps[name].get("implemented"))
    return name in set(reality.get("availableActions") or [])


def verified_ids(reality: dict) -> list[str]:
    """Activities the running Stage can genuinely execute (any scene)."""
    godot = True          # the stream is the Godot world
    # (the Godot world has no bedroom: a home-only objective - "relax" in the reading chair - could never run there,
    # stayed open and kept the five-hour cycle from ever completing)
    return [a.id for a in REGISTRY.values()
            if a.objective and a.enabled() and all(implemented(reality, r) for r in a.requires) and not (godot and a.home_only)]


class ActivityPool:
    def __init__(self, clock: Callable[[], float] = time.time, path: Optional[Path] = POOL_FILE):
        self.clock = clock
        self.path = path
        self.state = {"cycleStartedAt": 0.0, "cycle": 0, "remaining": [], "completed": [], "failed": [], "history": []}
        self.load()

    # ---- persistence
    def load(self) -> None:
        if not self.path:
            return
        try:
            data = json.loads(Path(self.path).read_text())
            if isinstance(data, dict) and "remaining" in data:
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

    # ---- cycle
    def ensure_cycle(self, reality: dict) -> bool:
        """Start a new cycle when none runs or five hours have passed. True if reset."""
        now = self.clock()
        started = float(self.state.get("cycleStartedAt") or 0)
        if started and now - started < CYCLE_SECONDS:
            # Newly verified activities (a capability finished loading) join the cycle.
            known = set(self.state["remaining"]) | {c["id"] for c in self.state["completed"]}
            added = [i for i in verified_ids(reality) if i not in known]
            if added:
                self.state["remaining"] += added
                self.save()
            return False
        ids = verified_ids(reality)
        if not ids:
            return False  # Stage not reporting capabilities yet
        self.state.update({"cycleStartedAt": now, "cycle": int(self.state.get("cycle", 0)) + 1,
                           "remaining": ids, "completed": [], "failed": []})
        self.state["history"] = (self.state.get("history") or [])[-50:]
        self.save()
        return True

    def remaining(self) -> list[str]:
        return list(self.state.get("remaining") or [])

    def exhausted(self) -> bool:
        return bool(self.state.get("cycleStartedAt")) and not self.state.get("remaining")

    def resets_in(self) -> float:
        started = float(self.state.get("cycleStartedAt") or 0)
        return max(0.0, started + CYCLE_SECONDS - self.clock()) if started else 0.0

    # ---- outcomes
    def complete(self, activity_id: str, detail: str = "") -> None:
        now = self.clock()
        if activity_id in self.state["remaining"]:
            self.state["remaining"].remove(activity_id)
            self.state["completed"].append({"id": activity_id, "at": now, "detail": detail[:120]})
        self.state["history"].append({"id": activity_id, "at": now, "result": "completed"})
        self.state["history"] = self.state["history"][-200:]
        self.save()

    def fail(self, activity_id: str, reason: str = "") -> None:
        now = self.clock()
        self.state["failed"].append({"id": activity_id, "at": now, "reason": reason[:160]})
        self.state["failed"] = self.state["failed"][-50:]
        self.state["history"].append({"id": activity_id, "at": now, "result": "failed", "reason": reason[:160]})
        self.state["history"] = self.state["history"][-200:]
        self.save()

    def recent(self, n: int = 6) -> list[dict]:
        return list((self.state.get("history") or [])[-n:])

    def snapshot(self) -> dict:
        return {"cycle": self.state.get("cycle"), "remaining": self.remaining(),
                "completed": [c["id"] for c in self.state.get("completed", [])],
                "failedThisCycle": [f["id"] for f in self.state.get("failed", [])],
                "exhausted": self.exhausted(), "resetsInMinutes": round(self.resets_in() / 60)}
