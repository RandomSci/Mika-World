import json
from pathlib import Path
from types import SimpleNamespace
import pytest
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"src"))
from open_llm_vtuber.room.session_checkpoint import SessionCheckpoint
from open_llm_vtuber.room.viewer_intents import classify_viewer
from open_llm_vtuber.room.lifestyle import LifestyleShowRunner
ROOT=Path(__file__).resolve().parents[1]

@pytest.mark.parametrize('message,action',[('can you stop moving the camera','stabilize_camera'),('draw something','draw_doodle'),('dance','dance_session'),('stand up','stand_relaxed'),('listen','listen_to_viewer')])
def test_explicit_action_or_truthful_unavailable_intents(message,action):
 assert classify_viewer(message).action==action

def test_checkpoint_preserves_logical_goal_and_excludes_viewer_identity(tmp_path):
 checkpoint=SessionCheckpoint(tmp_path/'session.json')
 show=SimpleNamespace(clock=lambda:100,story=SimpleNamespace(id='home_day',index=2,recent_beats=['phone_vlog']),topics=SimpleNamespace(previous_topics=[{'title':'A little project'}]),cooldowns={'throw_phone':500},energy=.4,reality=SimpleNamespace(physical={'scene':'PARK','outfit':'WORKOUT'}))
 checkpoint.save(show);loaded=checkpoint.load(101)
 assert loaded['story']['index']==2 and loaded['cooldowns']['throw_phone']==500
 assert 'HOME' in loaded['restartPhysicalPolicy']
 assert not any(k in loaded for k in ('viewer','messages','cameraTransform','rigidBody','heldObject'))
 assert checkpoint.load(100000) is None

@pytest.mark.parametrize('data',[{'version':1,'savedAt':100,'story':{'id':'fake','index':1}},{'version':1,'savedAt':100,'story':{'id':'home_day','index':999}},{'version':2}, {'version':1,'savedAt':100000,'story':{'id':'home_day','index':0}}])
def test_invalid_restart_checkpoint_rejected(tmp_path,data):
 path=tmp_path/'state.json';path.write_text(json.dumps(data));assert SessionCheckpoint(path).load(101) is None

def test_quiet_reading_has_activity_specific_pacing():
 class Session:
  def trace(self,*a,**k):pass
 show=LifestyleShowRunner(Session());show.segment='READING';interval=show.speech_interval()
 assert show.pacing=='QUIET_ACTIVITY' and 90<=interval<=180  # reading is a quiet stretch
 show.segment='PHONE_VLOG';show.reality.physical['currentActivity']='jogging'
 assert 18<=show.speech_interval()<=30

@pytest.mark.parametrize('invalid',[{'energy':'bad'},{'energy':float('nan')},{'recentTopics':None},{'cooldowns':[]},{'cooldowns':{'throw_phone':float('inf')}},{'savedAt':float('nan')}])
def test_corrupted_checkpoint_payload_cannot_break_startup(tmp_path,invalid):
 data={'version':1,'savedAt':100,'story':{'id':'home_day','index':0},**invalid}
 path=tmp_path/'state.json';path.write_text(json.dumps(data));assert SessionCheckpoint(path).load(101) is None
