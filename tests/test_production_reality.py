import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"src"))
from types import SimpleNamespace
import random
from open_llm_vtuber.room.viewer_intents import classify_viewer
from open_llm_vtuber.room.reality import RealityState,speech_guard
from open_llm_vtuber.room.story_director import StoryDirector

def test_viewer_actions_are_semantic_and_observation_is_conversational():
    expected={'throw the phone':'throw_phone','show us around':'tour_room','flip the camera':'flip_rear_camera','show the desk':'show_desk','read the book':'read_book','sit down':'sit_chair','go exercise':'go_jogging','show your outfit':'show_outfit','go jogging':'go_jogging','listen!!':'listen_to_viewer'}
    for text,action in expected.items():
        intent=classify_viewer(text);assert intent.action==action
        assert not any(k in intent.arguments for k in ('x','y','z','rotation','bone'))
    for text in ('hi','what time is it','what can you actually do','what are you working on'):
        assert classify_viewer(text).kind=='CONVERSATION_INTENT'

def test_runtime_facts_replace_previous_outfit_and_scene_without_faking_props():
    reality=RealityState();reality.update({'worldState':{'scene':'HOME','outfit':'HOME','objects':[{'name':'Desk'}]}})
    reality.update({'worldState':{'scene':'PARK','outfit':'WORKOUT','objects':[{'name':'ParkBench'}],'cameraState':'PHONE_HANDHELD_FRONT'}})
    assert reality.physical['objects']==[{'name':'ParkBench'}]
    assert reality.physical['outfit']=='WORKOUT' and reality.physical['scene']=='PARK'
    assert 'Desk' not in str(reality.physical)

def test_grounding_rejects_observed_hallucinations_and_robot_laughter():
    assert speech_guard('I love my fairy lights.',{})[0] is None
    assert speech_guard('I just read chapter 98.',{})[0] is None
    assert speech_guard('HAHAHAHA That was close.',{})[0]=='That was close.'
    assert speech_guard('That desk is ridiculous.',{})[0]=='That desk is ridiculous.'

def test_story_peek_does_not_advance_failed_action():
    story=StoryDirector(random.Random(1));story.begin('AFTERNOON')
    before=story.beat;assert story.upcoming_action()=='show_desk' and story.beat==before
    story.advance();assert story.beat=='inspect_the_workspace'
    story.begin('LATE_NIGHT');assert story.id=='night_reset'

def test_completed_day_story_does_not_select_night_reset_in_afternoon():
    story=StoryDirector(random.Random(1));story.begin('AFTERNOON')
    for _ in range(30):
        story.advance(day_part='AFTERNOON')
        assert story.id!='night_reset'

def test_room_claims_use_actual_parts_and_allow_hypothetical_props():
    state={'objects':[{'name':'Desk'}],'objectParts':{'Bed':['SoftPillow']}}
    assert speech_guard('There is a crumpled notebook here.',state)[0] is None
    assert speech_guard('These spotless pens on my desk are perfect.',state)[0] is None
    assert speech_guard('Imagine a notebook that folds itself.',state)[0]
    assert speech_guard('This pillow is ridiculous.',state)[0]
    state['objects'].append({'name':'Notebook'})
    assert speech_guard('This notebook is ridiculous.',state)[0]
