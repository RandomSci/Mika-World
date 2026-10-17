"""Goal-based autonomy: the deliberation lane of Mika's showrunner.

Mika pursues her own objectives instead of waiting for chat. A goal is built
only from semantic actions the Stage currently reports as executable, so the
planner can never invent an activity (no drawing until a drawing engine exists).
Physical work still flows through the showrunner's single command path; this
module only decides *what* and *why*, tracks progress and records outcomes.
"""
from __future__ import annotations

import os
import re
import time
import uuid
from dataclasses import dataclass, field

STARTUP_ACTIVITY_SECONDS = float(os.environ.get('MIKA_STARTUP_ACTIVITY_SECONDS', 20))
IDLE_WATCHDOG_SECONDS = float(os.environ.get('MIKA_IDLE_WATCHDOG_SECONDS', 75))
STREAM_GAP_SECONDS = float(os.environ.get('MIKA_STREAM_GAP_SECONDS', 1200))
DAYPARTS = ('MORNING', 'AFTERNOON', 'EVENING', 'LATE_NIGHT')


@dataclass(frozen=True)
class GoalSpec:
    id: str
    title: str                      # how Mika would describe the plan
    steps: tuple                    # semantic actions, executed in order
    reasons: dict                   # mood -> her own reason
    segment: str = 'PHONE_VLOG'     # topic segment while pursuing it
    dwell: tuple = (0, 0)           # seconds to stay after the main steps
    after: tuple = ()               # steps after dwelling (e.g. walk home)
    quiet: bool = False             # intentional low-speech activity
    lively: bool = False            # visibly active; answers "boring"
    weight: float = 1.0
    daypart: dict = field(default_factory=dict)
    cooldown: float = 900
    scenes: tuple = ('HOME',)
    zone: str = 'HOME'              # where the goal takes her


GOALS = {g.id: g for g in [
    GoalSpec('fresh_air', 'head outside and show you the garden', ('visit_gardens',),
             {'boredom': "I've been standing in one spot way too long", 'curiosity': 'I want to see what the garden looks like right now',
              'energy': 'I have too much energy for this room'}, dwell=(25, 50), lively=True, zone='GROUNDS',
             daypart={'LATE_NIGHT': .9}),
    GoalSpec('stargaze', 'go outside and quietly watch the night sky for a while', ('quiet_outside',),
             {'desireForQuiet': 'it is quiet enough out there to just look up for a bit', 'curiosity': 'I want to check whether the stars are out',
              'boredom': 'staring at my walls is losing to staring at the sky'}, dwell=(150, 260), quiet=True, zone='GROUNDS',
             daypart={'MORNING': .02, 'AFTERNOON': .02, 'EVENING': 1.2, 'LATE_NIGHT': 2.2}, cooldown=1800),
    GoalSpec('lantern_walk', 'walk down to the lantern pavilion by the water', ('visit_lantern_retreat',),
             {'curiosity': 'the lanterns by the pond are the prettiest thing out there', 'boredom': 'I need a change of scenery',
              'desireForQuiet': 'the pavilion is my favourite calm corner'}, dwell=(40, 90), lively=True, zone='GROUNDS',
             daypart={'EVENING': 1.4, 'LATE_NIGHT': 1.3}),
    GoalSpec('garden_jog', 'change and go for a jog around the garden loop', ('go_jogging',),
             {'energy': 'I want to burn off some energy', 'restlessness': 'my legs want to move', 'boredom': 'sitting still is getting old'},
             segment='PHONE_VLOG', lively=True, weight=.9, zone='GROUNDS', daypart={'MORNING': 2.0, 'AFTERNOON': 1.2, 'EVENING': 1.0, 'LATE_NIGHT': .25},
             cooldown=2400),
    GoalSpec('explore', 'wander to a corner of the garden I have not visited lately', ('explore',),
             {'curiosity': 'there is a corner of the garden I have not looked at in a while', 'boredom': 'I want somewhere new to stand',
              'restlessness': 'a slow wander sounds good right now'}, dwell=(20, 50), lively=True, zone='GROUNDS',
             daypart={'MORNING': 1.2, 'AFTERNOON': 1.2, 'EVENING': 1.0, 'LATE_NIGHT': .4}, cooldown=1200),
    GoalSpec('flower', 'pick one flower from the garden beds and show it to you', ('pick_flower',),
             {'curiosity': 'one of the flowers along the path caught my eye', 'playfulness': 'I want to show you one up close',
              'satisfaction': 'a small garden moment sounds nice'}, dwell=(10, 25), after=('place_flower',), zone='GROUNDS',
             daypart={'MORNING': 1.3, 'AFTERNOON': 1.1, 'EVENING': .6, 'LATE_NIGHT': .1}, cooldown=2400),
    GoalSpec('atelier', 'go and look over my paintings', ('visit_atelier',),
             {'curiosity': 'I want to see my half-finished canvas in this light', 'desireForQuiet': 'the art studio is the calmest place to think',
              'playfulness': 'I want to show you my gallery wall'}, dwell=(45, 110), zone='GROUNDS',
             daypart={'MORNING': 1.3, 'AFTERNOON': 1.2, 'EVENING': .7, 'LATE_NIGHT': .2}, cooldown=2400),
    GoalSpec('relax', 'sit down in my reading chair and unwind for a while', ('sit_chair',),
             {'desireForQuiet': 'I want a calm moment in my chair', 'satisfaction': 'a slow, quiet break sounds right',
              'curiosity': 'I want to just sit and watch the light in my room for a bit'}, segment='READING', dwell=(90, 200), quiet=True,
             daypart={'LATE_NIGHT': 1.6, 'EVENING': 1.3}, cooldown=1500),
    GoalSpec('read', 'take a book from my shelf and read in the reading chair', ('read_book',),
             {'desireForQuiet': 'I want a calm stretch with a book', 'curiosity': 'I want to get back to the book I left open',
              'satisfaction': 'a slow reading break sounds right'}, segment='READING', dwell=(180, 320), quiet=True, after=('return_book',),
             daypart={'LATE_NIGHT': 1.8, 'EVENING': 1.3}, cooldown=1500),
    GoalSpec('dance_practice', 'dance a few routines with Luna', ('dance_session',),
             {'energy': 'I want to practise that routine properly', 'playfulness': 'I feel like dancing badly on purpose, then well',
              'restlessness': 'dancing is the fastest cure for being restless'}, segment='SHOW_AND_TELL', lively=True, zone='STUDIO',
             daypart={'AFTERNOON': 1.4, 'EVENING': 1.3, 'LATE_NIGHT': .35}, cooldown=2400),
    GoalSpec('rhythm_challenge', 'try to beat my best rhythm score', ('dance_challenge',),
             {'playfulness': 'my last score is bugging me', 'energy': 'I want a proper challenge'}, segment='SHOW_AND_TELL', lively=True, zone='ARCADE',
             weight=.7, daypart={'LATE_NIGHT': .3}, cooldown=2700),
    GoalSpec('room_tour', 'show you around my room properly', ('tour_room',),
             {'curiosity': 'some of you have never seen the whole room', 'playfulness': 'I want to show off my corners'},
             segment='ROOM_LIFE', lively=True, weight=.6, cooldown=2400),
    GoalSpec('window', 'look out of the window for a minute', ('show_window',),
             {'curiosity': 'I want to check the view outside', 'desireForQuiet': 'the garden view from my window is calming'},
             segment='THOUGHT_OF_THE_DAY', dwell=(15, 35), weight=.7, cooldown=1200),
    GoalSpec('desk', 'show you what is on my desk monitor', ('show_desk',),
             {'curiosity': 'I want to show you what is on my screen', 'playfulness': 'my monitor has been doing its own thing'},
             segment='DESK_TALK', weight=.5, cooldown=1800),
    GoalSpec('magic_training', 'go to my magic sanctuary and practise my next spell lesson', ('magic_lesson',),
             {'curiosity': 'I want to see if I can finally get the next spell right', 'playfulness': 'magic practice is way more fun than it should be',
              'energy': 'I feel like I could actually pull off a spell today', 'boredom': 'time to make some sparks happen'},
             segment='SHOW_AND_TELL', lively=True, zone='SANCTUARY', weight=1.3, cooldown=1800),
    GoalSpec('garden_bench', 'sit on a garden bench for a bit', ('sit_bench',),
             {'desireForQuiet': 'my legs want a break on a bench', 'satisfaction': 'a bench in the garden sounds right',
              'curiosity': 'I want to just watch the garden for a minute'}, dwell=(40, 90), quiet=True, zone='GROUNDS',
             daypart={'LATE_NIGHT': .4}, cooldown=1500),
    GoalSpec('coding_session', 'sit at my desk and code something small', ('coding_session',),
             {'curiosity': 'I have a little coding idea I want to try', 'playfulness': 'I want to break some code on purpose and fix it',
              'energy': 'my brain wants a puzzle'}, segment='DESK_TALK', weight=.8, cooldown=2400),
    GoalSpec('head_home', 'head back inside', ('return_home',),
             {'satisfaction': 'that was enough of being away', 'desireForQuiet': 'I want to be back home'},
             weight=.1, scenes=('GROUNDS', 'STUDIO', 'ARCADE', 'DANCE_HALL'), cooldown=60),
]}

BORED_RE = re.compile(r"\b(boring|bored|so dull|lame|snooze|z{3,}|nothing (?:is )?happening|do something|wake (?:me|us) up)\b", re.I)
ROUTE_FAILURE_RE = re.compile(r'route|blocked|unreachable|inside furniture|navigation|door_contact|passage_not_clear', re.I)
NOT_BORED_RE = re.compile(r"\b(?:not|isn'?t|never)\s+(?:\w+\s+)?boring\b", re.I)


def is_boredom_feedback(text: str) -> bool:
    return bool(BORED_RE.search(text or '')) and not NOT_BORED_RE.search(text or '')


class Autonomy:
    def __init__(self, clock=time.time, rng=None):
        import random
        self.clock = clock
        self.rng = rng or random.Random()
        self.goal = None                 # active GoalRun dict
        self.history = []                # finished goal runs (bounded)
        self.cooldowns = {}
        self.consecutive_failures = 0
        self.last_decision = None
        self.last_progress_at = clock()
        self.last_success = None
        self.blocking_reason = None
        self.next_decision_at = clock() + STARTUP_ACTIVITY_SECONDS
        self.forced = None               # GoalSpec chosen by a viewer reaction
        self.yield_requested = None      # reason a running goal should stop at a safe boundary
        self.stream = {'id': None, 'startedAt': None, 'greeted': False, 'kind': None}
        self.resumable = None            # unfinished goal from a restart
        self.unreachable = {}            # zone -> until (route/door failures)
        from .activity_registry import ActivityPool
        self.pool = ActivityPool(clock, path=None)  # five-hour objective pool (persisted by the show)

    # --- stream identity ---------------------------------------------------
    def begin_stream(self, saved_stream, saved_at):
        """New stream unless the previous one was alive within the gap."""
        now = self.clock()
        if saved_stream and saved_stream.get('id') and saved_at and now - saved_at < STREAM_GAP_SECONDS:
            self.stream = {**saved_stream, 'kind': 'reconnection'}
        else:
            self.stream = {'id': uuid.uuid4().hex[:12], 'startedAt': now, 'greeted': False, 'kind': 'new_stream'}
        return self.stream['kind']

    # --- selection ---------------------------------------------------------
    def candidates(self, reality, *, lively_only=False, exclude=(), ignore_cooldown=False, revisit=False, revisit_gap=3):
        """Eligible registry activities in the open five-hour pool, scored.

        She plans from where she is: an activity in another place is eligible
        when its capability is implemented (the travel is part of the plan);
        a bedroom-only activity gets a trip into the house only when she is
        away. Nothing sends her home between activities."""
        from .activity_registry import REGISTRY, implemented
        now = self.clock()
        scene = reality.get('scene') or 'HOME'
        part = reality.get('dayPart') or 'AFTERNOON'
        moods = reality.get('vlogger', {}).get('moods', {}) or {}
        energy, boredom = moods.get('energy', .6), moods.get('boredom', .2)
        quiet_wish, restless = moods.get('desireForQuiet', .4), moods.get('restlessness', .2)
        recent = [g['id'] for g in self.history[-3:]]
        self.pool.ensure_cycle(reality)
        open_ids = set(self.pool.remaining())
        rows = []
        for spec in GOALS.values():
            act = REGISTRY.get(spec.id)
            if not act or not act.objective or not act.enabled():
                continue
            if spec.id not in open_ids and not (revisit and spec.id not in recent[len(recent) - revisit_gap:]):
                continue
            if spec.id in exclude or (not ignore_cooldown and now < self.cooldowns.get(spec.id, 0)):
                continue
            if self.unreachable.get(spec.zone, 0) > now:
                continue
            if not all(implemented(reality, r) for r in act.requires):
                continue
            if act.home_only and scene != 'HOME' and not implemented(reality, 'return_home'):
                continue
            if lively_only and not spec.lively:
                continue
            score = spec.weight * spec.daypart.get(part, 1.0)
            if spec.quiet:
                score *= (.5 + quiet_wish) * (1.3 - .6 * energy)
            if spec.lively:
                score *= (.5 + energy) * (.6 + boredom + restless)
            if act.home_only and scene != 'HOME':
                score *= .7  # slightly prefer what is near her
            if recent and spec.id == recent[-1]:
                score *= .05
            elif spec.id in recent:
                score *= .35
            if revisit:
                # Done this cycle already: the longer ago, the more it appeals again.
                last = max((h.get('at') or 0 for h in self.pool.recent(200) if h.get('id') == spec.id), default=0)
                score *= min(1.0, .25 + (now - last) / 3600) if last else 1.0
            rows.append((spec, round(score, 4)))
        return rows

    def choose(self, reality, *, lively_only=False, exclude=(), source='autonomous'):
        rows = [(s, w) for s, w in self.candidates(reality, lively_only=lively_only, exclude=exclude) if w > 0]
        relaxed = False
        if not rows and not self.pool.exhausted():
            # Everything in the open pool is resting: an open objective that is
            # cooling down is still better than standing still.
            last = self.history[-1]['id'] if self.history else None
            rows = [(s, w) for s, w in self.candidates(reality, lively_only=lively_only, exclude=tuple(exclude) + ((last,) if last else ()), ignore_cooldown=True) if w > 0]
            relaxed = bool(rows)
        self.last_decision = {'at': self.clock(), 'source': source, 'candidates': {s.id: w for s, w in rows}, 'chosen': None, 'cooldownsRelaxed': relaxed}
        if not rows and self.pool.exhausted():
            # Every objective of this five-hour cycle is done. Standing still
            # for hours is worse than doing something again, so she revisits the
            # activities she did longest ago (never her last three, cooldowns
            # kept). The cycle itself is not reset early.
            rows = [(s, w) for s, w in self.candidates(reality, lively_only=lively_only, exclude=exclude, revisit=True) if w > 0]
            if not rows:
                rows = [(s, w) for s, w in self.candidates(reality, lively_only=lively_only, exclude=exclude, revisit=True, ignore_cooldown=True) if w > 0]
            if not rows:
                # the Godot world may offer only two or three objectives here: anything but the very last one
                rows = [(s, w) for s, w in self.candidates(reality, lively_only=lively_only, exclude=exclude, revisit=True, ignore_cooldown=True, revisit_gap=1) if w > 0]
            relaxed = bool(rows)
            self.last_decision['candidates'] = {s.id: w for s, w in rows}
            self.last_decision['revisit'] = bool(rows)
        if not rows and not self.pool.exhausted():
            # Everything still open in this cycle is something this world cannot do (the Godot world implements only
            # a few of the registry's objectives): treat it like an exhausted cycle and revisit what she CAN do here,
            # done longest ago. Before this she stood blocked for the rest of the five-hour cycle (2026-10-18 live:
            # 86 blocks in 40 minutes, filling the time with the same few remarks).
            rows = [(s, w) for s, w in self.candidates(reality, lively_only=lively_only, exclude=exclude, revisit=True) if w > 0]
            if not rows:
                rows = [(s, w) for s, w in self.candidates(reality, lively_only=lively_only, exclude=exclude, revisit=True, ignore_cooldown=True) if w > 0]
            if not rows:
                # only a few things are possible here: anything but the very last one
                rows = [(s, w) for s, w in self.candidates(reality, lively_only=lively_only, exclude=exclude, revisit=True, ignore_cooldown=True, revisit_gap=1) if w > 0]
            if rows:
                self.last_decision['candidates'] = {s.id: w for s, w in rows}
                self.last_decision['revisit'] = True
                self.last_decision['cooldownsRelaxed'] = True
        if not rows:
            self.blocking_reason = 'activity_pool_exhausted' if self.pool.exhausted() else 'no_executable_goal_in_scene'
            self.next_decision_at = self.clock() + (300 if self.pool.exhausted() else 30)
            return None
        spec = self.rng.choices([s for s, _ in rows], weights=[w for _, w in rows], k=1)[0]
        self.last_decision['chosen'] = spec.id
        self.blocking_reason = None
        return spec

    def motivation(self, spec, reality):
        moods = reality.get('vlogger', {}).get('moods', {}) or {}
        ranked = sorted(spec.reasons, key=lambda k: moods.get(k, .4), reverse=True)
        return spec.reasons[ranked[0]] if ranked else ''

    # --- run lifecycle -------------------------------------------------------
    def start(self, spec, reality, source='autonomous', step_index=0):
        from .activity_registry import REGISTRY
        lo, hi = spec.dwell
        act = REGISTRY.get(spec.id)
        travel = [('act', 'return_home')] if act and act.home_only and (reality.get('scene') or 'HOME') != 'HOME' else []
        plan = travel + [('act', a) for a in spec.steps]
        if hi:
            plan.append(('dwell', round(self.rng.uniform(lo, hi))))
        plan += [('act', a) for a in spec.after]
        self.goal = {'id': spec.id, 'title': spec.title, 'motivation': self.motivation(spec, reality), 'source': source,
                     'plan': plan, 'stepIndex': step_index, 'status': 'announcing', 'quiet': spec.quiet, 'lively': spec.lively,
                     'startedAt': self.clock(), 'stepStartedAt': self.clock(), 'dwellUntil': None, 'segment': spec.segment, 'result': None}
        self.cooldowns[spec.id] = self.clock() + spec.cooldown
        self.yield_requested = None
        self.progress()
        return self.goal

    def progress(self):
        self.last_progress_at = self.clock()

    def step_done(self, action):
        self.last_success = {'action': action, 'at': self.clock()}
        self.consecutive_failures = 0
        self.progress()

    def finish(self, status, reason=None):
        goal = self.goal
        if not goal:
            return None
        goal['status'] = status
        goal['result'] = reason or status
        goal['endedAt'] = self.clock()
        self.history.append({k: goal[k] for k in ('id', 'title', 'status', 'result', 'startedAt', 'endedAt', 'source')})
        if status == 'completed':
            self.pool.complete(goal['id'], str(reason or ''))
        elif status == 'failed':
            self.pool.fail(goal['id'], str(reason or ''))
        self.history = self.history[-20:]
        if status == 'failed':
            self.consecutive_failures += 1
            # Bounded retry: a failing goal rests longer each time.
            self.cooldowns[goal['id']] = self.clock() + 900 * min(4, self.consecutive_failures)
            zone = GOALS[goal['id']].zone
            if zone != 'HOME' and ROUTE_FAILURE_RE.search(reason or ''):
                # The place itself is unreachable: rest every goal that needs it.
                self.unreachable[zone] = self.clock() + 900
                for spec in GOALS.values():
                    if spec.zone == zone:
                        self.cooldowns[spec.id] = max(self.cooldowns.get(spec.id, 0), self.clock() + 900)
        self.goal = None
        self.yield_requested = None
        self.progress()
        return goal

    def linger_seconds(self, reality):
        moods = reality.get('vlogger', {}).get('moods', {}) or {}
        if self.consecutive_failures >= 3:
            return 90  # stop hammering a broken world; still observable
        # No trip home between activities any more: she picks the next one soon.
        base = self.rng.uniform(8, 20) * (1.3 - moods.get('boredom', .2))
        return max(6, base)

    # --- diagnostics / persistence ------------------------------------------
    def snapshot(self, reality=None):
        now = self.clock()
        goal = dict(self.goal) if self.goal else None
        if goal:
            index = goal['stepIndex']
            goal['currentStep'] = goal['plan'][index] if index < len(goal['plan']) else None
            goal['plan'] = [f'{k}:{v}' for k, v in goal['plan']]
            goal['elapsedSeconds'] = round(now - goal['startedAt'])
            if goal.get('dwellUntil'):
                goal['dwellRemainingSeconds'] = round(max(0, goal['dwellUntil'] - now))
        return {'stream': self.stream, 'goal': goal, 'lastSuccessfulAction': self.last_success,
                'lastDecision': self.last_decision, 'secondsSinceProgress': round(now - self.last_progress_at),
                'blockingReason': self.blocking_reason, 'nextDecisionSeconds': round(max(0, self.next_decision_at - now)),
                'consecutiveFailures': self.consecutive_failures, 'yieldRequested': self.yield_requested,
                'recentGoals': self.history[-6:], 'resumable': self.resumable,
                'unreachableZones': {z: round(t - now) for z, t in self.unreachable.items() if t > now},
                'activityPool': self.pool.snapshot()}

    def to_checkpoint(self):
        goal = None
        if self.goal and self.goal['status'] not in ('completed', 'failed'):
            goal = {'id': self.goal['id'], 'stepIndex': int(self.goal['stepIndex']), 'source': self.goal['source'][:24]}
        return {'stream': {k: self.stream.get(k) for k in ('id', 'startedAt', 'greeted')}, 'goal': goal,
                'cooldowns': {k: v for k, v in self.cooldowns.items() if k in GOALS and v > self.clock()},
                'history': [{k: h[k] for k in ('id', 'status', 'endedAt')} for h in self.history[-8:]]}

    def restore(self, data):
        if not isinstance(data, dict):
            return
        goal = data.get('goal')
        if isinstance(goal, dict) and goal.get('id') in GOALS and isinstance(goal.get('stepIndex'), int):
            self.resumable = {'id': goal['id'], 'stepIndex': goal['stepIndex']}
        for key, value in (data.get('cooldowns') or {}).items():
            if key in GOALS and isinstance(value, (int, float)) and self.clock() < value < self.clock() + 7200:
                self.cooldowns[key] = value
        for row in (data.get('history') or [])[-8:]:
            if isinstance(row, dict) and row.get('id') in GOALS:
                self.history.append({'id': row['id'], 'title': GOALS[row['id']].title, 'status': str(row.get('status'))[:20],
                                     'result': 'restored', 'startedAt': None, 'endedAt': row.get('endedAt'), 'source': 'restored'})
