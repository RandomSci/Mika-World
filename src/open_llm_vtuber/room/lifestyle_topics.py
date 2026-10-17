"""Session-only topic continuity and segment preferences; no scene transforms."""
from collections import deque
import random
import time

SEGMENTS = {
    'PHONE_VLOG': dict(action='casual_phone_chat', style='direct, warm and playful', categories=['room','daily','creative'], duration=150, energy=.65, camera='PHONE_HANDHELD_FRONT'),
    'THOUGHT_OF_THE_DAY': dict(action='casual_phone_chat', style='a thoughtful example, then a practical takeaway', categories=['productivity','money','daily'], duration=180, energy=.45, camera='PHONE_HANDHELD_FRONT'),
    'ROOM_LIFE': dict(action='look_out_window', style='notice something in the virtual room and build a reflection', categories=['room','observations','plans'], duration=150, energy=.4, camera='PHONE_HANDHELD_FRONT'),
    'READING': dict(action='read_book', style='imaginary reading notes and ideas; never fabricate a published quote', categories=['hobbies','creative','lore'], duration=180, energy=.35, camera='PHONE_PLACED'),
    'DESK_TALK': dict(action='place_phone_for_full_body', style='friendly technology and creative-work discussion', categories=['technology','productivity','business'], duration=180, energy=.5, camera='PHONE_PLACED'),
    'STORYTIME': dict(action='sit_chair', style='an explicitly fictional anecdote from this virtual room', categories=['lore','observations','hobbies'], duration=180, energy=.55, camera='PHONE_PLACED'),
    'SHOW_AND_TELL': dict(action='show_room', style='describe a visible object and why it catches your attention', categories=['room','creative'], duration=120, energy=.6, camera='PHONE_HANDHELD_REAR'),
    'RELAXED_CHAT': dict(action='casual_phone_chat', style='calm, curious, conversational', categories=['daily','hobbies','plans'], duration=150, energy=.3, camera='PHONE_HANDHELD_FRONT'),
    'Q_AND_A': dict(action='casual_phone_chat', style='answer the viewer and connect their idea to the ongoing thought', categories=['viewer','daily'], duration=120, energy=.5, camera='PHONE_HANDHELD_FRONT'),
    'CASUAL_CHAT': dict(action='casual_phone_chat', style='an easy conversation with a listening audience', categories=['daily','observations'], duration=150, energy=.5, camera='PHONE_HANDHELD_FRONT'),
}

SEEDS = {
    'daily': ['Why a tiny change can make a room feel new', 'The difference between a break and avoiding a task', 'Small rituals that make an ordinary day interesting'],
    'observations': ['Why objects look more dramatic from a low angle', 'The comedy of a plan with far too many steps', 'The suspicious talent of clutter to return'],
    'lore': ['An imaginary detective story about a missing bookmark', 'A fictional late-night debate with my own to-do list', 'A virtual-room adventure that never left the room'],
    'room': ['What makes a reading corner inviting', 'A tour of the room through objects rather than walls', 'How lighting changes the mood of a familiar place'],
    'creative': ['Inventing a ridiculous but harmless household gadget', 'Designing a cozy game in our imagination', 'Turning a mundane object into a story prompt'],
    'technology': ['Why good tools sometimes have fewer buttons', 'The appeal of small useful automations', 'What makes a digital space feel lived in'],
    'money': ['Why a shopping wish list can beat an impulse purchase', 'Needs, wants and the stories we attach to purchases', 'Comparing value without chasing a guaranteed bargain'],
    'business': ['Why understanding a customer starts with listening', 'A fictional tiny bookmark shop and its first decision', 'The difference between a useful idea and a catchy name'],
    'productivity': ['Making the first step smaller instead of forcing motivation', 'What to leave off a realistic to-do list', 'Why finishing a small draft can beat polishing forever'],
    'hobbies': ['A hobby that is allowed to stay a hobby', 'The charm of collecting ideas instead of equipment', 'Inventing a reading challenge with no pressure'],
    'plans': ['One small creative project for a future stream', 'What a relaxed virtual evening could look like', 'A room challenge that uses only things already here'],
    'viewer': ['Different ways people make a space their own', 'A question worth answering in more than one way'],
}
# The Godot world (VR_WORLD_RENDERER=godot): she is a mage in the Arcane Sanctuary, not a girl vlogging her bedroom.
GODOT_SEEDS = {
    'daily': ['Small rituals of a mage\'s day in the sanctuary', 'The difference between a break and avoiding practice', 'What makes an ordinary day in the sanctuary interesting'],
    'observations': ['Why the sanctuary looks different every hour', 'The comedy of a spell plan with far too many steps', 'Things Luna notices that I always miss'],
    'lore': ['What the old Keepers left behind in the sanctuary', 'A legend about the Ember Keeper', 'The story the library books keep hinting at'],
    'room': ['A favourite corner of the sanctuary', 'How the light changes the sanctuary through the day', 'What Starfall Hill looks like at different hours'],
    'creative': ['Inventing a ridiculous but harmless spell', 'Designing a cozy game in our imagination', 'Turning something from the world into a story prompt'],
    'hobbies': ['A hobby a mage is allowed to keep just for fun', 'Collecting little finds instead of trophies', 'A reading challenge from the Ancient Spell Library'],
    'plans': ['Somewhere in the world I want to explore next', 'A spell I want to learn properly', 'What a calm evening with Luna could look like'],
}


def _seeds() -> dict:
    import os
    return {**SEEDS, **GODOT_SEEDS}          # the stream is the Godot world


BEATS = ['introduce', 'example', 'develop', 'question', 'reflect', 'conclude']

class TopicManager:
    def __init__(self, rng=None, clock=time.time):
        self.rng=rng or random.Random();self.clock=clock
        self.current_topic=None;self.previous_topics=deque(maxlen=24)
        self.last_chat_interruption=None;self.last_activity='casual_phone_chat'
        self.position_in_topic=0;self.viewer_feedback=deque(maxlen=5)
        self.open_question=None;self.next_possible_direction=None
        self.recent_lines=deque(maxlen=6);self.used={};self.resuming=False
        self.long_lines=deque(maxlen=16)   # across topic changes (recent_lines is cleared): repetition memory

    def available(self,segment):
        now=self.clock();spec=SEGMENTS[segment]
        seeds=_seeds()
        choices=[(category,title) for category in spec['categories'] for title in seeds[category] if now-self.used.get(title,-1e9)>1200]
        return choices or [(category,title) for category in spec['categories'] for title in seeds[category]]

    def start(self, segment, proposal=None):
        now=self.clock();spec=SEGMENTS[segment]
        if self.current_topic:self.previous_topics.append({**self.current_topic,'last_point':self.recent_lines[-1][-360:] if self.recent_lines else ''})
        choices=self.available(segment)
        proposed=str((proposal or {}).get('topic',''))
        category,title=next((item for item in choices if item[1]==proposed),self.rng.choice(choices))
        # An AI proposal supplies an angle, while category/action remain validated.
        angle=str((proposal or {}).get('angle') or '')[:180]
        self.current_topic={'title':title,'category':category,'segment':segment,'angle':angle,'topic_start_time':now,'topic_interest_score':.7,'topic_exhaustion':0}
        self.used[title]=now;self.position_in_topic=0;self.viewer_feedback.clear();self.open_question=None
        self.next_possible_direction='a concrete example';self.recent_lines.clear();self.resuming=False
        return self.current_topic

    def feedback(self, text):
        self.last_chat_interruption=self.clock();self.viewer_feedback.append(text[:240]);self.resuming=True
        if self.current_topic:self.current_topic['topic_interest_score']=min(1,self.current_topic['topic_interest_score']+.1)

    def record(self, text):
        self.recent_lines.append(text[-600:]);self.long_lines.append(text[-600:]);self.position_in_topic+=1
        if '?' in text:self.open_question=text[text.rfind('.')+1:][-220:]
        elif self.position_in_topic>4:self.open_question=None
        self.current_topic['topic_exhaustion']=min(1,self.position_in_topic/6)
        self.next_possible_direction=BEATS[min(5,self.position_in_topic)]
        self.resuming=False

    def snapshot(self):
        return dict(current_topic=self.current_topic,previous_topics=list(self.previous_topics),position_in_topic=self.position_in_topic,subpoint=BEATS[min(5,self.position_in_topic)],viewer_feedback=list(self.viewer_feedback),open_question=self.open_question,next_possible_direction=self.next_possible_direction,last_chat_interruption=self.last_chat_interruption,last_activity=self.last_activity,recent_lines=list(self.recent_lines),resuming=self.resuming)
