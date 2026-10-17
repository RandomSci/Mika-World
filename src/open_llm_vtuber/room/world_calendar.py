"""One injected epoch clock, zoned civil dates, and small local event records.

No holiday feed, invented schedule, viewer data, or in-flight physical state.
Events are explicit one-off appointments; reuse requires a new eventId.
"""
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo
import json
import math
import os
import re
import time

ROOT = Path(__file__).resolve().parents[3]
TERMINAL = {'completed', 'canceled', 'ended'}
WEEKLY = (
    ('planning and creative work', {'show_desk': 1.7, 'read_book': 1.2}),
    ('hobbies and exercise', {'go_jogging': 1.4, 'read_book': 1.2}),
    ('projects and practice', {'show_desk': 1.5, 'dance': 1.2}),
    ('regular hobbies', {'read_book': 1.4, 'show_desk': 1.2}),
    ('a practice or entertainment break', {'dance': 1.7, 'dance_challenge': 1.5}),
    ('exploration and longer activities', {'go_jogging': 1.6, 'tour_room': 1.4}),
    ('relaxation and reflection', {'read_book': 1.8, 'show_window': 1.5}),
)


def zoned_datetime(value, zone):
    """Require an offset for ambiguous/nonexistent wall times (DST locales)."""
    result = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if result.tzinfo is None:
        a, b = result.replace(tzinfo=zone, fold=0), result.replace(tzinfo=zone, fold=1)
        if a.utcoffset() != b.utcoffset() or a.astimezone(timezone.utc).astimezone(zone).replace(tzinfo=None) != result:
            raise ValueError('ambiguous_or_nonexistent_event_time: supply an explicit UTC offset')
        result = a
    return result.astimezone(zone)


DEFAULT_ZONE = 'America/New_York'


def sun_times(local, latitude, longitude):
    """Approximate local sunrise/sunset hours (NOAA-style; a few minutes'
    accuracy) for the local date, including its UTC offset (so DST)."""
    n = local.timetuple().tm_yday
    decl = math.radians(23.44) * math.sin(2 * math.pi * (284 + n) / 365)
    lat = math.radians(latitude)
    cos_h = (math.sin(math.radians(-0.833)) - math.sin(lat) * math.sin(decl)) / (math.cos(lat) * math.cos(decl))
    half = math.degrees(math.acos(max(-1.0, min(1.0, cos_h)))) / 15
    b = 2 * math.pi * (n - 81) / 364
    eot = 9.87 * math.sin(2 * b) - 7.53 * math.cos(b) - 1.5 * math.sin(b)
    offset = local.utcoffset().total_seconds() / 3600
    noon = 12 - longitude / 15 + offset - eot / 60
    return noon - half, noon + half


def sky_state(hour, sunrise, sunset):
    """DAY between sunrise and sunset, DUSK for the twilight either side."""
    if sunrise + .25 <= hour < sunset - .5: return 'DAY'
    if sunset - .5 <= hour < sunset + .75 or sunrise - .5 <= hour < sunrise + .25: return 'DUSK'
    return 'NIGHT'


class WorldCalendar:
    def __init__(self, clock=time.time, config_path=None):
        self.clock = clock
        self.validation_errors = []
        try:
            config = json.loads(Path(config_path or ROOT / 'room/calendar.json').read_text())
            if not isinstance(config,dict) or not isinstance(config.get('events',[]),list): raise ValueError('invalid_calendar_config')
            # Mika's fictional home is New York; MIKA_TIMEZONE overrides for DEV.
            self.zone = ZoneInfo(os.environ.get('MIKA_TIMEZONE') or config.get('timezone', DEFAULT_ZONE))
        except (OSError,ValueError,TypeError,KeyError) as exc:
            config={};self.zone=ZoneInfo(DEFAULT_ZONE);self.validation_errors.append('calendar_config_fallback: '+str(exc)[:120])
        self.regional_context = str(config.get('regionalContext', 'New York, USA; temperate four-season regional context, not live weather'))[:160]
        loc = config.get('location') or {}
        self.latitude, self.longitude = float(loc.get('latitude', 40.71)), float(loc.get('longitude', -74.01))
        zone_city = self.zone.key.split('/')[-1].replace('_', ' ')
        self.city = (zone_city if os.environ.get('MIKA_TIMEZONE') else str(loc.get('name') or zone_city))[:40]
        self.events = {}
        for source in config.get('events', [])[:64]:
            try:
                event = self.validate_event(source)
                if event['eventId'] in self.events:
                    raise ValueError('duplicate_eventId')
                self.events[event['eventId']] = event
            except (ValueError, TypeError, KeyError) as exc:
                self.validation_errors.append(str(exc)[:160])
        self.records = {}; self.history = []; self.daily_history = {}; self.rollovers = []; self.path = None
        self.last_date = None; self.dirty = False; self.last_error = None

    def validate_event(self, source):
        event = dict(source)
        if not re.fullmatch(r'[a-zA-Z0-9_-]{1,80}', event['eventId']):
            raise ValueError('invalid_eventId')
        zone = ZoneInfo(event.get('timezone', self.zone.key))
        start = zoned_datetime(event['startDateTime'], zone)
        end = zoned_datetime(event['endDateTime'], zone)
        if end <= start: raise ValueError('event_end_must_follow_start')
        for key, default in [('priority', 1), ('preparationWindow', 0), ('cooldown', 86400)]:
            value = float(event.get(key, default))
            if not math.isfinite(value) or value < 0: raise ValueError('invalid_' + key)
            event[key] = min(value, 366 * 86400)
        for key in ('activities', 'environmentChanges', 'completionConditions'):
            value = event.get(key, [])
            if not isinstance(value, list) or any(not isinstance(v, str) or len(v) > 100 for v in value):
                raise ValueError('invalid_' + key)
            event[key] = value[:12]
        event.update(title=str(event.get('title', event['eventId']))[:140],
                     category=str(event.get('category', 'fictional'))[:40], timezone=zone.key,
                     startDateTime=start.isoformat(), endDateTime=end.isoformat(),
                     outfitPreference=event.get('outfitPreference'), start=start.timestamp(), end=end.timestamp())
        return event

    def enable_persistence(self, path):
        self.path = Path(path)
        if self.path.exists():
            try:
                if self.path.stat().st_size > 100000: raise ValueError('calendar_checkpoint_too_large')
                data = json.loads(self.path.read_text())
                if data.get('version') != 1: raise ValueError('unsupported_calendar_checkpoint')
                records = data.get('records', {})
                if not isinstance(records, dict) or len(records) > 128: raise ValueError('invalid_records')
                for ident, row in records.items():
                    if not re.fullmatch(r'[a-zA-Z0-9_-]{1,80}', ident) or not isinstance(row, dict): raise ValueError('invalid_record')
                    if row.get('status') not in {'created','upcoming','in_progress','postponed',*TERMINAL}: raise ValueError('invalid_status')
                    for key in ('createdAt','updatedAt','completedAt','canceledAt','postponedAt','startOverride','endOverride'):
                        if key in row and (not isinstance(row[key], (int,float)) or not math.isfinite(row[key])): raise ValueError('invalid_timestamp')
                    done = row.get('actionsDone', [])
                    if not isinstance(done, list) or any(not isinstance(a,str) or len(a)>100 for a in done): raise ValueError('invalid_actionsDone')
                    row['actionsDone']=done[:12]
                    if 'startOverride' in row and row.get('endOverride',0)<=row['startOverride']: raise ValueError('invalid_postponement')
                history = data.get('history', [])[-96:]
                if not isinstance(history,list) or any(not isinstance(r,dict) or not isinstance(r.get('action'),str) or len(r['action'])>100 or not isinstance(r.get('at'),(float,int)) or not math.isfinite(r['at']) for r in history): raise ValueError('invalid_activity_history')
                daily=data.get('dailyHistory',{})
                if not isinstance(daily,dict) or len(daily)>31: raise ValueError('invalid_daily_history')
                for day,actions in daily.items():
                    datetime.fromisoformat(day)
                    if not isinstance(actions,dict) or len(actions)>64: raise ValueError('invalid_daily_actions')
                    for action,row in actions.items():
                        if not isinstance(action,str) or len(action)>100 or not isinstance(row,dict) or not isinstance(row.get('count'),int) or row['count']<1 or not isinstance(row.get('lastAt'),(int,float)) or not math.isfinite(row['lastAt']): raise ValueError('invalid_daily_action')
                if 'dailyHistory' not in data:
                    for row in history:
                        day=datetime.fromtimestamp(row['at'],self.zone).date().isoformat()
                        item=daily.setdefault(day,{}).setdefault(row['action'],{'count':0,'lastAt':row['at']})
                        item['count']+=1;item['lastAt']=max(item['lastAt'],row['at'])
                    daily={d:daily[d] for d in sorted(daily)[-31:]};self.dirty=True
                self.records = records; self.history = history; self.daily_history=daily
                self.last_date = data.get('lastDate') if re.fullmatch(r'\d{4}-\d{2}-\d{2}', str(data.get('lastDate'))) else None
                self.rollovers = [d for d in data.get('rollovers', [])[-30:] if re.fullmatch(r'\d{4}-\d{2}-\d{2}', str(d))]
            except (OSError, ValueError, TypeError, KeyError) as exc:
                self.last_error = 'calendar_restore_failed: ' + str(exc)[:160]
        self.tick()

    def save(self):
        if not self.path or not self.dirty: return
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix('.tmp')
            tmp.write_text(json.dumps({'version':1,'records':self.records,'history':self.history[-96:],'dailyHistory':self.daily_history,
                                      'lastDate':self.last_date,'rollovers':self.rollovers[-30:]}))
            tmp.replace(self.path); self.dirty = False
        except OSError as exc:
            self.last_error = 'calendar_save_failed: ' + str(exc)[:160]

    def bounds(self, event):
        row = self.records.get(event['eventId'], {})
        return row.get('startOverride', event['start']), row.get('endOverride', event['end'])

    def tick(self, now=None):
        now = self.clock() if now is None else now; today = datetime.fromtimestamp(now, self.zone).date().isoformat()
        if today != self.last_date:
            # A rollover is observed once. It never resets story or physics.
            if today not in self.rollovers: self.rollovers = (self.rollovers + [today])[-30:]
            self.last_date = today; self.dirty = True
        for ident, event in self.events.items():
            row = self.records.setdefault(ident, {'status':'created','createdAt':now,'updatedAt':now,'actionsDone':[]})
            if row['status'] in TERMINAL: continue
            start, end = self.bounds(event)
            status = 'ended' if now >= end else 'in_progress' if now >= start else 'postponed' if 'postponedAt' in row else 'upcoming'
            if row['status'] != status:
                row.update(status=status, updatedAt=now); self.dirty = True
        self.save()

    def set_status(self, ident, status, *, start=None, end=None):
        """Local administration; not an LLM raw state-writing capability."""
        self.tick()
        if ident not in self.events: raise ValueError('unknown_event')
        row = self.records[ident]
        if row['status'] in TERMINAL: raise ValueError('terminal_event_requires_new_id')
        if status not in ('completed','canceled','postponed'): raise ValueError('invalid_event_transition')
        if status == 'postponed':
            zone = ZoneInfo(self.events[ident]['timezone'])
            a,b = zoned_datetime(start,zone).timestamp(),zoned_datetime(end,zone).timestamp()
            if b<=a or a<=self.clock(): raise ValueError('invalid_postponement')
            row.update(startOverride=a,endOverride=b)
        row.update(status=status,updatedAt=self.clock(),**{status+'At':self.clock()})
        self.dirty = True; self.save()

    def confirmed_action(self, action, completed=True):
        if not completed: return
        self.tick(); now = self.clock()
        # Only acknowledged runtime actions enter history; no viewer names/text.
        if self.history and self.history[-1] == {'action':action,'at':now}: return
        self.history = (self.history + [{'action':action,'at':now}])[-96:]; self.dirty = True
        date=datetime.fromtimestamp(now,self.zone).date().isoformat()
        daily=self.daily_history.setdefault(date,{})
        row=daily.setdefault(action,{'count':0,'lastAt':now});row.update(count=row['count']+1,lastAt=now)
        self.daily_history={d:self.daily_history[d] for d in sorted(self.daily_history)[-31:]}
        for ident,event in self.events.items():
            row = self.records[ident]
            if row['status']!='in_progress' or action not in event['activities']: continue
            row['actionsDone'] = list(dict.fromkeys(row['actionsDone'] + [action]))[-12:]
            required = event['completionConditions']
            if required and set(required).issubset(row['actionsDone']):
                row.update(status='completed',completedAt=now,updatedAt=now)
        self.save()

    def public_event(self, event):
        row = self.records[event['eventId']]; start,end = self.bounds(event)
        result = {k:v for k,v in event.items() if k not in ('start','end')}
        zone = ZoneInfo(event['timezone'])
        result.update(startDateTime=datetime.fromtimestamp(start,zone).isoformat(),
                      endDateTime=datetime.fromtimestamp(end,zone).isoformat(),status=row['status'],
                      actionsDone=row['actionsDone'])
        if 'completedAt' in row: result['completedAt']=datetime.fromtimestamp(row['completedAt'],self.zone).isoformat()
        return result

    def snapshot(self):
        now = self.clock(); self.tick(now); local = datetime.fromtimestamp(now,self.zone); hour=local.hour+local.minute/60
        sunrise, sunset = sun_times(local, self.latitude, self.longitude)
        daypart = 'MORNING' if 5<=hour<12 else 'AFTERNOON' if 12<=hour<17 else 'EVENING' if 17<=hour<22 else 'LATE_NIGHT'
        ordered = sorted(self.events.values(), key=lambda e:self.bounds(e)[0])
        public = [self.public_event(e) for e in ordered]
        preferences = dict(WEEKLY[local.weekday()][1])
        if daypart=='LATE_NIGHT': preferences.update(go_jogging=.2,dance=.2,dance_challenge=.2,read_book=2)
        return dict(clockEpochMs=round(now*1000),currentDate=local.date().isoformat(),date=local.date().isoformat(),
                    currentTime=local.strftime('%H:%M:%S'),localTime=local.strftime('%H:%M'),timezone=self.zone.key,
                    # Spoken/displayed form: 12-hour with AM/PM and the city, so
                    # "02:49" in New York is never read as 2:49 in the afternoon.
                    clock12=f"{local.hour % 12 or 12}:{local.minute:02d} {'AM' if local.hour < 12 else 'PM'}",city=self.city,
                    year=local.year,month=local.month,dayOfMonth=local.day,dayOfWeek=local.weekday(),weekdayName=local.strftime('%A'),
                    isWeekend=local.weekday()>=5,dayOfYear=local.timetuple().tm_yday,seasonOrRegionalContext=self.regional_context,
                    dayPart=daypart,sky=sky_state(hour,sunrise,sunset),hour=hour,sunrise=round(sunrise,3),sunset=round(sunset,3),
                    location={'latitude':self.latitude,'longitude':self.longitude},
                    weeklyRoutine={'style':WEEKLY[local.weekday()][0],'actionWeights':preferences,'policy':'preferences, not appointments'},
                    upcomingEvents=[e for e in public if e['status'] in ('upcoming','postponed')][:12],
                    activeEvents=[e for e in public if e['status']=='in_progress'][:12],
                    recentCompletedEvents=[e for e in public if e['status']=='completed'][-12:],
                    calendarDiagnostics={'errors':self.validation_errors,'lastError':self.last_error},
                    recentActivityDays=[{'date':date,'confirmedActions':list(actions),'counts':{a:r['count'] for a,r in actions.items()}} for date,actions in sorted(self.daily_history.items())[-7:]],
                    activityHistory=[{'action':h['action'],'at':datetime.fromtimestamp(h['at'],self.zone).isoformat()} for h in self.history[-12:]])

    def planned_action(self, available, cooldowns):
        self.tick(); now=self.clock()
        for event in sorted(self.events.values(),key=lambda e:-e['priority']):
            row=self.records[event['eventId']]; start,end=self.bounds(event)
            if row['status'] in TERMINAL or not start-event['preparationWindow']<=now<end: continue
            for action in event['activities']:
                if action in available and action not in row['actionsDone'] and now>=cooldowns.get(action,0) and now>=cooldowns.get('failed_'+action,0):
                    if any(h['action']==action and now-h['at']<event['cooldown'] for h in self.history): continue
                    return action
        return None

    def viewer_facts(self, text):
        """Ground date/schedule/history questions without invented appointments."""
        q=text.lower(); state=self.snapshot(); local=datetime.fromtimestamp(state['clockEpochMs']/1000,self.zone)
        if not re.search(r'\b(date|day|today|tomorrow|weekend|yesterday|month|year|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next.*performance)\b',q): return None
        if 'yesterday' in q:
            date=local.date()-timedelta(days=1)
            actions=list(self.daily_history.get(date.isoformat(),{}))
            return {'questionType':'history','date':date.isoformat(),'confirmedActions':actions,'missingHistory':'No retained confirmed activity record for that date.' if not actions else None}
        if any(word in q for word in ('tomorrow','weekend','next','performance')):
            upcoming=state['upcomingEvents']+state['activeEvents']
            if 'tomorrow' in q: start=local.date()+timedelta(days=1);end=start+timedelta(days=1)
            elif 'weekend' in q:
                start=local.date()+timedelta(days=(5-local.weekday())%7 if local.weekday()<6 else -1);end=start+timedelta(days=2)
            else:start=local.date();end=None
            events=[e for e in upcoming if (end is None or datetime.fromisoformat(e['startDateTime']).astimezone(self.zone).date()<end) and datetime.fromisoformat(e['endDateTime']).astimezone(self.zone).date()>=start and ('performance' not in q or e['category']=='performance')]
            return {'questionType':'schedule','windowStart':start.isoformat(),'windowEnd':end.isoformat() if end else None,'events':events,'noSchedule':not bool(events),'rule':'Weekday preferences and unfinished stories are not scheduled appointments.'}
        return {'questionType':'date','currentDate':state['currentDate'],'weekdayName':state['weekdayName'],'monthName':local.strftime('%B'),'year':local.year,'isWeekend':state['isWeekend'],'timezone':self.zone.key}

    def viewer_answer(self, text):
        """Small factual calendar answers, carried by the existing Ana pipeline.

        The LLM stays creative for conversation; appointments/history must not
        acquire fictional extra sentences. Only direct calendar inquiries match.
        """
        q=text.lower()
        if not re.search(r"\b(?:what(?:'s| is)? (?:date|day|month|year|are you doing|did you do|happening)|is (?:it|today) (?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|when.*next.*(?:dance )?performance)\b",q): return None
        facts=self.viewer_facts(text)
        if not facts:return None
        if facts['questionType']=='history':
            labels={'read_book':'reading with the book','dance':'a dance practice','dance_challenge':'a rhythm challenge','go_jogging':'a garden jog','show_desk':'a desk visit','tour_room':'a room tour','casual_phone_chat':'phone chat'}
            actions=[labels.get(a,a.replace('_',' ')) for a in facts['confirmedActions'][:3]]
            return "I don't have a confirmed activity record for yesterday, so I can't give you an honest recap." if not actions else 'My confirmed record for yesterday includes '+', '.join(actions)+'.'
        if facts['questionType']=='schedule':
            if facts['noSchedule']:
                return "I haven't scheduled my next dance performance yet." if 'performance' in q else "I don't have any appointments scheduled for "+('tomorrow' if 'tomorrow' in q else 'this weekend')+". I'll choose from my ongoing goals when the time comes."
            event=facts['events'][0];start=datetime.fromisoformat(event['startDateTime']).astimezone(self.zone)
            return f"My calendar lists {event['title']} on {start.strftime('%A, %B')} {start.day} at {start.strftime('%H:%M')}."
        if 'month' in q:return f"It's {facts['monthName']} {facts['year']}."
        if 'year' in q and 'day' not in q:return f"It's {facts['year']}."
        weekdays='monday tuesday wednesday thursday friday saturday sunday'.split()
        requested=next((d for d in weekdays if re.search(r'\b'+d+r'\b',q)),None)
        prefix=('Yes, ' if requested==facts['weekdayName'].lower() else 'No, ') if requested else ''
        date=datetime.fromisoformat(facts['currentDate'])
        return prefix+('it\'s ' if prefix else 'It\'s ')+f"{facts['weekdayName']}, {facts['monthName']} {date.day}, {facts['year']} here."
