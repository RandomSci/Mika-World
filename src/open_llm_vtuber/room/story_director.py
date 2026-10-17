"""Goals and open threads across activities; speech itself remains generated."""
from collections import deque
import random
import time

STORIES = {
    'rhythm_break': {'title':'A NEON PULSE rhythm challenge', 'goal':'Complete one simulated challenge, report the measured result, and return to a quieter activity.',
                     'beats':[('choose_a_fun_break','casual_phone_chat'),('try_the_neon_challenge','dance_challenge'),('review_the_actual_score','casual_phone_chat'),('read_and_recover','read_book')]},
    'dance_practice': {'title':'One routine, one deliberate practice break', 'goal':'Practice one validated routine, then return to the day; do not claim video recording or learned choreography.',
                      'beats':[('choose_the_practice','casual_phone_chat'),('practice_in_mika_motion','dance'),('reflect_on_the_actual_result','casual_phone_chat'),('read_and_settle','read_book')]},
    'home_day': {'title': 'Finding the shape of my day', 'goal': 'Try one idea, test it in the room, and decide what is worth keeping.',
                 'beats': [('phone_vlog', 'casual_phone_chat'), ('inspect_the_workspace', 'show_desk'),
                           ('read_and_compare', 'read_book'), ('show_the_result', 'show_outfit'),
                           ('fresh_air', 'go_jogging'), ('back_home', 'casual_phone_chat')]},
    'night_reset': {'title': 'A small night-time reset', 'goal': 'Wind down without turning the stream into a silent sleep camera.',
                    'beats': [('night_thought', 'casual_phone_chat'), ('room_check', 'tour_room'),
                              ('reading_break', 'read_book'), ('comfortable_clothes', 'change_outfit'),
                              ('window_thought', 'show_window'), ('wrap_the_thread', 'casual_phone_chat')]},
    'workout_day': {'title': 'A tiny workout that escaped the room', 'goal': 'Change privately, head out through the house, jog the garden loop, and walk back home.',
                    'beats': [('choose_the_challenge', 'casual_phone_chat'), ('go_jogging', 'go_jogging'),
                              ('what_changed', 'casual_phone_chat'), ('read_and_recover', 'read_book')]},
}


class StoryDirector:
    def __init__(self, rng=None, clock=time.time):
        self.rng = rng or random.Random(); self.clock = clock
        self.id = 'home_day'; self.index = 0; self.beat_started = clock()
        self.open_threads = deque(maxlen=5); self.viewer_influence = deque(maxlen=6)
        self.recent_beats = deque(maxlen=20); self.used = {}; self.mood = 'curious'

    @property
    def beat(self): return STORIES[self.id]['beats'][self.index][0]

    def begin(self, day_part):
        self.id = 'night_reset' if day_part == 'LATE_NIGHT' else 'home_day'
        self.index = 0; self.beat_started = self.clock()

    def next_action(self): return STORIES[self.id]['beats'][self.index][1]

    def upcoming_action(self):
        beats=STORIES[self.id]['beats'];return beats[self.index+1][1] if self.index+1<len(beats) else 'casual_phone_chat'

    def advance(self, viewer=None, day_part=None, calendar=None):
        self.recent_beats.append(self.beat)
        if viewer: self.viewer_influence.append(viewer[:200])
        self.index += 1
        if self.index >= len(STORIES[self.id]['beats']):
            self.used[self.id] = self.clock()
            options = [key for key in STORIES if key != self.id and self.clock() - self.used.get(key, -1e9) > 900]
            if day_part in ('MORNING','AFTERNOON'):
                options = [key for key in options if key != 'night_reset']
            elif day_part == 'LATE_NIGHT':
                options = [key for key in options if key not in ('workout_day','dance_practice','rhythm_break')]
            choices=options or ['home_day']
            weights=(calendar or {}).get('weeklyRoutine',{}).get('actionWeights',{})
            story_action={'dance_practice':'dance','rhythm_break':'dance_challenge','workout_day':'go_jogging','night_reset':'read_book','home_day':'show_desk'}
            self.id = self.rng.choices(choices,weights=[weights.get(story_action[key],1) for key in choices],k=1)[0]; self.index = 0
        self.beat_started = self.clock()

    def snapshot(self,scene='HOME'):
        spec = STORIES[self.id]
        return {'id': self.id, 'title': spec['title'], 'goal': spec['goal'],
                'scene': scene, 'preferredOutfit': 'WORKOUT' if scene=='PARK' else 'LOUNGE' if self.id == 'night_reset' else 'HOME',
                'currentBeat': self.beat, 'possibleNextBeats': [b for b, _ in spec['beats'][self.index+1:self.index+3]],
                'openThreads': list(self.open_threads), 'viewerInfluence': list(self.viewer_influence),
                'recentBeats': list(self.recent_beats), 'completion': 'Complete the current sequence of confirmed activities', 'cooldownSeconds': 900}
