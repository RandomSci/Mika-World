"""Capability-aware plans and fictional moods; no ownership of physical transforms."""
import json
import math
import os
from pathlib import Path
import random
import tempfile
import time


class TemporaryMemory:
    retention_seconds = 20 * 86400
    def __init__(self, path=None, clock=time.time):
        self.path = Path(path) if path else None
        self.clock = clock
        self.records = []
        self.error = None
        if self.path:
            try:
                if self.path.stat().st_size > 1024 * 1024:
                    raise ValueError('temporary_memory_too_large')
                data = json.loads(self.path.read_text())
                if data.get('version') != 1 or not isinstance(data.get('records'), list):
                    raise ValueError('invalid_temporary_memory_version')
                self.records = [r for r in data['records'] if isinstance(r, dict) and isinstance(r.get('at'), (int, float)) and math.isfinite(r['at']) and isinstance(r.get('kind'), str)]
            except FileNotFoundError:
                pass
            except (OSError, ValueError, TypeError) as exc:
                self.error = str(exc)
        self.prune()

    def prune(self):
        now = self.clock()
        self.records = [r for r in self.records if now - self.retention_seconds <= r['at'] <= now + 60][-2048:]

    def add(self, kind, **data):
        # No viewer identity, raw chat, physical transforms or credentials.
        allowed = {'action', 'scene', 'date', 'hour', 'theme', 'goal', 'result', 'topic'}
        self.records.append({'at': self.clock(), 'kind': kind, **{k: str(v)[:180] for k, v in data.items() if k in allowed}})
        self.prune()

    def save(self):
        self.prune()
        if not self.path:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=self.path.name + '.', suffix='.tmp', dir=self.path.parent)
        try:
            with os.fdopen(fd, 'w') as handle:
                json.dump({'version': 1, 'savedAt': self.clock(), 'records': self.records}, handle)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, self.path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


class VloggerDirector:
    micro_actions = frozenset({'presentation_beat','switch_selfie_profile','listen_to_viewer','flip_rear_camera','set_monitor'})
    def __init__(self, clock=time.time, rng=None):
        self.clock = clock
        self.rng = rng or random.Random()
        self.memory = TemporaryMemory(clock=clock)
        self.moods = dict(energy=.65, boredom=.1, curiosity=.6, playfulness=.35, inspiration=.55, restlessness=.2, socialEngagement=.5, desireForQuiet=.3, satisfaction=.5)
        self.hour_key = None
        self.day_key = None
        self.plan = None
        self.last_tick = clock()
        self.review_at = clock() + 240
        self.cooldowns = {}

    def enable_persistence(self, path):
        self.memory = TemporaryMemory(path, self.clock)
        self.memory.records = [r for r in self.memory.records if not (r['kind'] == 'activity_completed' and r.get('action') in self.micro_actions)]
        # Restore logical continuity only, never a pose, scene position or throw.
        recent = self.memory.records
        for row in recent:
            if row['kind'] == 'activity_completed':
                action = row.get('action')
                self.cooldowns[action] = max(self.cooldowns.get(action, 0), row['at'] + (1800 if action == 'garden_jog' else 900))
        plans = [r for r in recent if r['kind'] == 'hourly_plan']
        if plans:
            row=plans[-1]
            self.day_key=row.get('date')
            self.hour_key=(row.get('date'),row.get('hour'))
            self.theme=row.get('theme') or 'finish a small goal'
            self.plan = {'date':row.get('date'),'hour':row.get('hour'),'goal':row.get('goal'),'theme':self.theme,'status':'flexible_intention','allowsContinue':True,'reviewAfter':self.clock()+3600,'restored':True,'physicalRestore':'safe HOME'}

    def update(self, reality, viewer_active=False):
        now = self.clock()
        dt = max(0, min(60, now - self.last_tick))
        self.last_tick = now
        calendar_date = reality.get('currentDate')
        local_hour = str(reality.get('localTime', '00:00'))[:2]
        key = (calendar_date, local_hour)
        late = reality.get('dayPart') == 'LATE_NIGHT'
        quiet = reality.get('currentActivity') in ('quiet_waterfront', 'read_book', 'sit_read')
        self.moods['boredom'] = min(1, self.moods['boredom'] + dt / 1200)
        self.moods['restlessness'] = min(1, self.moods['restlessness'] + dt / 2400)
        self.moods['energy'] += ((.35 if late else .68) - self.moods['energy']) * min(1, dt / 1800)
        self.moods['desireForQuiet'] += ((.8 if late or quiet else .3) - self.moods['desireForQuiet']) * min(1, dt / 600)
        self.moods['socialEngagement'] += ((.8 if viewer_active else .35) - self.moods['socialEngagement']) * min(1, dt / 300)
        if key != self.hour_key:
            if calendar_date != self.day_key:
                self.day_key = calendar_date
                themes = ['make something worth keeping', 'explore familiar places slowly', 'practice and take real breaks', 'finish a small goal']
                self.theme = self.rng.choice(themes)
                self.memory.add('daily_intention', date=calendar_date, theme=self.theme)
            self.hour_key = key
            goals = ['quiet reading with a fresh-air break', 'a scenic garden visit', 'continue an unfinished story', 'a short practice session']
            goal = self.rng.choice(goals if not late else goals[:3])
            self.plan = {'date': calendar_date, 'hour': local_hour, 'theme': self.theme, 'goal': goal, 'status': 'flexible_intention', 'reviewAfter': now + 3600, 'allowsContinue': True}
            self.memory.add('hourly_plan', date=calendar_date, hour=local_hour, theme=self.theme, goal=goal)
        self.memory.prune()

    def propose(self, reality):
        now = self.clock()
        if now < self.review_at:
            return None
        self.review_at = now + self.rng.uniform(180, 300)
        available = set(reality.get('availableActions', []))
        scene = reality.get('scene')
        if scene == 'GROUNDS':
            candidates = ['return_home'] if self.moods['boredom'] > .55 else ['quiet_outside']
        else:
            candidates = ['quiet_outside', 'visit_lantern_retreat'] if reality.get('dayPart') == 'LATE_NIGHT' else ['visit_gardens', 'garden_jog', 'visit_lantern_retreat']
        candidates = [a for a in candidates if a in available and now >= self.cooldowns.get(a, 0)]
        if not candidates:
            return None
        chosen = self.rng.choice(candidates)
        # Retry backoff starts at proposal; a failure never spins forever.
        self.cooldowns[chosen] = now + 600
        return chosen

    def confirmed(self, action, scene):
        # A camera adjustment is not a meaningful new activity or progress on
        # the day. It must neither reset boredom nor flood twenty-day memory.
        if action in self.micro_actions:
            return
        self.memory.add('activity_completed', action=action, scene=scene, result='runtime_acknowledged')
        self.cooldowns[action] = self.clock() + (1800 if action == 'garden_jog' else 900)
        self.moods['boredom'] *= .35
        self.moods['restlessness'] *= .5
        self.moods['satisfaction'] = min(1, self.moods['satisfaction'] + .08)
        if self.plan:
            self.plan['lastConfirmedAction'] = action
        # An intention is not marked complete merely because some action ran.

    def snapshot(self):
        return {'hourlyPlan': self.plan, 'moods': {k: round(v, 3) for k, v in self.moods.items()}, 'nextReviewSeconds': round(max(0, self.review_at - self.clock())), 'temporaryMemoryDays': 20, 'recentConfirmedActivities': [r for r in self.memory.records if r['kind'] == 'activity_completed'][-8:], 'memoryError': self.memory.error}
