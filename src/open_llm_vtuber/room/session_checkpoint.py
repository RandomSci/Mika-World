"""Small versioned logical checkpoint; no viewer identities or live transforms."""
import json
import time
import math
from pathlib import Path
from .story_director import STORIES

class SessionCheckpoint:
    def __init__(self, path):
        self.path = Path(path)

    def load(self, now=None):
        now = time.time() if now is None else now
        try:
            if self.path.stat().st_size > 24000:
                return None
            data = json.loads(self.path.read_text())
            if not isinstance(data,dict) or data.get('version') != 1:
                return None
            saved=data['savedAt']
            if not isinstance(saved,(int,float)) or not math.isfinite(saved) or now-saved > 86400 or saved > now+60:
                return None
            story = data.get('story', {})
            if not isinstance(story,dict) or story.get('id') not in STORIES or type(story.get('index')) is not int or not 0 <= story['index'] < len(STORIES[story['id']]['beats']):
                return None
            energy=data.get('energy',.65)
            if not isinstance(energy,(int,float)) or not math.isfinite(energy) or not 0<=energy<=1:
                return None
            for items,maximum,length in [(story.get('recentBeats',[]),12,64),(data.get('recentTopics',[]),8,140)]:
                if not isinstance(items,list) or len(items)>maximum or any(not isinstance(item,str) or len(item)>length for item in items):
                    return None
            cooldowns=data.get('cooldowns',{})
            if not isinstance(cooldowns,dict) or len(cooldowns)>64 or any(not isinstance(key,str) or len(key)>100 or not isinstance(value,(int,float)) or not math.isfinite(value) for key,value in cooldowns.items()):
                return None
            autonomy=data.get('autonomy',{})
            if not isinstance(autonomy,dict) or len(json.dumps(autonomy))>6000:
                data['autonomy']={}
            return data
        except (OSError, ValueError, TypeError, KeyError):
            return None

    def save(self, show):
        # Physical scene/outfit are informational only. Restart ALWAYS rebuilds
        # HOME/front safely; never resume a collider, throw or halfway swap.
        data = {'version': 1, 'savedAt': show.clock(),
                'story': {'id': show.story.id, 'index': show.story.index,
                          'recentBeats': list(show.story.recent_beats)[-12:]},
                'recentTopics': [r['title'][:140] for r in list(show.topics.previous_topics)[-8:]],
                'cooldowns': {k:v for k,v in show.cooldowns.items() if (k.startswith(('throw_', 'segment_', 'failed_')) or k in ('dance','dance_challenge','repeat_dance','dance_activity')) and v > show.clock()},
                'energy': max(0, min(1, show.energy)),
                'lastScene': show.reality.physical.get('scene'),
                'lastOutfit': show.reality.physical.get('outfit'),
                'restartPhysicalPolicy': 'HOME / HOME outfit / safe handheld front',
                # Stream identity (greeting idempotence) and an unfinished goal to resume.
                'autonomy': show.autonomy.to_checkpoint() if hasattr(show, 'autonomy') else {}}
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix('.tmp')
        temporary.write_text(json.dumps(data, ensure_ascii=False))
        temporary.replace(self.path)
