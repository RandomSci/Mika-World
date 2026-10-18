"""Character runtimes: one agent (persona, own LLM client) per room character.

A turn reuses the proven single-character pipeline unchanged
(``process_single_conversation``: streamed LLM, sentence splitting, parallel
TTS, ordered audio, wait for playback). Only the context differs: the
character's own agent, voice and emotion map, and every audio payload is
tagged with the character id so the right model lip syncs.

Agents are created lazily on a character's first turn. Creating an agent
makes no API call; only a turn does.
"""

from __future__ import annotations

import asyncio
import json
import time
from types import SimpleNamespace
from typing import TYPE_CHECKING, Any

from loguru import logger

from . import events as ev
from .prompting import strip_wrapping_quotes, system_prompt

if TYPE_CHECKING:  # pragma: no cover
    from .director import InteractionPlan, Turn
    from .session import RoomSession


LLM_ERROR_PREFIX = "Error calling the chat endpoint"


def is_llm_error_text(text: Any) -> bool:
    return isinstance(text, str) and text.strip().startswith(LLM_ERROR_PREFIX)


class RoomRuntimes:
    def __init__(
        self, session: "RoomSession", base_context: Any, client_uid: str, send
    ):
        self.session = session
        self.base = base_context
        self.client_uid = client_uid
        self.send = send
        self._agents: dict[str, Any] = {}
        self._models: dict[str, Any] = {}
        self.errors: dict[str, str] = {}

    def retarget(self, client_uid: str, send) -> None:
        self.client_uid = client_uid
        self.send = send

    # ------------------------------------------------------------------
    def _live2d(self, character_id: str):
        if character_id in self._models:
            return self._models[character_id]
        from ..live2d_model import Live2dModel

        profile = self.session.room.get(character_id)
        model = Live2dModel(profile.model)
        # Emotion tags map to the character's profile emotions; the room page
        # plays them through its registry (emotion_mode "profile").
        model.emo_map = profile.emotion_index_map()
        model.emo_str = " ".join(f"[{k}]," for k in model.emo_map)
        self._models[character_id] = model
        return model

    def agent(self, character_id: str):
        if character_id in self._agents:
            return self._agents[character_id]
        from ..agent.agent_factory import AgentFactory

        profile = self.session.room.get(character_id)
        base_agent = self.base.character_config.agent_config
        settings = base_agent.agent_settings.model_dump()
        memory = dict(settings.get("basic_memory_agent") or {})
        memory["use_mcpp"] = False  # viewer text never drives tools in the room
        settings["basic_memory_agent"] = memory
        try:
            agent = AgentFactory.create_agent(
                conversation_agent_choice="basic_memory_agent",
                agent_settings=settings,
                llm_configs=base_agent.llm_configs.model_dump(),
                system_prompt=system_prompt(profile, self.session.room),
                live2d_model=self._live2d(character_id),
                tts_preprocessor_config=self.base.character_config.tts_preprocessor_config,
                character_avatar="",
                system_config=self.base.system_config.model_dump(),
                tool_manager=None,
                tool_executor=None,
                mcp_prompt_string="",
            )
        except Exception as exc:
            self.errors[character_id] = str(exc)[:200]
            logger.error(f"VR Room: agent for {character_id} unavailable: {exc}")
            agent = None
        self._agents[character_id] = agent
        return agent

    async def _complete(self, llm, messages: list[dict[str, Any]]) -> str:
        """One completion as plain text, whatever shape the client streams."""
        try:
            stream = llm.chat_completion(messages)
        except TypeError:
            stream = llm.chat_completion(messages=messages)
        if asyncio.iscoroutine(stream):
            stream = await stream
        if isinstance(stream, str):
            return stream
        chunks: list[str] = []

        def take(chunk: Any) -> None:
            if isinstance(chunk, str):
                chunks.append(chunk)
                return
            if not isinstance(chunk, dict):
                return
            value = chunk.get("text") or chunk.get("content")
            if isinstance(value, str):
                chunks.append(value)
                return
            for choice in chunk.get("choices") or []:
                try:
                    value = (choice.get("delta") or {}).get("content") or choice.get(
                        "text"
                    )
                except AttributeError:
                    value = None
                if isinstance(value, str):
                    chunks.append(value)

        if hasattr(stream, "__aiter__"):
            async for chunk in stream:
                take(chunk)
        elif hasattr(stream, "__iter__"):
            for chunk in stream:
                take(chunk)
        return "".join(chunks)

    async def run_turn(self, turn: "Turn", prompt: str, plan: "InteractionPlan") -> str:
        from ..conversations.single_conversation import process_single_conversation

        session = self.session
        cid = turn.speaker
        profile = session.room.get(cid)
        agent = self.agent(cid)
        engine = session.voices.engine(cid)
        if not profile or agent is None:
            return ""
        lifestyle_mode=session.lifestyle.enabled and cid=='mika'
        if bool(getattr(agent,'_mika_lifestyle_mode',False))!=lifestyle_mode and hasattr(agent,'set_system'):
            from .lifestyle import lifestyle_system_prompt
            agent.set_system(lifestyle_system_prompt(profile) if lifestyle_mode else system_prompt(profile,session.room))
            agent._mika_lifestyle_mode=lifestyle_mode
        context = SimpleNamespace(
            agent_engine=agent,
            tts_engine=engine,
            live2d_model=self._live2d(cid),
            translate_engine=None,
            asr_engine=None,
            history_uid=None,
            speech_guard=session.lifestyle.guard_speech if lifestyle_mode else None,
            character_config=SimpleNamespace(
                character_name=profile.name,
                avatar="",
                human_name="viewer",
                conf_uid=f"room-{cid}",
            ),
        )
        started = time.time()
        state = {"first": None, "audio": 0, "silent": 0}
        # A DEV page can reconnect while the runtime/agent survives. Select the
        # current registered transport for each turn, never the bootstrap socket.
        target_uid, send = session.speech_target() or (self.client_uid, self.send)
        from .latency import TurnLatency, RoomTransportError
        latency = TurnLatency(plan.id, cid, plan.message.timestamp, id(session))
        if session.lifestyle and turn.kind=='viewer_answer':
            for event in list(session.lifestyle.pipeline_events)[-6:]:
                if event['event'] in ('intent_classified','action_started') and event['at']>=plan.message.timestamp:
                    latency.mark(event['event'],event['at']*1000)
        character = session.state.characters.get(cid)

        async def tagged_send(payload: str) -> None:
            if payload.startswith('{"type": "audio"'):
                data = json.loads(payload)
                shown = data.get("display_text")
                if is_llm_error_text(
                    (shown or {}).get("text") if isinstance(shown, dict) else ""
                ):
                    # Open-LLM-VTuber speaks its own error messages. Never on
                    # stream: drop the line, log it, stay quiet this turn.
                    state["llm_error"] = True
                    latency.fail("llm_failed")
                    logger.error(
                        f"VR Room: {cid}'s LLM call failed; the error was not "
                        "spoken. The real reason is in the 'LLM API' log line."
                    )
                    return
                if isinstance(shown, dict) and shown.get("text"):
                    shown["text"] = strip_wrapping_quotes(str(shown["text"]))
                data["character"] = cid
                data["emotion_mode"] = "profile"
                if data.get("audio"):
                    latency.mark('browser_audio_requested')
                    state["audio"] += 1
                else:
                    state["silent"] += 1
                if state["first"] is None:
                    state["first"] = time.time()
                    timing = getattr(plan, "timing", None)
                    if timing is not None and not timing.first_audio_at:
                        from ..vr_agent.state import VRAgentState, runtime

                        timing.first_audio_at = state["first"]
                        runtime.set(VRAgentState.SPEAKING, plan.id)
                    session.trace(
                        "character_audio_started",
                        interaction=plan.id,
                        character=cid,
                        after_s=round(state["first"] - started, 2),
                        chat_to_voice_s=round(
                            state["first"] - plan.message.timestamp, 2
                        )
                        if plan.message.timestamp
                        else None,
                    )
                    if character:
                        character.speaking = True
                    seconds = min(
                        20.0,
                        2.0
                        + len(str((data.get("display_text") or {}).get("text", "")))
                        * 0.07,
                    )
                    ops = session.emit(
                        ev.SPEECH_STARTED,
                        character=cid,
                        addressee=turn.addressee,
                        seconds=seconds,
                    )
                    if turn.intent.action:
                        ops += session.play(cid, turn.intent.action.name)
                    await session.push(ops)
                payload = json.dumps(data)
                await session.mirror_speech(target_uid, data)
            try:
                await send(payload)
            except (RuntimeError, ConnectionError) as exc:
                latency.fail('transport_disconnected')
                raise RoomTransportError('The stage disconnected during this reply') from exc

        metadata = {
            "source": "youtube_live",  # no "Thinking..." text on stream
            "from_name": "viewer",
            "skip_history": True,
            "skip_memory": True,
            "history_limit": -1,  # the prompt carries the short room context
        }
        session.trace(
            "character_llm_started", interaction=plan.id, character=cid, kind=turn.kind
        )
        try:
            text = await process_single_conversation(
                context=context,
                websocket_send=tagged_send,
                client_uid=target_uid,
                user_input=prompt,
                images=None,
                metadata=metadata,
                latency=latency,
            )
        except asyncio.CancelledError:
            latency.fail("cancelled")
            raise
        except Exception:
            if not latency.errors:
                latency.fail("response_pipeline_failed")
            raise
        finally:
            if character:
                character.speaking = False
                character.spoken_turns += 1
            latency.log()
            await session.push(session.emit(ev.SPEECH_ENDED, character=cid))
        text = strip_wrapping_quotes(" ".join(str(text or "").split()))
        if state.get("llm_error") or is_llm_error_text(text):
            session.record_failure(cid, "llm call failed")
            text = ""
        if text and state["audio"] == 0 and engine is not None:
            latency.fail("tts_produced_no_audio")
            session.record_failure(cid, "tts produced no audio")
            if str(plan.id).startswith('show-'):raise RuntimeError('tts_produced_no_audio')
        session.trace(
            "character_turn_finished",
            interaction=plan.id,
            character=cid,
            seconds=round(time.time() - started, 2),
            audio_chunks=state["audio"],
            spoken=bool(text),
        )
        if str(plan.id).startswith('show-') and state['audio'] and 'audio_start' not in latency.events:
            latency.fail('browser_no_audible_playback');raise RuntimeError('browser_no_audible_playback: '+','.join(latency.errors))
        if character and text:
            character.recent_dialogue.append(text[:200])
        return text

    async def plan_lifestyle(self, state):
        from .lifestyle import ACTIONS
        agent=self.agent('mika')
        llm=getattr(agent,'_llm',None)
        if llm is None:return {}
        prompt='Choose a fresh angle for this virtual lifestyle stream and optionally one safe semantic action. Return JSON only: {"segment":"one offered segment", "topic":"exact offered topic title", "angle":"a concrete angle on that topic", "action":"approved name", "mood":"calm/friendly/amused"}. Use only planning_options for segment/topic; favor a new location when staleness is high. Do not output transforms, coordinates, bones, tools or financial guarantees. Approved actions: '+', '.join(sorted(ACTIONS))
        reply=await self._complete(llm,[{'role':'system','content':prompt},{'role':'user','content':json.dumps(state,ensure_ascii=False)}])
        try:
            value=json.loads(reply.strip().removeprefix('```json').removesuffix('```').strip())
            return {k:str(value.get(k,''))[:180] for k in ('segment','topic','angle','action','mood')}
        except (ValueError,AttributeError):return {}

    def describe(self) -> dict[str, Any]:
        return {
            cid: {
                "agent": cid in self._agents and self._agents[cid] is not None,
                "error": self.errors.get(cid),
            }
            for cid in self.session.state.characters
        }
