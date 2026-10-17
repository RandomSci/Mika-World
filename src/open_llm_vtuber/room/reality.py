"""The Stage supplies physical facts; the server adds only its own story state."""
import os
import json
from pathlib import Path


GODOT_CAL_DROP = ('timezone', 'city', 'clock12', 'localTime', 'currentTime', 'location', 'seasonOrRegionalContext',
                  'sky', 'sunrise', 'sunset', 'hour', 'clockEpochMs')


class RealityState:
    def __init__(self):
        self.physical = {}
        self.curated=json.loads((Path(__file__).resolve().parents[3]/'room/content-curated.json').read_text())

    def update(self, state):
        actual = state.get('worldState')
        if isinstance(actual, dict):
            keys = ('spatial','grounds','wallpaper','scene', 'sceneName', 'calendarDecorations', 'locationAnchor', 'outfit', 'cameraState', 'heldObject',
                    'reachableObjects', 'visibleObjects', 'objects', 'availableActions',
                    'availableTransitions', 'transitionNames', 'currentActivity', 'animation', 'monitor',
                    'privateTransition', 'capabilities', 'recentGestures','physicalState','activeAction','movement','parkPhase','visualContext','bookContents','objectParts','dance','books',
                    'revision','coordination','cinematography','expressions','health','audio','flowers','mageProgress','clock','weather')
            self.physical = {key: actual[key] for key in keys if key in actual}

    def snapshot(self, show):
        cal = show.calendar.snapshot()
        # the Godot world tells the time from its own (real) clock, loosely; no city, zone or coordinates ever
        cal = {k: v for k, v in cal.items() if k not in GODOT_CAL_DROP}
        return {**self.physical, **cal,
                'activeStory': show.story.snapshot(self.physical.get('scene','HOME')), 'currentBeat': show.story.beat,
                'vlogger':show.vlogger.snapshot(), 'energy': show.energy, 'mood': show.story.mood,
                'recentActions': [{'event': e['event'], 'action': e.get('action'), 'reason': e.get('reason')}
                                  for e in list(show.history)[-8:]],
                'recentTopics': [row['title'] for row in list(show.topics.previous_topics)[-5:]],
                'currentTopic': (show.topics.current_topic or {}).get('title'),
                'curatedExternalTopics':self.curated,
                'residents': 'Mika and Luna (two young mages)', 'development': 'Only capabilities and availableActions confirm what she can do here. No announced release dates or contact URLs.'}

    def concise(self,show):
        state=self.snapshot(show)
        state['visibleObjects']=[o.get('name') for o in state.get('visibleObjects',[])]
        state['reachableObjects']=[o.get('name') for o in state.get('reachableObjects',[])]
        state['objects']=[o.get('name') for o in state.get('objects',[]) if o.get('name') not in ('Floor','Ceiling','BackWall','LeftWall','RightWall','WallSlat','GoldPictureRail','BackWoodTrim','LeftWoodTrim','RightWoodTrim')]
        state['capabilities']={k:{'available':v.get('available'),'canPlan':v.get('canPlan'),'reason':v.get('reason')} for k,v in state.get('capabilities',{}).items() if not v.get('available')}
        state['animation']={k:v for k,v in state.get('animation',{}).items() if k in ('ready','name','source','error')}
        if state.get('grounds'):
            state['grounds']={k:v for k,v in state['grounds'].items() if k in ('implemented','loaded','ready','busy','error','water','destinations','weather')}
        if state.get('spatial'):
            spatial=state['spatial']
            state['spatial']={k:spatial.get(k) for k in ('zone','subzone','region','position','facingDeg','ground','held','interactive','exploration','previousZone','nearby','doors','connections','recentVisits','visibilityPolicy')}
            if state['spatial'].get('exploration'):state['spatial']['exploration']={k:state['spatial']['exploration'].get(k) for k in ('current','unvisitedRecently','places')}
            state['spatial']['knownLandmarks']=[{'id':r.get('id'),'label':r.get('label'),'zone':r.get('zone')} for r in spatial.get('landmarks',[])]
        # Operational detail stays out of the speaking context.
        for key in ('coordination','cinematography','health','audio'):state.pop(key,None)
        if state.get('dance'):
            dance=state['dance'];game=dance.get('game',{});result=game.get('lastResult')
            state['dance']={k:dance.get(k) for k in ('scene','busy','qualityReady','error','cycles')}
            state['dance']['doors']=[{'id':d.get('id'),'state':d.get('state'),'error':d.get('error')} for d in dance.get('doors',[])]
            state['dance']['game']={k:game.get(k) for k in ('state','active','routine','title','mode','score','combo','audio','audioPlaying','enabledRoutines')}
            if result:state['dance']['game']['lastResult']={k:result.get(k) for k in ('routine','mode','completed','reason','score','maxCombo','previousBest','newRecord','timingModel')}
        return state


def speech_guard(text, reality):
    """Small deterministic last guard before Ana, not a fabricated world database."""
    import re
    text = re.sub(r'\b(?:ha){2,}\b|\bHAHA(?:HA)*\b', '', text, flags=re.I).strip()
    if reality.get('dance') and not reality['dance'].get('game',{}).get('lastResult') and re.search(r'\b(?:last|previous) (?:dance |routine )?attempt\b|\bI (?:just |already )?(?:performed|practiced) (?:the )?Macarena\b',text,re.I):
        return "I don't have a recorded dance result in this session yet.",None
    if reality.get('dance',{}).get('game',{}).get('active') is False and re.search(r"\bI(?:'m| am) (?:dancing|practicing (?:the )?(?:Macarena|Chicken Dance))\b",text,re.I):
        return None,'unconfirmed_current_dance'
    # Check present physical claims against actual root/mesh/held names. General
    # recommendations and explicitly imagined props are not room assertions.
    if 'objects' in reality:
        names=[str(o.get('name',''))+' '+str(o.get('label','')) for o in reality['objects']]
        names += [str(part) for parts in reality.get('objectParts',{}).values() for part in parts]
        names += [str(reality.get('heldObject') or ''),'phone']
        known=re.sub(r'([a-z])([A-Z])',r'\1 \2',' '.join(names)).lower()
        aliases={'notebook':('notebook','notepad'),'pen':('pen','pencil'),'vase':('vase',),'mug':('mug','cup'),'candle':('candle',),'curtain':('curtain',),'blanket':('blanket','duvet'),'pillow':('pillow',),'sofa':('sofa','couch'),'television':('television','tv'),'speaker':('speaker',),'coffee maker':('coffee maker','coffee machine')}
        for sentence in re.split(r'(?<=[.!?])\s+',text):
            hypothetical=re.search(r'\b(imagine|imagining|fictional|hypothetical|I wish|I would add|I could add|I want to add|if I had|if there were|for a future)\b',sentence,re.I)
            present=re.search(r"\b(here|this|these|those|my|our|the room|on the desk|next to|beside|there is|there are)\b|there's",sentence,re.I)
            if hypothetical or not present:continue
            for entity,terms in aliases.items():
                if re.search(r'\b'+re.escape(entity)+r'(?:s)?\b',sentence,re.I) and not any(re.search(r'\b'+re.escape(term)+r'(?:s)?\b',known) for term in terms):
                    return None,'unsupported_physical_prop:'+entity
    # These are concrete hallucinations observed in acceptance, not real props.
    unsupported = ('fairy lights', 'blue vase', 'tapestry', 'cozy blanket', 'throw blanket', 'pillow fort', 'pet cat', 'my cat', 'my roommate')
    if any(word in text.lower() for word in unsupported):
        return None, 'unsupported_scene_detail'
    if re.search(r'\b(I just|I have|I already|when I) (rearranged|moved|bought|turned on|tucked away)\b', text, re.I):
        return None, 'unconfirmed_completed_action'
    if re.search(r'\b(chapter \d+|latest chapter|newest chapter)\b', text, re.I):
        return None, 'unverified_chapter_claim'
    if not text: return None, 'nonverbal_text_removed'
    return text, None
