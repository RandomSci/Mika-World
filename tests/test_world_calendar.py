import json
import random
import sys
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
import pytest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from open_llm_vtuber.room.world_calendar import WorldCalendar
from open_llm_vtuber.room.lifestyle import LifestyleShowRunner
from open_llm_vtuber.room.viewer_intents import classify_viewer

def epoch(text): return datetime.fromisoformat(text).timestamp()
def setup(tmp_path, now='2026-10-09T10:00:00+08:00',events=(),zone='Asia/Manila'):
    config=tmp_path/'config.json';config.write_text(json.dumps({'timezone':zone,'events':events}))
    time=[epoch(now)];calendar=WorldCalendar(lambda:time[0],config)
    return calendar,time,config
def event(**changes):
    return dict(eventId='practice-2026-10-10',title='An explicitly scheduled rehearsal',
                startDateTime='2026-10-10T10:00:00+08:00',endDateTime='2026-10-10T11:00:00+08:00',
                timezone='Asia/Manila',category='performance',priority=2,preparationWindow=86400,
                activities=['dance'],environmentChanges=['festive'],outfitPreference='HOME',
                completionConditions=['dance'],cooldown=3600,**changes)

@pytest.mark.parametrize('before,after,date,weekday,dayyear',[
 ('2026-10-09T23:59:59+08:00','2026-10-10T00:00:00+08:00','2026-10-10','Saturday',283),
 ('2026-10-11T23:59:59+08:00','2026-10-12T00:00:00+08:00','2026-10-12','Monday',285),
 ('2026-10-31T23:59:59+08:00','2026-11-01T00:00:00+08:00','2026-11-01','Sunday',305),
 ('2026-12-31T23:59:59+08:00','2027-01-01T00:00:00+08:00','2027-01-01','Friday',1),
 ('2028-02-28T23:59:59+08:00','2028-02-29T00:00:00+08:00','2028-02-29','Tuesday',60),
 ('2028-02-29T23:59:59+08:00','2028-03-01T00:00:00+08:00','2028-03-01','Wednesday',61),
])
def test_zoned_rollovers_once_and_restart(tmp_path,before,after,date,weekday,dayyear):
    c,now,config=setup(tmp_path,before);store=tmp_path/'state.json';c.enable_persistence(store)
    now[0]=epoch(after);state=c.snapshot()
    assert (state['currentDate'],state['weekdayName'],state['dayOfYear'])==(date,weekday,dayyear)
    assert state['isWeekend']==(weekday in ('Saturday','Sunday'))
    for _ in range(10):c.snapshot()
    assert c.rollovers.count(date)==1
    restored=WorldCalendar(lambda:now[0],config);restored.enable_persistence(store)
    assert restored.snapshot()['currentDate']==date and restored.rollovers.count(date)==1

def test_canonical_injected_epoch_not_os_clock(tmp_path):
    c,now,_=setup(tmp_path,'2026-10-08T16:01:00+00:00')
    state=c.snapshot();assert state['currentDate']=='2026-10-09' and state['localTime']=='00:01'
    assert state['timezone']=='Asia/Manila' and state['dayPart']=='LATE_NIGHT' and state['sky']=='NIGHT'
    show=LifestyleShowRunner(SimpleNamespace(trace=lambda *a,**kw:None),clock=lambda:now[0]);show.calendar=c
    assert show.reality.snapshot(show)['currentDate']==state['currentDate']

def test_activation_completion_survives_story_expiry_and_no_replay(tmp_path):
    c,now,config=setup(tmp_path,events=[event()]);store=tmp_path/'state.json';c.enable_persistence(store)
    assert c.snapshot()['upcomingEvents'] and not c.snapshot()['activeEvents']
    assert c.planned_action(['dance'],{})=='dance'
    now[0]=epoch('2026-10-10T10:00:00+08:00');assert c.snapshot()['activeEvents'][0]['status']=='in_progress'
    c.confirmed_action('dance',completed=False);assert not c.snapshot()['recentCompletedEvents']
    c.confirmed_action('dance');assert c.snapshot()['recentCompletedEvents'][0]['actionsDone']==['dance']
    now[0]+=86400*40
    restored=WorldCalendar(lambda:now[0],config);restored.enable_persistence(store)
    assert restored.snapshot()['recentCompletedEvents'] and restored.planned_action(['dance'],{}) is None
    assert restored.viewer_facts('When is your next dance performance?')['noSchedule']
    assert 'viewer' not in store.read_text() and 'cameraTransform' not in store.read_text()

def test_cancel_postpone_and_end_without_fake_completion(tmp_path):
    c,now,_=setup(tmp_path,events=[event()]);c.set_status('practice-2026-10-10','postponed',start='2026-10-12T10:00:00+08:00',end='2026-10-12T11:00:00+08:00')
    assert c.snapshot()['upcomingEvents'][0]['startDateTime'].startswith('2026-10-12')
    assert c.snapshot()['upcomingEvents'][0]['status']=='postponed'
    now[0]=epoch('2026-10-12T10:00:00+08:00');assert c.snapshot()['activeEvents']
    c.set_status('practice-2026-10-10','canceled');assert not c.snapshot()['activeEvents']
    with pytest.raises(ValueError):c.set_status('practice-2026-10-10','completed')
    other,now,_=setup(tmp_path,events=[event()]);now[0]=epoch('2026-10-10T11:00:00+08:00')
    assert not other.snapshot()['recentCompletedEvents'] and other.records['practice-2026-10-10']['status']=='ended'

def test_duplicate_invalid_and_dst_dates_rejected(tmp_path):
    bad=event();bad['endDateTime']=bad['startDateTime']
    c,_,_=setup(tmp_path,events=[event(),event(),bad]);assert len(c.events)==1 and len(c.validation_errors)==2
    for wall in ('2026-03-08T02:30:00','2026-11-01T01:30:00'):
        bad=event();bad.update(timezone='America/New_York',startDateTime=wall,endDateTime='2026-11-02T04:00:00-05:00')
        c,_,_=setup(tmp_path,events=[bad]);assert c.validation_errors and not c.events

def test_only_confirmed_dated_activity_not_fictional_history(tmp_path):
    c,now,_=setup(tmp_path);c.confirmed_action('read_book');c.confirmed_action('read_book')
    assert len(c.history)==1
    now[0]+=86400
    assert c.viewer_facts('What did you do yesterday?')['confirmedActions']==['read_book']
    now[0]+=86400
    assert c.viewer_facts('What did you do yesterday?')['missingHistory']

def test_daily_history_survives_recent_buffer_and_restart(tmp_path):
    c,now,config=setup(tmp_path);path=tmp_path/'events.json';c.enable_persistence(path);c.confirmed_action('read_book')
    now[0]+=86400
    for _ in range(100):
        now[0]+=.1;c.confirmed_action('presentation_beat')
    assert len(c.history)==96
    restored=WorldCalendar(lambda:now[0],config);restored.enable_persistence(path)
    assert restored.viewer_facts('What did you do yesterday?')['confirmedActions']==['read_book']

def test_missing_config_is_safe_empty_calendar_and_observable(tmp_path):
    c=WorldCalendar(lambda:epoch('2026-10-09T10:00:00+08:00'),tmp_path/'missing.json')
    assert c.snapshot()['timezone']=='America/New_York' and c.validation_errors and not c.events

def test_friday_does_not_become_weekend_in_speech():
    s=SimpleNamespace(trace=lambda *a,**kw:None)
    show=LifestyleShowRunner(s,clock=lambda:epoch('2026-10-09T00:10:00+08:00'))
    assert 'weekend starts on Saturday' in show.guard_speech("We're officially into the weekend!")
    assert show.guard_speech('No appointments are scheduled this weekend.')=='No appointments are scheduled this weekend.'

def test_calendar_answer_replaces_fabricated_extra_history_before_audio():
    show=LifestyleShowRunner(SimpleNamespace(trace=lambda *a,**kw:None),clock=lambda:epoch('2026-10-09T00:10:00+08:00'))
    show.running_turn='viewer_answer';show.calendar_reply=show.calendar.viewer_answer('When is your next dance performance?')
    assert show.guard_speech('My last attempt was the Macarena.')=="I haven't scheduled my next dance performance yet."
    assert show.guard_speech('The last time I danced was yesterday.') is None
    assert show.calendar.viewer_answer('Nice day! How are you?') is None

@pytest.mark.parametrize('question',['What date is it?','What day is today?','Is it Friday?','What month is it?',"What's happening this weekend?",'What are you doing tomorrow?','When is your next dance performance?','What did you do yesterday?'])
def test_calendar_questions_grounded_and_not_physical_commands(tmp_path,question):
    c,_,_=setup(tmp_path);facts=c.viewer_facts(question);assert facts
    assert classify_viewer(question).kind=='CONVERSATION_INTENT'
    if facts['questionType']=='schedule':assert facts['noSchedule'] and facts['events']==[]
    assert c.viewer_answer(question)

def test_real_plan_is_distinct_from_flexible_weekday_preference(tmp_path):
    c,_,_=setup(tmp_path,events=[event()]);assert c.snapshot()['weeklyRoutine']['actionWeights']['dance']>1
    assert c.viewer_facts("What's happening this weekend?")['events'][0]['eventId']=='practice-2026-10-10'
    assert c.planned_action([], {}) is None
    assert c.planned_action(['dance'], {'dance':c.clock()+10}) is None

def test_names_route_to_distinct_existing_rooms():
    assert classify_viewer('show me MIKA MOTION').action=='visit_dance_studio'
    assert classify_viewer('go to NEON PULSE').action=='visit_rhythm_arcade'

def test_bad_checkpoint_does_not_replace_story_or_create_events(tmp_path):
    c,_,_=setup(tmp_path);p=tmp_path/'state.json';p.write_text('{bad')
    c.enable_persistence(p);assert c.last_error and not c.events




def ny(tmp_path, utc):
    return setup(tmp_path, utc, zone='America/New_York')[0].snapshot()


def test_mika_lives_on_new_york_time_by_default():
    config = json.loads((Path(__file__).resolve().parents[1] / 'room/calendar.json').read_text())
    assert config['timezone'] == 'America/New_York' and 'New York' in config['regionalContext']
    assert abs(config['location']['latitude'] - 40.71) < .1


@pytest.mark.parametrize('before,after,local_before,local_after,offset_before,offset_after', [
    # Spring forward: 01:59 EST is followed by 03:00 EDT.
    ('2026-03-08T06:59:00+00:00', '2026-03-08T07:00:00+00:00', '01:59', '03:00', -5, -4),
    # Fall back: 01:30 happens twice, an hour apart in UTC.
    ('2026-11-01T05:30:00+00:00', '2026-11-01T06:30:00+00:00', '01:30', '01:30', -4, -5),
])
def test_new_york_dst_transitions(tmp_path, before, after, local_before, local_after, offset_before, offset_after):
    a, b = ny(tmp_path, before), ny(tmp_path, after)
    assert (a['localTime'], b['localTime']) == (local_before, local_after)
    assert a['currentDate'] == b['currentDate'] == before[:10]
    for state, offset in ((a, offset_before), (b, offset_after)):
        local = datetime.fromtimestamp(state['clockEpochMs'] / 1000, __import__('zoneinfo').ZoneInfo('America/New_York'))
        assert local.utcoffset().total_seconds() / 3600 == offset


def test_new_york_midnight_is_the_day_boundary(tmp_path):
    late, early = ny(tmp_path, '2026-10-10T03:59:59+00:00'), ny(tmp_path, '2026-10-10T04:00:00+00:00')
    assert (late['currentDate'], late['weekdayName'], late['localTime']) == ('2026-10-09', 'Friday', '23:59')
    assert (early['currentDate'], early['weekdayName'], early['localTime']) == ('2026-10-10', 'Saturday', '00:00')


@pytest.mark.parametrize('utc,sky,sunset', [
    ('2026-06-21T22:00:00+00:00', 'DAY', 20.5),    # 18:00 EDT in June: sun still up
    ('2026-10-09T22:00:00+00:00', 'DUSK', 18.35),  # 18:00 EDT in October: around sunset
    ('2026-12-21T23:00:00+00:00', 'NIGHT', 16.55), # 18:00 EST in December: dark
])
def test_sky_follows_new_york_sunset_by_season(tmp_path, utc, sky, sunset):
    state = ny(tmp_path, utc)
    assert state['sky'] == sky and abs(state['sunset'] - sunset) < .15, state['sunset']


