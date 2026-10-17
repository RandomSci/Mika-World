"""Topic continuity, viewer priority, transport ownership and safe action admission."""
import asyncio
import json
import random
import sys
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from open_llm_vtuber.room.lifestyle import LifestyleShowRunner
from open_llm_vtuber.room.lifestyle_topics import TopicManager

def session():
    async def send(uid,payload):pass
    return SimpleNamespace(_clients={'stage':True},_send=send,trace=lambda *a,**kw:None,director=SimpleNamespace(ready=True),record_success=lambda _:None)

def test_empty_planner_timeout_has_a_reason_and_safe_fallback():
    async def go():
        show=LifestyleShowRunner(session())
        async def planner(state):raise asyncio.TimeoutError()
        show.planner=planner
        assert await show.plan_next()=={}
        failure=show.history[-1]
        assert failure['event']=='planning_failed'
        assert failure['reason'].startswith('TimeoutError:') and failure['timeout_seconds']==8
    asyncio.run(go())

def test_private_change_keeps_viewers_company_without_claiming_park():
    async def go():
        show=LifestyleShowRunner(session());show.register('stage');show.clients['stage']['ready']=True
        show.started=True;show.active_action='change_outfit';show.last_speech_end=0
        show.reality.physical={'scene':'HOME','outfit':'HOME','privateTransition':True}
        show.action_task=asyncio.ensure_future(asyncio.Future());calls=[]
        async def speak(prompt,kind):
            calls.append((prompt,kind));show.closed=True
        show.speak=speak
        await asyncio.wait_for(show.run(),2)
        assert len(calls)==1 and calls[0][1]=='transition_comment'
        assert 'HOME' in calls[0][0] and 'Do not describe undressing' in calls[0][0]
        await show.close()
    asyncio.run(go())

def test_topic_beats_retain_viewer_feedback_and_recent_topic_cooldown():
    now=[1000.0];manager=TopicManager(random.Random(2),lambda:now[0])
    title=manager.start('PHONE_VLOG')['title']
    manager.record('A specific thought.');manager.feedback('My room feels cozy with warm lighting.')
    assert manager.current_topic['title']==title and manager.position_in_topic==1
    assert manager.resuming and manager.snapshot()['viewer_feedback']
    manager.record('Building on your lighting idea.');assert not manager.resuming
    seen={title}
    for _ in range(6):
        next_title=manager.start('PHONE_VLOG')['title'];assert next_title not in seen;seen.add(next_title)
    assert len(manager.previous_topics)==6

def test_unknown_transforms_are_not_commands_and_disconnect_releases_waiter():
    async def go():
        s=session();show=LifestyleShowRunner(s);show.register('stage');show.clients['stage']['ready']=True
        try:await show.command('set_xyz',x=10)
        except ValueError:pass
        else:assert False
        command=asyncio.create_task(show.command('casual_phone_chat'));await asyncio.sleep(0)
        assert len(show.waiters)==1
        show.unregister('stage')
        try:await command
        except ConnectionError:pass
        else:assert False
        assert not show.waiters and show.next_action is None
    asyncio.run(go())

def test_viewer_interrupt_preserves_topic_and_serializes_voice():
    async def go():
        s=session();show=LifestyleShowRunner(s);show.topics.start('PHONE_VLOG');title=show.topics.current_topic['title']
        voice=[];active=[0]
        async def runner(turn,prompt,plan):
            active[0]+=1;assert active[0]==1
            try:
                if turn.kind=='autonomous':await asyncio.sleep(10)
                voice.append(turn.kind);assert plan.message.timestamp==1000;return 'That is an interesting idea.'
            finally:active[0]-=1
        s.director.turn_runner=runner
        show.speech_task=asyncio.create_task(show.speak('ongoing thought'));await asyncio.sleep(0)
        message=SimpleNamespace(timestamp=1000,clean_text='What about lighting?',display_name='viewer')
        show.notice_chat(message)
        plan=SimpleNamespace(message=message,turns=[],id='viewer-1')
        answered=await show.answer_chat(plan,runner)
        assert answered.turns[0].text and voice==['viewer_answer']
        assert show.topics.current_topic['title']==title and show.topics.resuming
        assert show.viewer_pending==0 and show.running_turn is None
        await show.close()
    asyncio.run(go())

def test_action_ack_is_owned_by_target_stage():
    async def go():
        s=session();sent=[]
        async def send(uid,payload):sent.append((uid,payload))
        s._send=send;show=LifestyleShowRunner(s);show.register('stage');show.clients['stage']['ready']=True
        task=asyncio.create_task(show.command('place_phone_for_reading'));await asyncio.sleep(0)
        ident=next(iter(show.waiters))
        show.acknowledge('wrong',{'id':ident,'ok':True});assert not task.done()
        show.acknowledge('stage',{'id':ident,'ok':True,'state':{'placement':'PhonePlace_ChairSide'}})
        assert (await task)['ok'] and not show.waiters
        assert show.cooldowns['place_phone_for_reading']>show.clock()
    asyncio.run(go())

def test_prior_activity_context_does_not_present_current_topic_as_book_contents():
    show=LifestyleShowRunner(session(),rng=random.Random(3))
    show.topics.start('READING');earlier=show.topics.current_topic['title']
    show.topics.record('An imagined debate with the to-do list.')
    show.segment='DESK_TALK';show.topics.start('DESK_TALK')
    show.state={'activity':'place_phone_for_full_body'}
    prompt=show.viewer_prompt(SimpleNamespace(clean_text='What were you reading before the desk?',display_name='viewer'))
    context=json.loads(next(line for line in prompt.splitlines() if line.startswith('{')))
    assert context['completed_segment_topics_oldest_first'][-1]['topic']==earlier
    assert context['completed_segment_topics_oldest_first'][-1]['activity']=='read_book'
    assert context['current_topic']==show.topics.current_topic['title']
    assert context['current_topic']!=earlier and context['book_contents'].startswith('Unknown.')
    assert context['requested_earlier_activity_record']['topic']==earlier

def test_autonomous_loop_survives_child_voice_cancellation_on_python_310():
    async def go():
        s=session();show=LifestyleShowRunner(s);show.register('stage');show.clients['stage']['ready']=True
        show.started=True;show.topics.start(show.segment);attempt=[0]
        async def runner(turn,prompt,plan):
            attempt[0]+=1
            if attempt[0]==1:raise asyncio.CancelledError()
            await asyncio.sleep(100)
        s.director.turn_runner=runner
        show.task=asyncio.create_task(show.run())
        for _ in range(100):
            if attempt[0]>=2:break
            await asyncio.sleep(.005)
        assert attempt[0]>=2 and not any(e['event']=='recovery' for e in show.history)
        await show.close();assert show.task is None or show.task.done()
    asyncio.run(go())


def test_planned_action_reply_cannot_false_refuse_but_real_failure_is_preserved():
    show=LifestyleShowRunner(session(),rng=random.Random(3))
    show.running_turn='viewer_answer'
    show.viewer_ack={'action':'go_jogging','feasible':True,'received':0}
    assert show.guard_speech("Unfortunately, jogging isn't available right now.")=="I'll change and take a jog around the garden."
    show.viewer_ack={'action':'read_book','feasible':True,'received':0}
    assert show.guard_speech('Reading is a visible activity without specific book text.')=="I'll settle in with the book."
    assert show.guard_speech('But I will keep that in mind for later.') is None
    show.viewer_ack={'action':'throw_phone','feasible':False,'received':0}
    assert show.guard_speech('The stunt is unavailable while it cools down.')=='The stunt is unavailable while it cools down.'
    show.viewer_ack={'action':'go_jogging','feasible':True,'received':0}
    show.record('viewer_action_failed',action='go_jogging',reason='blocked')
    assert show.guard_speech('I cannot do that right now.')=='I cannot do that right now.'
