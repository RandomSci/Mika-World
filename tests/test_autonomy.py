"""Goal-based autonomy: Mika acts without chat, greets once per stream, treats
"boring" as feedback she acts on, and recovers from failed goals."""
import asyncio
import random
import sys
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from open_llm_vtuber.room.autonomy import Autonomy, GOALS, is_boredom_feedback
from open_llm_vtuber.room.lifestyle import LifestyleShowRunner

HOME_ACTIONS = ['casual_phone_chat', 'read_book', 'visit_gardens', 'quiet_outside', 'visit_lantern_retreat', 'go_jogging',
                'dance', 'dance_session', 'sit_chair', 'tour_room', 'show_window', 'show_desk', 'presentation_beat', 'switch_selfie_profile']


class Clock:
    def __init__(self, t=1_000_000.0): self.t = t
    def __call__(self): return self.t


def stage_session(sent):
    async def send(uid, payload): sent.append(payload)
    return SimpleNamespace(_clients={'stage': True}, _send=send, trace=lambda *a, **k: None,
                           director=SimpleNamespace(ready=True), record_success=lambda _: None,
                           state=SimpleNamespace(characters={}))


def make_show(actions=HOME_ACTIONS, day_part=None, seed=4):
    sent = []
    show = LifestyleShowRunner(stage_session(sent), rng=random.Random(seed))
    show.register('stage'); show.clients['stage']['ready'] = True
    show.reality.physical = {'scene': 'HOME', 'availableActions': list(actions)}
    if day_part:
        show.calendar.snapshot = lambda **_: {**type(show.calendar).snapshot(show.calendar), 'dayPart': day_part}
    done, spoken = [], []
    async def command(action, **args):
        done.append(action)
        return {'ok': True, 'state': {}}
    async def speak(prompt, kind='autonomous', received=None):
        spoken.append((kind, prompt)); return 'Okay, here is my thought.'
    show.command, show.speak = command, speak
    return show, done, spoken, sent


def test_boredom_feedback_detection():
    for text in ['Boring', 'this is so boring', 'zzzz', 'do something!', "I'm bored"]:
        assert is_boredom_feedback(text), text
    for text in ['not boring at all', 'that isn\'t boring', 'what book is that?']:
        assert not is_boredom_feedback(text), text


def test_goals_only_from_executable_actions_and_scene():
    a = Autonomy(Clock(), random.Random(1))
    assert a.choose({'scene': 'HOME', 'availableActions': ['casual_phone_chat']}) is None
    assert a.blocking_reason == 'no_executable_goal_in_scene'
    picks = {a.choose({'scene': 'HOME', 'availableActions': ['read_book', 'tour_room']}).id for _ in range(30)}
    assert picks <= {'room_tour'}  # shelf reading is paused: never her own objective
    # Away from home, "head home" is no longer an automatic objective: nothing
    # sends her back to the bedroom between activities.
    a2 = Autonomy(Clock(), random.Random(1))
    assert a2.choose({'scene': 'GROUNDS', 'availableActions': ['return_home']}) is None


def test_late_night_prefers_quiet_goals_without_forbidding_activity():
    a = Autonomy(Clock(), random.Random(2))
    reality = {'scene': 'sanctuary', 'dayPart': 'LATE_NIGHT', 'availableActions': ['quiet_outside', 'dance_session', 'visit_gardens'],
               'vlogger': {'moods': {'energy': .35, 'boredom': .2, 'desireForQuiet': .8, 'restlessness': .2}}}
    scores = {s.id: w for s, w in a.candidates(reality)}
    assert scores['stargaze'] > scores['dance_practice'] and scores['stargaze'] > scores['fresh_air']
    assert scores['dance_practice'] > 0 and scores['fresh_air'] > 0  # not rigidly tied to a schedule


def test_stream_identity_new_versus_reconnection():
    clock = Clock()
    a = Autonomy(clock)
    assert a.begin_stream(None, None) == 'new_stream'
    saved = {**a.stream, 'greeted': True}
    b = Autonomy(clock)
    assert b.begin_stream(saved, clock() - 120) == 'reconnection' and b.stream['greeted']
    c = Autonomy(clock)
    assert c.begin_stream(saved, clock() - 7200) == 'new_stream' and not c.stream['greeted']


def test_fresh_stream_greets_once_and_starts_an_executable_goal(monkeypatch):
    import dataclasses
    monkeypatch.setitem(GOALS, 'fresh_air', dataclasses.replace(GOALS['fresh_air'], dwell=(0, 0)))
    async def go():
        show, done, spoken, _ = make_show(actions=['visit_gardens'])
        show.reality.physical['scene'] = 'sanctuary'
        await show.open_stream()
        assert [k for k, _ in spoken] == ['stream_greeting']
        assert 'show you the garden' in spoken[0][1]  # greeting states the actual plan
        await asyncio.wait_for(show.action_task, 2)
        assert done == ['visit_gardens']  # no phone pose first: the Godot world has no phone
        last = show.autonomy.history[-1]
        assert last['id'] == 'fresh_air' and last['status'] == 'completed'
        assert any(r['kind'] == 'goal_completed' for r in show.vlogger.memory.records)
        # A browser refresh keeps the same process state: no second greeting.
        assert show.started and show.autonomy.stream['greeted']
    asyncio.run(go())


def test_restart_resumes_unfinished_goal_without_replaying_greeting(tmp_path):
    async def go():
        clock = Clock()
        show, done, spoken, _ = make_show()
        show.clock = show.autonomy.clock = clock
        show.enable_persistence(tmp_path / 'session.json')
        show.autonomy.stream = {'id': 'abc123', 'startedAt': clock(), 'greeted': True, 'kind': 'new_stream'}
        show.autonomy.start(GOALS['read'], show.reality.snapshot(show))
        show.checkpoint.save(show)
        clock.t += 90  # quick DEV restart
        again, done2, spoken2, _ = make_show()
        again.clock = again.autonomy.clock = clock
        again.enable_persistence(tmp_path / 'session.json')
        await again.open_stream()
        assert 'stream_greeting' not in [k for k, _ in spoken2]
        assert again.autonomy.stream['kind'] == 'reconnection'
        spec, source, _ = again.autonomy.forced
        assert spec.id == 'read' and source == 'resumed'
    asyncio.run(go())


def test_chat_message_does_not_cancel_running_physical_action():
    show, _, _, sent = make_show()
    show.command_id = 'abc'; show.command_owner = show.task
    async def go():
        show.notice_chat(SimpleNamespace(clean_text='hi mika what are you up to', timestamp=show.clock()))
        await asyncio.sleep(0.01)
    asyncio.run(go())
    assert not any(p.get('type') == 'lifestyle-cancel' for p in sent)


def test_boring_while_idle_switches_to_a_lively_goal_and_says_so_as_intent():
    show, _, _, _ = make_show()
    show.autonomy.start(GOALS['read'], show.reality.snapshot(show))
    show.autonomy.goal['status'] = 'dwelling'
    extra = show.boredom_reaction(SimpleNamespace(timestamp=show.clock()))
    forced = show.autonomy.forced
    assert forced.lively and forced.id != 'read'
    assert show.autonomy.yield_requested == 'viewer_feedback_boring'
    assert 'about to start, not something already done' in extra and 'no asking what they want' in extra


def test_boring_while_busy_keeps_going():
    show, _, _, _ = make_show()
    show.autonomy.start(GOALS['fresh_air'], show.reality.snapshot(show))
    show.autonomy.goal['status'] = 'running'
    extra = show.boredom_reaction(SimpleNamespace(timestamp=show.clock()))
    assert show.autonomy.forced is None and 'keep going' in extra


def test_failed_goal_is_recorded_rested_and_replaced():
    async def go():
        show, done, _, _ = make_show(actions=['casual_phone_chat', 'tour_room', 'show_desk'])
        async def command(action, **args):
            done.append(action)
            if action == 'tour_room': raise RuntimeError('No clear route to anchor')
            return {'ok': True}
        show.command = command
        show.autonomy.start(GOALS['room_tour'], show.reality.snapshot(show))
        await show.pursue_goal()
        last = show.autonomy.history[-1]
        assert last['status'] == 'failed' and 'No clear route' in last['result']
        assert show.autonomy.next_decision_at - show.clock() <= 5
        nxt = show.autonomy.choose(show.reality.snapshot(show))
        assert nxt is not None and nxt.id != 'room_tour'
    asyncio.run(go())


def test_goal_whose_announcement_dies_is_never_left_without_a_runner():
    async def go():
        show, done, _, _ = make_show(actions=['casual_phone_chat', 'tour_room'])
        async def speak(prompt, kind='autonomous', received=None):
            show.clients.clear()  # the stage refreshes mid-announcement
            raise asyncio.CancelledError()
        show.speak = speak
        try:
            await show.begin_goal()
        except asyncio.CancelledError:
            pass
        assert show.autonomy.goal is None
        assert show.autonomy.history[-1]['result'] == 'stage_disconnected_before_start'
    asyncio.run(go())


def test_stall_watchdog_releases_a_goal_without_runner():
    async def go():
        show, _, spoken, _ = make_show(actions=['casual_phone_chat', 'tour_room'])
        show.started = True; show.greeted = True
        show.autonomy.start(GOALS['room_tour'], show.reality.snapshot(show))  # no runner task
        show.next_speech_at = show.clock() + 999; show.presentation_at = show.clock() + 999
        async def stop_soon():
            await asyncio.sleep(.3); show.closed = True
        await asyncio.gather(show.run(), stop_soon())
        assert any(r['event'] == 'autonomy_stall_recovered' for r in show.history)
    asyncio.run(go())


def test_blocked_route_rests_every_goal_needing_that_zone():
    async def go():
        show, done, _, _ = make_show()
        async def command(action, **args):
            if action in ('visit_gardens', 'quiet_outside', 'visit_lantern_retreat', 'go_jogging'):
                raise RuntimeError('No clear route to anchor')
            return {'ok': True}
        show.command = command
        show.autonomy.start(GOALS['fresh_air'], show.reality.snapshot(show))
        await show.pursue_goal()
        assert 'GROUNDS' in show.autonomy.snapshot()['unreachableZones']
        for _ in range(20):
            alt = show.autonomy.choose(show.reality.snapshot(show))
            assert alt.zone != 'GROUNDS', alt.id
    asyncio.run(go())


def test_all_goals_resting_relaxes_cooldowns_instead_of_idling():
    clock = Clock(); a = Autonomy(clock, random.Random(3))
    reality = {'scene': 'HOME', 'availableActions': ['sit_chair', 'show_window']}
    for gid in ('relax', 'window'):
        a.cooldowns[gid] = clock() + 900
    a.history.append({'id': 'window', 'title': '', 'status': 'completed', 'result': '', 'startedAt': 0, 'endedAt': 0, 'source': 'x'})
    spec = a.choose(reality)
    assert spec.id == 'relax' and a.last_decision['cooldownsRelaxed']


def test_atelier_goal_needs_its_executable_action_and_viewers_can_ask_for_it():
    from open_llm_vtuber.room.viewer_intents import classify_viewer
    a = Autonomy(clock=Clock())
    base = {'scene': 'HOME', 'dayPart': 'MORNING'}
    assert 'atelier' not in {s.id for s, _ in a.candidates({**base, 'availableActions': HOME_ACTIONS})}
    with_atelier = {**base, 'availableActions': HOME_ACTIONS + ['visit_atelier']}
    assert 'atelier' in {s.id for s, _ in a.candidates(with_atelier)}
    for message in ('show us your art studio', 'can you go to the atelier', 'take us to your art room'):
        intent = classify_viewer(message)  # a real walk there, either way
        assert intent.action == 'visit_atelier' or (intent.action, intent.arguments) == ('go_to', {'place': 'art_studio'})
    assert classify_viewer('draw something').action == 'draw_doodle'


def test_explore_and_flower_goals_and_intents_need_their_actions():
    from open_llm_vtuber.room.viewer_intents import classify_viewer
    a = Autonomy(clock=Clock())
    base = {'scene': 'HOME', 'dayPart': 'MORNING'}
    ids = {s.id for s, _ in a.candidates({**base, 'availableActions': HOME_ACTIONS})}
    assert 'explore' not in ids and 'flower' not in ids
    ids = {s.id for s, _ in a.candidates({**base, 'availableActions': HOME_ACTIONS + ['explore', 'pick_flower', 'place_flower']})}
    assert 'explore' in ids and 'flower' not in ids  # flower picking is paused (owner decision)
    assert GOALS['flower'].after == ('place_flower',) and GOALS['read'].after == ('return_book',)
    assert classify_viewer('can you pick a flower for us?').action == 'pick_flower'
    assert classify_viewer('go explore the garden').action == 'explore'


def test_relax_goal_sits_without_a_book():
    a = Autonomy(clock=Clock())
    spec = GOALS['relax']
    assert spec.steps == ('sit_chair',) and spec.quiet
    # the Godot world has no bedroom: the reading chair is never one of her own objectives there
    ids = {s.id for s, _ in a.candidates({'scene': 'sanctuary', 'dayPart': 'EVENING', 'availableActions': ['sit_chair']})}
    assert ids == set()
