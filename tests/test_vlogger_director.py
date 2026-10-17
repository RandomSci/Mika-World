import json
import random
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from open_llm_vtuber.room.vlogger_director import TemporaryMemory,VloggerDirector
from open_llm_vtuber.room.viewer_intents import classify_viewer


def test_expiration_atomic_restart_and_no_private_chat(tmp_path):
    now=[2000000.0];path=tmp_path/'temporary.json';memory=TemporaryMemory(path,lambda:now[0])
    memory.records=[{'at':now[0]-20*86400-1,'kind':'hourly_plan','goal':'old'},{'at':now[0]-19*86400,'kind':'activity_completed','action':'visit_gardens'}]
    memory.add('hourly_plan',goal='fresh air',viewer_name='private',raw_text='secret');memory.save()
    restored=TemporaryMemory(path,lambda:now[0]);assert len(restored.records)==2
    assert 'private' not in path.read_text() and 'secret' not in path.read_text()
    assert not list(tmp_path.glob('*.tmp'))
    now[0]+=2*86400;restored.prune();assert len(restored.records)==1


def test_corrupt_checkpoint_recovers_without_fabricated_activity(tmp_path):
    path=tmp_path/'temporary.json';path.write_text('{broken')
    memory=TemporaryMemory(path,lambda:1000);assert memory.error and not memory.records


def test_hour_review_midnight_and_capability_guards():
    now=[1000.0];director=VloggerDirector(lambda:now[0],random.Random(3))
    state={'currentDate':'2026-12-31','localTime':'23:59','dayPart':'LATE_NIGHT','scene':'HOME','availableActions':[]}
    director.update(state);first=director.plan.copy();now[0]+=3600;assert director.propose(state) is None
    state.update(currentDate='2027-01-01',localTime='00:00',availableActions=['quiet_outside']);director.update(state)
    assert director.plan['date']=='2027-01-01' and director.plan['status']=='flexible_intention'
    assert director.plan!=first;now[0]+=360;assert director.propose(state)=='quiet_outside'
    assert director.propose(state) is None
    director.confirmed('quiet_outside','GROUNDS');assert director.memory.records[-1]['result']=='runtime_acknowledged'
    assert director.plan['status']!='completed'


def test_restore_cooldown_and_keep_permanent_store_separate(tmp_path):
    now=[1000.0];path=tmp_path/'temporary.json';permanent=tmp_path/'artworks.json';permanent.write_text('{"savedArtwork":"keep"}')
    director=VloggerDirector(lambda:now[0]);director.enable_persistence(path);director.confirmed('garden_jog','GROUNDS');director.memory.save()
    restored=VloggerDirector(lambda:now[0]);restored.enable_persistence(path);assert restored.cooldowns['garden_jog']==2800
    now[0]+=21*86400;restored.memory.save();assert json.loads(path.read_text())['records']==[]
    assert 'keep' in permanent.read_text()


def test_micro_gestures_do_not_reset_boredom_or_fill_activity_memory():
    director=VloggerDirector(lambda:1000)
    director.moods['boredom']=.8
    for _ in range(100):director.confirmed('presentation_beat','HOME')
    assert director.moods['boredom']==.8 and not director.memory.records
    director.confirmed('visit_gardens','GROUNDS')
    assert director.moods['boredom']<.8 and len(director.memory.records)==1


def test_restart_preserves_current_hour_intention_without_duplicate_daily_plan(tmp_path):
    now=[1000.0];path=tmp_path/'memory.json'
    state={'currentDate':'2026-10-09','localTime':'01:40','dayPart':'LATE_NIGHT','scene':'HOME'}
    first=VloggerDirector(lambda:now[0],random.Random(2));first.enable_persistence(path);first.update(state);first.memory.save()
    goal=first.plan['goal'];count=len(first.memory.records)
    restored=VloggerDirector(lambda:now[0],random.Random(9));restored.enable_persistence(path);restored.update(state)
    assert restored.plan['goal']==goal and len(restored.memory.records)==count
    state['localTime']='02:00';restored.update(state)
    assert restored.plan['hour']=='02' and len(restored.memory.records)==count+1
    assert sum(r['kind']=='daily_intention' for r in restored.memory.records)==1


def test_viewer_semantic_ground_routes():
    assert classify_viewer('show me the gardens').action=='visit_gardens'
    assert classify_viewer('visit the lantern waterfront').action=='visit_lantern_retreat'
    assert classify_viewer('jog the flower loop').action=='garden_jog'
    assert classify_viewer('go jog in the garden').action=='garden_jog'
    assert classify_viewer('go rest quietly outside in the garden').action=='quiet_outside'
    assert classify_viewer('return home').action=='return_home'
