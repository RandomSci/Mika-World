import asyncio
import json
import os
import re
import uuid
from datetime import datetime
from typing import List, Optional, Dict
from loguru import logger

from ..agent.output_types import DisplayText, Actions
from ..live2d_model import Live2dModel
from ..tts.tts_interface import TTSInterface
from ..utils.stream_audio import prepare_audio_payload
from .types import WebSocketSend

CLAUSE_MIN_CHARS = 18
_DASHES = re.compile(r"\s*[\u2014\u2013\u2015\u2012]\s*")


def no_dashes(text: str) -> str:
    """Public speech and captions never contain em or en dashes."""
    return _DASHES.sub(", ", text or "").replace(" ,", ",") if text else text


def clause_chunks(text: str, first_limit) -> List[str]:
    """Split a long sentence at clause punctuation into growing chunks.

    For voices slower than playback by a fixed factor (local Kokoro on the CPU
    runs at ~0.35x real time): each chunk is ready before the previous one has
    finished playing, so a long sentence after a short one leaves no silence.
    Text is never cut inside a clause, and short sentences stay whole.
    """
    if not isinstance(first_limit, int) or first_limit <= 0 or len(text) <= first_limit * 1.3:
        return [text]
    parts = [p for p in re.split(r"(?<=[,;:\u2013\u2014])\s+", text.strip()) if p]
    chunks: List[str] = []
    limit, current = first_limit, ""
    for part in parts:
        if current and len(current) + 1 + len(part) > limit and len(current) >= CLAUSE_MIN_CHARS:
            chunks.append(current)
            limit = max(limit, int(len(current) * 2.5))
            current = part
        else:
            current = f"{current} {part}".strip()
    chunks.append(current)
    if len(chunks) > 1 and len(chunks[-1]) < CLAUSE_MIN_CHARS:
        chunks[-2] = f"{chunks[-2]} {chunks.pop()}"
    return chunks


class SingleChunk:
    """The same engine, without clause chunking (a chunk is not split again)."""

    clause_chunk_chars = None

    def __init__(self, engine):
        self._engine = engine

    def __getattr__(self, name):
        return getattr(self._engine, name)


def _speech_debug() -> bool:
    return os.environ.get("VR_SPEECH_DEBUG", "1").strip().lower() not in ("0", "false", "off", "no")


class TTSTaskManager:
    """Manages TTS tasks and ensures ordered delivery to frontend while allowing parallel TTS generation"""

    def __init__(self, latency=None) -> None:
        self.latency = latency
        self.audio_seconds = 0.0
        self.task_list: List[asyncio.Task] = []
        self._lock = asyncio.Lock()
        # Queue to store ordered payloads
        self._payload_queue: asyncio.Queue[Dict] = asyncio.Queue()
        # Task to handle sending payloads in order
        self._sender_task: Optional[asyncio.Task] = None
        # Counter for maintaining order
        self._sequence_counter = 0
        self._next_sequence_to_send = 0

    async def speak(
        self,
        tts_text: str,
        display_text: DisplayText,
        actions: Optional[Actions],
        live2d_model: Live2dModel,
        tts_engine: TTSInterface,
        websocket_send: WebSocketSend,
    ) -> None:
        """
        Queue a TTS task while maintaining order of delivery.

        Args:
            tts_text: Text to synthesize
            display_text: Text to display in UI
            actions: Live2D model actions
            live2d_model: Live2D model instance
            tts_engine: TTS engine instance
            websocket_send: WebSocket send function
        """
        tts_text = no_dashes(tts_text)
        if isinstance(display_text, DisplayText) and display_text.text:
            display_text = DisplayText(text=no_dashes(display_text.text), name=display_text.name, avatar=display_text.avatar)
        if len(re.sub(r'[\s.,!?，。！？\'"』」）】\s]+', "", tts_text)) == 0:
            logger.debug("Empty TTS text, sending silent display payload")
            # Get current sequence number for silent payload
            current_sequence = self._sequence_counter
            self._sequence_counter += 1

            # Start sender task if not running
            if not self._sender_task or self._sender_task.done():
                self._sender_task = asyncio.create_task(
                    self._process_payload_queue(websocket_send)
                )

            await self._send_silent_payload(display_text, actions, current_sequence)
            return

        chunks = clause_chunks(tts_text, getattr(tts_engine, "clause_chunk_chars", None))
        if len(chunks) > 1:
            # Each clause is its own ordered payload: caption, audio and lip
            # sync follow it; actions (expressions) belong to the first one.
            for index, chunk in enumerate(chunks):
                await self.speak(
                    tts_text=chunk,
                    display_text=DisplayText(text=chunk, name=display_text.name, avatar=display_text.avatar)
                    if isinstance(display_text, DisplayText)
                    else display_text,
                    actions=actions if index == 0 else None,
                    live2d_model=live2d_model,
                    tts_engine=SingleChunk(tts_engine),
                    websocket_send=websocket_send,
                )
            return

        logger.debug(
            f"🏃Queuing TTS task for: '''{tts_text}''' (by {display_text.name})"
        )
        if _speech_debug():
            logger.warning(
                "SPEECH_DIAG tts request queued "
                f"speaker={display_text.name} chars={len(tts_text)} engine={type(tts_engine).__module__}.{type(tts_engine).__name__}"
            )

        # Get current sequence number
        current_sequence = self._sequence_counter
        self._sequence_counter += 1

        # Start sender task if not running
        if not self._sender_task or self._sender_task.done():
            self._sender_task = asyncio.create_task(
                self._process_payload_queue(websocket_send)
            )

        # Create and queue the TTS task
        task = asyncio.create_task(
            self._process_tts(
                tts_text=tts_text,
                display_text=display_text,
                actions=actions,
                live2d_model=live2d_model,
                tts_engine=tts_engine,
                sequence_number=current_sequence,
            )
        )
        self.task_list.append(task)

    async def _process_payload_queue(self, websocket_send: WebSocketSend) -> None:
        """
        Process and send payloads in correct order.
        Runs continuously until all payloads are processed.
        """
        buffered_payloads: Dict[int, Dict] = {}

        while True:
            try:
                # Get payload from queue
                payload, sequence_number = await self._payload_queue.get()
                buffered_payloads[sequence_number] = payload

                # Send payloads in order
                while self._next_sequence_to_send in buffered_payloads:
                    next_payload = buffered_payloads.pop(self._next_sequence_to_send)
                    if _speech_debug():
                        audio = next_payload.get("audio")
                        logger.warning(
                            "SPEECH_DIAG websocket audio send "
                            f"seq={self._next_sequence_to_send} type={next_payload.get('type')} "
                            f"audio_chars={len(audio) if isinstance(audio, str) else 0} "
                            f"volumes={len(next_payload.get('volumes') or [])} "
                            f"slice_ms={next_payload.get('slice_length')}"
                        )
                    self.audio_seconds += len(next_payload.get('volumes') or []) * float(next_payload.get('slice_length') or 20) / 1000
                    await websocket_send(json.dumps(next_payload))
                    self._next_sequence_to_send += 1

                self._payload_queue.task_done()

            except asyncio.CancelledError:
                break

    async def _send_silent_payload(
        self,
        display_text: DisplayText,
        actions: Optional[Actions],
        sequence_number: int,
    ) -> None:
        """Queue a silent audio payload"""
        audio_payload = prepare_audio_payload(
            audio_path=None,
            display_text=display_text,
            actions=actions,
        )
        await self._payload_queue.put((audio_payload, sequence_number))

    async def _process_tts(
        self,
        tts_text: str,
        display_text: DisplayText,
        actions: Optional[Actions],
        live2d_model: Live2dModel,
        tts_engine: TTSInterface,
        sequence_number: int,
    ) -> None:
        """Process TTS generation and queue the result for ordered delivery"""
        audio_file_path = None
        if self.latency:
            self.latency.start_tts(sequence_number)
        try:
            if _speech_debug():
                logger.warning(f"SPEECH_DIAG tts synthesis begin seq={sequence_number} chars={len(tts_text)}")
            audio_file_path = await asyncio.wait_for(self._generate_audio(tts_engine, tts_text), timeout=30)
            if not audio_file_path:
                raise RuntimeError('TTS returned no audio file')
            if _speech_debug():
                try:
                    size = os.path.getsize(str(audio_file_path))
                except Exception:
                    size = -1
                logger.warning(f"SPEECH_DIAG tts synthesis result seq={sequence_number} path={audio_file_path} bytes={size}")
            payload = prepare_audio_payload(
                audio_path=audio_file_path,
                display_text=display_text,
                actions=actions,
            )
            if self.latency:
                self.latency.end_tts(sequence_number)
                payload['speech_trace'] = self.latency.payload(sequence_number)
            # Queue the payload with its sequence number
            await self._payload_queue.put((payload, sequence_number))

        except Exception as e:
            logger.error(f"Error preparing audio payload: {e}")
            # Queue silent payload for error case
            payload = prepare_audio_payload(
                audio_path=None,
                display_text=display_text,
                actions=actions,
            )
            if self.latency:
                self.latency.end_tts(sequence_number, 'tts_timeout' if isinstance(e, asyncio.TimeoutError) else 'tts_generation_failed')
                payload['speech_trace'] = self.latency.payload(sequence_number)
            payload['audio_error'] = 'tts_timeout' if isinstance(e, asyncio.TimeoutError) else 'tts_generation_failed'
            await self._payload_queue.put((payload, sequence_number))

        finally:
            if audio_file_path:
                tts_engine.remove_file(audio_file_path)
                logger.debug("Audio cache file cleaned.")

    async def _generate_audio(self, tts_engine: TTSInterface, text: str) -> str:
        """Generate audio file from text"""
        from ..vr_agent.usage import usage

        usage.record_tts(getattr(tts_engine, "_vr_usage_source", None) or "tts_manager")
        logger.debug(f"🏃Generating audio for '''{text}'''...")
        if _speech_debug():
            logger.warning(f"SPEECH_DIAG tts engine call begin engine={type(tts_engine).__name__} chars={len(text)}")
        return await tts_engine.async_generate_audio(
            text=text,
            file_name_no_ext=f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{str(uuid.uuid4())[:8]}",
        )

    async def flush(self) -> None:
        """Wait for generation AND ordered delivery; surface a failed sender."""
        if self.task_list:
            await asyncio.gather(*self.task_list)
        if not self._sender_task:
            return
        joined = asyncio.create_task(self._payload_queue.join())
        try:
            done, _ = await asyncio.wait({joined, self._sender_task}, timeout=10,
                                         return_when=asyncio.FIRST_COMPLETED)
            if self._sender_task in done:
                await self._sender_task
            if joined not in done:
                raise TimeoutError('Ordered audio delivery did not finish')
        finally:
            if not joined.done():
                joined.cancel()

    def clear(self) -> None:
        """Clear all pending tasks and reset state"""
        for task in self.task_list:
            if not task.done():
                task.cancel()
        self.task_list.clear()
        if self._sender_task:
            self._sender_task.cancel()
        self._sequence_counter = 0
        self._next_sequence_to_send = 0
        # Create a new queue to clear any pending items
        self._payload_queue = asyncio.Queue()
