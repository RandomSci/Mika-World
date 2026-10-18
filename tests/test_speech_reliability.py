"""Ordered sentence delivery and reconnect/fast-ack paths, with no network voices."""
import asyncio
import json
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from open_llm_vtuber.message_handler import MessageHandler, message_handler
from open_llm_vtuber.conversations.tts_manager import TTSTaskManager
from open_llm_vtuber.conversations.conversation_utils import finalize_conversation_turn
from open_llm_vtuber.room.latency import TurnLatency, observe_audio


def test_completion_follows_ordered_audio_and_immediate_ack_is_not_lost():
    async def go():
        manager=TTSTaskManager();sent=[]
        async def send(payload):
            data=json.loads(payload);sent.append(data)
            if data['type']=='backend-synth-complete':
                message_handler.handle_message('test-fast',{'type':'frontend-playback-complete'})
        manager._sequence_counter=2
        manager._sender_task=asyncio.create_task(manager._process_payload_queue(send))
        async def produce():
            await manager._payload_queue.put(({'type':'audio','index':1},1))
            await asyncio.sleep(.01)
            await manager._payload_queue.put(({'type':'audio','index':0},0))
        manager.task_list=[asyncio.create_task(produce())]
        try:
            await asyncio.wait_for(finalize_conversation_turn(manager,send,'test-fast'),.5)
            assert [x.get('index') for x in sent[:2]]==[0,1]
            assert sum(x['type']=='backend-synth-complete' for x in sent)==1
            assert sent[-1]['text']=='conversation-chain-end'
        finally:manager.clear();message_handler.cleanup_client('test-fast')
    asyncio.run(go())


def test_delivery_failure_surfaces_and_disconnect_releases_waiter():
    async def go():
        manager=TTSTaskManager()
        async def closed(payload):raise ConnectionError('closed test socket')
        manager._sender_task=asyncio.create_task(manager._process_payload_queue(closed))
        await manager._payload_queue.put(({'type':'audio'},0))
        try:
            try:await asyncio.wait_for(manager.flush(),.5)
            except ConnectionError:pass
            else:assert False,'failed sender must propagate'
        finally:manager.clear()
        handler=MessageHandler()
        waiter=asyncio.create_task(handler.wait_for_response('old-stage','frontend-playback-complete'))
        await asyncio.sleep(0);handler.cleanup_client('old-stage')
        assert await asyncio.wait_for(waiter,.1) is None
        assert 'old-stage' not in handler._response_events
        assert 'old-stage' not in handler._response_data
    asyncio.run(go())


def test_latency_uses_first_audible_chunk_and_reports_playback_errors():
    trace=TurnLatency('test','mika',received=10)
    trace.events.update(response_start=10100,response_complete=11000)
    trace.segments[0]={'tts_start':10400,'tts_complete':10700}
    observe_audio({'type':'audio-play-start','trace_id':trace.id,'received_at_ms':10800,'at_ms':10820})
    observe_audio({'type':'audio-play-start','trace_id':trace.id,'received_at_ms':12000,'at_ms':12050})
    observe_audio({'type':'audio-play-error','trace_id':trace.id,'reason':'playback_blocked'})
    s=trace.summary()
    assert s['llm_ms']==900 and s['tts_ms']==300 and s['queue_ms']==20
    assert s['total_to_first_audio_ms']==820
    assert s['errors']==['browser_playback_blocked']


def test_runtime_selects_reconnected_stage_instead_of_bootstrap_socket(monkeypatch):
    from types import SimpleNamespace
    from tests.test_llm_errors_stay_off_stream import Stage
    import open_llm_vtuber.conversations.single_conversation as sc
    stage=Stage();seen=[];sent=[]
    async def old(payload):raise RuntimeError('closed bootstrap socket')
    async def current(payload):sent.append(json.loads(payload))
    async def conversation(context,websocket_send,client_uid,**kwargs):
        seen.append(client_uid)
        await websocket_send(json.dumps({'type':'audio','audio':'test','display_text':{'text':'Hi'}}))
        return 'Hi'
    monkeypatch.setattr(sc,'process_single_conversation',conversation)
    stage.runtimes.send=old;stage.runtimes._live2d=lambda cid:None
    stage.session.voices.engine=lambda cid:None
    stage.session._clients['reconnected']=current
    turn=SimpleNamespace(speaker='mika',kind='chat',addressee='',intent=SimpleNamespace(action=None))
    plan=SimpleNamespace(id='reconnect',timing=None,message=SimpleNamespace(timestamp=0))
    assert asyncio.run(stage.runtimes.run_turn(turn,'hello',plan))=='Hi'
    assert seen==['reconnected'] and any(x['type']=='audio' for x in sent)


def test_losing_stage_three_times_does_not_cool_down_working_voice():
    import time
    from tests.test_character_ownership import Room
    from open_llm_vtuber.room.latency import RoomTransportError
    from open_llm_vtuber.room.live_message import LiveMessage
    room=Room();session=room.session
    async def closed(*args):raise RoomTransportError('stage went away')
    session.director.turn_runner=closed
    async def go():
        for i in range(3):
            plan=session.director.plan(LiveMessage(platform='dev',message_id=str(i),username='@test',text='mika hello',timestamp=time.time(),author_id='test'))
            await session.director.run(plan)
            assert plan.turns[0].skipped=='transport_disconnected'
        assert session.state.characters['mika'].failures==0
        assert not session.state.characters['mika'].cooldown_until
    asyncio.run(go())
