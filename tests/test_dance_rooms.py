"""Physical door ownership, grounded local choreography and semantic admission."""
import asyncio
import hashlib
import json
import math
from pathlib import Path
from types import SimpleNamespace
import pytest
ROOT = Path(__file__).resolve().parents[1]
from open_llm_vtuber.room.viewer_intents import classify_viewer
from open_llm_vtuber.room.lifestyle import LifestyleShowRunner, CAMERAS
from open_llm_vtuber.room.session_checkpoint import SessionCheckpoint
from open_llm_vtuber.room.reality import speech_guard

@pytest.mark.parametrize('message,action,args',[
 ('show me your dance studio','visit_dance_studio',{}),
 ('go to the neon arcade','visit_rhythm_arcade',{}),
 ("let's play the dance game",'dance_challenge',{'room':'ARCADE','mode':'CHALLENGE_MODE'}),
 ('practice your choreography','dance',{'room':'STUDIO','mode':'PRACTICE_MODE'}),
 ('try the Macarena','dance',{'routine':'macarena'}),
 ('stop dancing','stop_dancing',{}),
 ("don't dance",'stop_dancing',{}),
 ('show the TV','show_dance_tv',{}),
 ('return home','return_home',{}),
 ('film a dance','record_dance_content',{}),
 ('try again','repeat_dance',{}),
])
def test_room_intents_are_semantic(message,action,args):
 intent=classify_viewer(message);assert intent.action==action and intent.arguments==args

@pytest.mark.parametrize('message',['what dance are you doing','how did you do','what is your score','how does the dance game work'])
def test_information_does_not_start_a_routine(message):
 assert classify_viewer(message).action is None

def test_dance_camera_admission_and_activity_silence():
 assert {'PHONE_PLACED_STUDIO','PHONE_PLACED_ARCADE'}<=CAMERAS
 show=LifestyleShowRunner(SimpleNamespace(trace=lambda *a,**kw:None));show.reality.physical['currentActivity']='dancing'
 assert 45<=show.speech_interval()<=70 and show.pacing=='INTENTIONAL_SILENCE'

def test_dance_cooldown_survives_safe_logical_restart(tmp_path):
 checkpoint=SessionCheckpoint(tmp_path/'session.json')
 show=SimpleNamespace(clock=lambda:100,story=SimpleNamespace(id='dance_practice',index=1,recent_beats=[]),topics=SimpleNamespace(previous_topics=[]),cooldowns={'dance':1900},energy=.5,reality=SimpleNamespace(physical={'scene':'STUDIO'}))
 checkpoint.save(show);state=checkpoint.load(101)
 assert state['cooldowns']['dance']==1900 and state['story']['id']=='dance_practice'
 assert state['restartPhysicalPolicy'].startswith('HOME') and 'cameraTransform' not in state



def test_finished_routine_cannot_be_announced_as_current_performance():
 reality={'dance':{'game':{'active':False}}}
 assert speech_guard("I'm practicing the Macarena right now!",reality)[1]=='unconfirmed_current_dance'
 assert speech_guard('The last routine was the Macarena.',reality)==('The last routine was the Macarena.',None)




@pytest.mark.parametrize('message',['I like the Macarena','what do you think of the Macarena?','I saw the Chicken Dance yesterday','can you explain the dance game?','dancing looks fun','I love disco parties'])
def test_dance_mentions_are_conversation_not_motor_commands(message):
 assert classify_viewer(message).action is None

@pytest.mark.parametrize('name,routine',[('Belly Dance','belly'),('Booty Hip Hop Dance','booty_hiphop'),('Snake Hip Hop Dance','snake_hiphop'),('Step Hip Hop Dance','step'),('YMCA Dance','ymca'),('Chicken Dance','chicken')])
def test_unreviewed_named_routine_is_preserved_for_admission_rejection(name,routine):
 intent=classify_viewer('Try the '+name)
 assert intent.action=='dance' and intent.arguments['routine']==routine
