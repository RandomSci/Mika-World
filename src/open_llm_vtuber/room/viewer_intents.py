"""Fast semantic admission before conversation; no viewer transforms or tools."""
from dataclasses import dataclass, field
import re


@dataclass
class ViewerIntent:
    kind: str = 'CONVERSATION_INTENT'
    action: str | None = None
    arguments: dict = field(default_factory=dict)


# Real places she can walk to in the world, by keyword.
PLACES = [
    (r'magic sanctuary|sanctuary|spell ?book|magic (place|area|spot|circle)', 'magic_sanctuary'),
    (r'koi bridge|bridge', 'koi_bridge'),
    (r'koi|fish|pond', 'koi_pond'),
    (r'pond bench|bench by the pond', 'pond_bench'),
    (r'jog(ging)? (loop )?bench|bench on the (jog|loop)', 'jog_bench'),
    (r'lantern bench|bench by the lantern', 'lantern_bench'),
    (r'bench', 'pond_bench'),
    (r'stone lantern', 'stone_lantern'),
    (r'gravel|zen', 'zen_gravel'),
    (r'(west|left) corner', 'west_corner'),
    (r'(east|right) corner', 'east_corner'),
    (r'far (end|corner)|corner of the garden|end of the garden|back of the garden', 'north_lawn'),
    (r'(open )?(grass|lawn|field)', 'open_lawn'),
    (r'art studio|atelier|gallery', 'art_studio'),
    (r'reading chair|armchair', 'reading_chair'),
    (r'\bdesk\b|computer|\bpc\b|workstation', 'desk'),
    (r'\bwindow\b', 'window'),
    (r'hallway|\bhall\b|lounge', 'hallway'),
    (r'bedroom|your room', 'bedroom'),
]
GO = r"\b(go|walk|head|run|wander|take (me|us)|bring (me|us)|visit|move|stroll|show (me|us))\b"
ROUTINE_IDS = [('macarena', 'macarena'), ('chicken dance', 'chicken'), ('belly dance', 'belly'), ('booty hip hop', 'booty_hiphop'),
               ('bounce hip hop', 'booty_hiphop'), ('snake hip hop', 'snake_hiphop'), ('step hip hop', 'step'), ('ymca', 'ymca')]


def destination(value):
    """('go_to', place) when a viewer asks her to go somewhere real."""
    if not re.search(GO, value) or re.search(r"\b(dont|don't|do not|never|stop)\b", value):
        return None
    for pattern, place in PLACES:
        if re.search(pattern, value):
            return place
    return None


def classify_viewer(text):
    value = text.lower().strip()
    if re.search(r"\b(dont|don't|do not|never|stop)\s+(go|going|walk|walking|visit|head|cast|casting|leave)\b", value):
        return ViewerIntent('ACTION_INTENT', 'listen_to_viewer')
    # Asking for a spell is asking for the lesson (it walks to the sanctuary
    # itself); "go to your sanctuary" alone is just the walk.
    if re.search(r"\b(cast|try|do|practi[cs]e|show)\b.*\b(spell|magic(?!\s+(?:sanctuary|place|area|spot|circle))|incantation)\b|\bmagic (lesson|practice|training)\b", value) and not re.search(r"\b(dont|don't|do not|never|stop)\b", value):
        return ViewerIntent('ACTION_INTENT', 'magic_lesson')
    place = destination(value)
    if place:
        return ViewerIntent('ACTION_INTENT', 'go_to', {'place': place})
    if re.search(r"\b(don't|do not|never|stop)\s+(throw|toss|jog|run|change|flip|read|sit)",value):
        return ViewerIntent('ACTION_INTENT','listen_to_viewer')
    if re.search(r"\b(don't|do not|never)\s+(dance|play|perform)\b",value):return ViewerIntent('ACTION_INTENT','stop_dancing')
    if re.search(r'^(why (would|did)|how (do|does)|i (would|will) never)\b',value):return ViewerIntent()
    if re.search(r'\b(what dance|how did you do|what.*score|how.*dance|what.*routine)\b',value):return ViewerIntent()
    if re.search(r'\b(stop|quit|cancel)\b.*\b(dance|dancing|routine|game)\b',value):return ViewerIntent('ACTION_INTENT','stop_dancing')
    if re.search(r'\b(show|visit|go|take)\b.*\b(dance studio|mirror studio|purple studio|mika motion)\b',value):return ViewerIntent('ACTION_INTENT','visit_dance_studio')
    if re.search(r'\b(show|visit|go|take)\b.*\b(arcade|dance room|rhythm room|neon pulse)\b',value):return ViewerIntent('ACTION_INTENT','visit_rhythm_arcade')
    if re.search(r'\b(show|see)\b.*\b(tv|instructor|dance screen)\b',value):return ViewerIntent('ACTION_INTENT','show_dance_tv')
    if re.search(r'\b(return|go|head)\b.*\bhome\b',value):return ViewerIntent('ACTION_INTENT','return_home')
    if re.search(r'\b(quiet|rest|stargaze|stargazing)\b.*\b(outside|garden|sky)\b',value):return ViewerIntent('ACTION_INTENT','quiet_outside')
    if re.search(r'\b(jog|run)\b.*\b(garden|flower|loop)\b',value):return ViewerIntent('ACTION_INTENT','garden_jog')
    if re.search(r'\b(show|visit|go|head|take|walk)\b.*\b(atelier|art studio|art room|painting studio|your (paintings|canvases|easel))\b',value):return ViewerIntent('ACTION_INTENT','visit_atelier')
    if re.search(r'\b(pick|smell|grab)\b.*\b(flower|flowers|blossom)\b',value):return ViewerIntent('ACTION_INTENT','pick_flower')
    if re.search(r'\b(explore|wander|go exploring|look around (the|your) (garden|yard))\b',value):return ViewerIntent('ACTION_INTENT','explore')
    if re.search(r'\b(show|visit|go|take)\b.*\b(lantern|waterfront|retreat)\b',value):return ViewerIntent('ACTION_INTENT','visit_lantern_retreat')
    if re.search(r'\b(show|visit|go|head|take|walk|step)\b.*\b(garden|gardens|fresh air|pond|water|outside)\b',value):return ViewerIntent('ACTION_INTENT','visit_gardens')
    dance_request=bool(re.search(r"^(?:mika[,!:]?\s+)?(?:please\s+)?(?:(?:can|could|would|will)\s+you\s+(?:please\s+)?(?:dance|try|perform|do|practice|play|beat)|(?:let's|lets|let us)\s+(?:dance|try|perform|play)|dance\b|(?:try|perform|do|practice|rehearse|play|start|begin|beat|give|show)\s+)",value))
    # "can you go dancing", "go dance for us": a request, not a compliment.
    dance_request=dance_request or bool(re.search(r"\b(?:(?:can|could|would|will)\s+you\s+(?:please\s+)?go|go|time to|wanna|want to)\s+(?:dance|dancing)\b",value)) and not re.search(r"\b(dont|don't|do not|never|stop)\b",value)
    # two mages live here: "can you and Luna dance", "you two", "Mika and Luna please dance" are requests too
    dance_request=dance_request or bool(re.search(r"(?:\b(?:can|could|would|will)\s+(?:you|y'all)(?:\s+(?:and\s+(?:luna|mika)|two|both|guys|girls))?|\b(?:mika|luna)(?:\s+(?:and|&)\s+(?:mika|luna))?[,!:]?|\bboth of you|\byou two)\s+(?:please\s+)?(?:dance|perform|do|try)\b",value)) and not re.search(r"\b(dont|don't|do not|never|stop)\b",value)
    for word,routine in ROUTINE_IDS:
        if word in value:
            return ViewerIntent('ACTION_INTENT','dance',{'routine':routine}) if dance_request else ViewerIntent()
    if re.search(r'\b(beat.*score|rhythm game|dance game|disco party)\b',value):
        return ViewerIntent('ACTION_INTENT','dance_challenge',{'room':'ARCADE','mode':'CHALLENGE_MODE'}) if dance_request else ViewerIntent()
    if re.search(r'^(try again|repeat (the |that )?(dance|routine))\b',value):return ViewerIntent('ACTION_INTENT','repeat_dance')
    if re.search(r'\b(record|film)\b.*\b(dance|routine|choreography)\b',value):return ViewerIntent('ACTION_INTENT','record_dance_content')
    if re.search(r'\b(practice|rehearse)\b.*\b(choreography|routine|dance)\b',value):return ViewerIntent('ACTION_INTENT','dance',{'room':'STUDIO','mode':'PRACTICE_MODE'})
    # an encore is a request: "Dance again please!", "one more dance", "another dance", "encore" (2026-10-17: read as
    # a compliment, so nothing happened while the reply promised "sure, one more dance")
    if re.search(r"\b(dance again|again.{0,15}\bdanc|one more (dance|song)|another (dance|song)|dance one more|dance some more|keep dancing|encore)\b",value) and not re.search(r"\b(dont|don't|do not|never|stop|no more)\b",value):
        return ViewerIntent('ACTION_INTENT','dance_session')
    if re.search(r'\b(dance|dancing)\b',value) and not dance_request:return ViewerIntent()
    rules = [
        (r'\b(stop|steady|stabilize)\b.*\b(camera|shaking|moving)\b', 'stabilize_camera', {}),
        (r'\b(draw|drawing|sketch)\b', 'draw_doodle', {}),
        (r'\b(dance|dancing)\b', 'dance_session', {}),
        (r'\b(listen|stop talking|wait a second|hold on)\b', 'listen_to_viewer', {}),
        (r'\b(throw|toss|yeet)\b.*\b(phone|camera)\b', 'throw_phone', {}),
        (r'\b(show|give|take)\b.*\b(around|tour)\b', 'tour_room', {}),
        (r'\b(flip|switch)\b.*\b(camera|lens)\b', 'flip_rear_camera', {}),
        (r'\b(show|look at)\b.*\b(desk|pc|computer|monitor)\b', 'show_desk', {}),
        (r'\b(show|look at)\b.*\b(window|outside view)\b', 'show_window', {}),
        (r'\b(put|place|set)\b.*\b(phone|camera)\b.*\b(down|desk|table)\b', 'place_phone_for_full_body', {}),
        (r'\b(pick|grab)\b.*\b(it|phone|camera)\b', 'pick_up_phone', {}),
        (r'\b(read|open)\b.*\b(book|manga|comic)\b', 'read_book', {}),
        (r'\b(sit|take a seat)\b', 'sit_chair', {}),
        (r'\bstand (up|please)\b', 'stand_relaxed', {}),
        (r'\b(show|see)\b.*\b(outfit|clothes|full body)\b', 'show_outfit', {}),
        (r'\b(change|switch)\b.*\b(outfit|clothes|clothing)\b', 'change_outfit', {}),
        (r'\b(jogging|jog|go for a run|go running|go exercise|work out|workout)\b', 'go_jogging', {}),
        (r'\b(go|head|step)\b.*\bpark\b', 'go_jogging', {}),
        (r'\b(go to sleep|lie down|bedtime)\b', 'rest_on_bed', {}),
    ]
    for pattern, action, arguments in rules:
        if re.search(pattern, value):
            mixed = bool(re.search(r'\b(why|what|how|tell me|and explain)\b', value))
            return ViewerIntent('MIXED_INTENT' if mixed else 'ACTION_INTENT', action, arguments)
    return ViewerIntent()
