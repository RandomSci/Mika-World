"""Day 3 fixes from the Day 2 live stream (2026-10-18):
- the stage bridge followed ANY new gamescope (a session's offscreen test reached viewers twice);
- Mika's autonomy blocked for 40 minutes once the few objectives the Godot world can do were done this cycle;
- her quiet-moment lines kept returning to dancing (63 of 324 lines) and the dawn sky;
- the Godot world still talked about bedroom / phone-vlog topics."""
import importlib.util
import random
import sys
import types
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'src'))
from open_llm_vtuber.room.autonomy import Autonomy  # noqa: E402
from open_llm_vtuber.room.lifestyle import LifestyleShowRunner  # noqa: E402
from open_llm_vtuber.room import lifestyle_topics  # noqa: E402
from open_llm_vtuber.room.lifestyle_topics import TopicManager  # noqa: E402


class Clock:
    def __init__(self, t=1_000_000.0): self.t = t
    def __call__(self): return self.t


def _bridge():
    """tools/stage_bridge.py with GStreamer stubbed (only its node choice is tested)."""
    gi = types.ModuleType('gi')
    gi.require_version = lambda *a, **k: None
    repo = types.ModuleType('gi.repository')
    repo.Gst = SimpleNamespace(init=lambda *a: None, MessageType=SimpleNamespace(ERROR=1, EOS=2))
    gi.repository = repo
    sys.modules.setdefault('gi', gi)
    sys.modules.setdefault('gi.repository', repo)
    spec = importlib.util.spec_from_file_location('stage_bridge_under_test', ROOT / 'tools' / 'stage_bridge.py')
    mod = importlib.util.module_from_spec(spec)
    saved = sys.argv
    sys.argv = ['stage_bridge.py', '/dev/null']
    try:
        spec.loader.exec_module(mod)
    finally:
        sys.argv = saved
    return mod


def _dump(*nodes):
    """nodes: (serial, client_id, pid)"""
    out = []
    for serial, cid, pid in nodes:
        out.append({'type': 'PipeWire:Interface:Client', 'id': cid, 'info': {'props': {'pipewire.sec.pid': pid}}})
        out.append({'type': 'PipeWire:Interface:Node', 'id': 1000 + serial,
                    'info': {'props': {'node.name': 'gamescope', 'media.class': 'Video/Source', 'object.serial': serial, 'client.id': cid}}})
    return out


def test_bridge_follows_only_the_stage_gamescope():
    b = _bridge()
    cmd = {101: 'gamescope --backend headless -- /home/x/Mika-Live/tools/godot-stage.sh --inner log',
           202: 'gamescope --backend headless -- /home/x/.cache/mika_qa/run/inner.sh'}
    b._cmdline = lambda pid: cmd.get(int(pid), '')
    dump = _dump((28985, 86, 101), (29476, 90, 202))       # the test's gamescope is the NEWER node
    nodes = b.stage_nodes(dump)
    assert [n['info']['props']['object.serial'] for n in nodes] == [28985]
    # a test rig can still bridge its own gamescope by naming it (never while the stream is live)
    assert [n['info']['props']['object.serial'] for n in b.stage_nodes(dump, 'inner.sh')] == [29476]
    # nothing that is not the stage: nothing to follow (the bridge keeps its last frame, never a stranger's)
    assert b.stage_nodes(_dump((29476, 90, 202))) == []


def test_autonomy_revisits_instead_of_blocking_when_the_rest_cannot_run_here():
    # The live state at 04:59: only a few objectives runnable here (the Godot world has no bedroom, so "relax" never
    # counts). Once they are done she must revisit one - never stand blocked for the rest of the five-hour cycle.
    clock = Clock()
    a = Autonomy(clock, random.Random(3))
    reality = {'scene': 'GROUNDS', 'availableActions': ['dance_session', 'dance', 'magic_lesson', 'sit_chair', 'casual_phone_chat']}
    done = []
    for _ in range(2):
        g = a.choose(reality)
        assert g is not None, a.blocking_reason
        a.start(g, reality)
        a.finish('completed')
        done.append(g.id)
        clock.t += 400
    assert 'relax' not in a.pool.remaining()                  # never an objective in the Godot world
    nxt = a.choose(reality)
    assert nxt is not None, a.blocking_reason
    assert nxt.id in done and nxt.id != done[-1] and a.last_decision.get('revisit')
    assert a.blocking_reason is None


def _talker(lines=(), danced_at=None, clock=None):
    clock = clock or Clock()
    t = TopicManager(rng=random.Random(1), clock=clock)
    t.start('PHONE_VLOG')
    for line in lines:
        t.record(line)
    hist = [{'at': danced_at, 'routines': ['step'], 'scores': {'step': 61}}] if danced_at is not None else []
    ns = SimpleNamespace(topics=t, dance_history=hist, clock=clock, THEMES=LifestyleShowRunner.THEMES)
    ns.danced_recently = types.MethodType(LifestyleShowRunner.danced_recently, ns)
    return ns


def test_dance_is_a_seed_only_right_after_a_real_dance(monkeypatch):
    monkeypatch.setenv('VR_WORLD_RENDERER', 'godot')
    clock = Clock()
    obj = _talker(clock=clock)
    seeds = LifestyleShowRunner.idle_seeds(obj)
    assert not any('danc' in s for s in seeds)
    assert any('Luna' in s for s in seeds)
    obj = _talker(danced_at=clock.t - 120, clock=clock)
    assert any('danc' in s for s in LifestyleShowRunner.idle_seeds(obj))
    obj = _talker(danced_at=clock.t - 3600, clock=clock)
    assert not any('danc' in s for s in LifestyleShowRunner.idle_seeds(obj))


def test_tired_themes_survive_topic_changes():
    obj = _talker(lines=['Step hip-hop still haunts me.', 'The dawn is taking its time.', 'Macarena is cursed, honestly.'])
    obj.topics.start('PHONE_VLOG')          # a topic change used to wipe the memory of what she said
    tired = LifestyleShowRunner.tired_themes(obj)
    assert tired == ['dancing or dance routines']
    obj.topics.record('Third dawn check, the sky is a no-show.')
    assert 'the sky, the stars or the dawn' in LifestyleShowRunner.tired_themes(obj)


def test_godot_world_topics_are_not_bedroom_vlog(monkeypatch):
    t = TopicManager(rng=random.Random(2), clock=Clock())
    monkeypatch.setenv('VR_WORLD_RENDERER', 'godot')
    titles = [title for _, title in t.available('PHONE_VLOG')]
    assert titles and not any(w in ' '.join(titles).lower() for w in ('reading corner', 'household gadget', 'tour of the room'))
    assert set(lifestyle_topics.GODOT_SEEDS) <= set(lifestyle_topics.SEEDS)


# ---------------------------------------------------------------- Godot world: no phone-vlog leftovers
def _show(actions):
    from types import SimpleNamespace as NS
    sent, done = [], []
    async def send(uid, payload): sent.append(payload)
    session = NS(_clients={'stage': True}, _send=send, trace=lambda *a, **k: None, director=NS(ready=True),
                 record_success=lambda _: None, state=NS(characters={}))
    show = LifestyleShowRunner(session, rng=random.Random(5))
    show.register('stage'); show.clients['stage']['ready'] = True
    show.reality.physical = {'scene': 'GROUNDS', 'availableActions': list(actions)}
    async def command(action, **args):
        done.append(action); return {'ok': True, 'state': {}}
    async def speak(prompt, kind='autonomous', received=None): return 'Okay.'
    show.command, show.speak = command, speak
    return show, done


def test_godot_world_sends_no_phone_actions(monkeypatch):
    import asyncio as aio
    monkeypatch.setenv('VR_WORLD_RENDERER', 'godot')
    show, done = _show(['magic_lesson', 'dance_session', 'explore', 'casual_phone_chat', 'presentation_beat', 'sit_chair'])
    aio.run(show.open_stream())
    aio.run(show.change_segment())
    assert 'casual_phone_chat' not in done and 'presentation_beat' not in done, done
    monkeypatch.setenv('VR_WORLD_RENDERER', '')          # whatever the environment says: the Godot world is the only one
    show2, done2 = _show(['casual_phone_chat', 'read_book', 'sit_chair'])
    aio.run(show2.open_stream())
    assert 'casual_phone_chat' not in done2


def test_godot_world_drops_home_only_objectives(monkeypatch):
    from open_llm_vtuber.room.activity_registry import verified_ids
    reality = {'scene': 'GROUNDS', 'availableActions': ['sit_chair', 'dance_session', 'magic_lesson']}
    monkeypatch.setenv('VR_WORLD_RENDERER', '')
    assert 'relax' not in verified_ids(reality)          # no bedroom in the Godot world, whatever the environment says


def test_gallery_promo_is_off_in_the_godot_world(monkeypatch):
    from open_llm_vtuber.publishing.promo import GalleryPromoter as P
    monkeypatch.delenv('VR_GALLERY_PROMO', raising=False)
    assert not P.enabled()                               # off unless asked for
    monkeypatch.setenv('VR_GALLERY_PROMO', '1')
    assert P.enabled()
