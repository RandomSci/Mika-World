"""Bounded DEV speech tracing; sentence streaming and the configured voice stay intact."""
from collections import OrderedDict
import time
import uuid
from loguru import logger

TRACES = OrderedDict()

class RoomTransportError(ConnectionError):
    category = 'transport_disconnected'

class TurnLatency:
    def __init__(self, interaction, character, received=None, owner=None):
        self.id = uuid.uuid4().hex
        self.interaction, self.character, self.owner = interaction, character, owner
        self.events = {'message_received': (received or time.time()) * 1000}
        self.segments = {}
        self.errors = []
        TRACES[self.id] = self
        while len(TRACES) > 64:
            TRACES.popitem(last=False)

    def mark(self, name, at=None):
        self.events.setdefault(name, at if at is not None else time.time() * 1000)
        alias={'response_start':'llm_started','response_complete':'llm_finished','tts_start':'tts_started','tts_complete':'tts_finished','audio_received':'browser_audio_requested','audio_start':'browser_audio_started'}.get(name)
        if alias:self.events.setdefault(alias,self.events[name])

    def start_tts(self, sequence):
        self.mark('tts_start')
        self.segments[sequence] = {'tts_start': time.time() * 1000}

    def end_tts(self, sequence, error=None):
        self.mark('tts_complete')
        self.segments.setdefault(sequence, {})['tts_complete'] = time.time() * 1000
        if error:
            self.fail(error)

    def fail(self, category):
        if category not in self.errors:
            self.errors.append(category)

    def payload(self, sequence):
        return {'trace_id': self.id, 'sequence': sequence, 'events': dict(self.events),
                'segment': dict(self.segments.get(sequence, {})), 'errors': list(self.errors)}

    def summary(self):
        e = self.events
        def span(a, b):
            return round(e[b] - e[a], 1) if a in e and b in e else None
        first = self.segments.get(0, {})
        return {'trace_id': self.id, 'interaction': self.interaction, 'character': self.character,
                'events': dict(e), 'errors': list(self.errors),
                'llm_ms': span('response_start', 'response_complete'),
                'tts_ms': round(first['tts_complete'] - first['tts_start'], 1) if 'tts_complete' in first else None,
                'queue_ms': span('audio_received', 'audio_start'),
                'total_to_first_audio_ms': span('message_received', 'audio_start'),
                'browser_ack_after_audio_ms':span('audio_start','browser_audio_acknowledged'),
                'diagnostic_write_ms':getattr(self,'diagnostic_write_ms',None)}

    def log(self):
        started=time.perf_counter()
        s = self.summary()
        logger.info('Mika speech latency | LLM: {} ms | TTS: {} ms | queue: {} ms | total-to-first-audio: {} ms | errors: {}',
                    s['llm_ms'], s['tts_ms'], s['queue_ms'], s['total_to_first_audio_ms'], ','.join(self.errors) or 'none')
        self.diagnostic_write_ms=round((time.perf_counter()-started)*1000,3)

def observe_audio(message):
    trace = TRACES.get(message.get('trace_id'))
    if not trace:
        return
    kind = message.get('type')
    if kind == 'audio-play-start':
        trace.mark('browser_audio_acknowledged')
        trace.mark('audio_received', message.get('received_at_ms'))
        trace.mark('audio_start', message.get('at_ms'))
        trace.log()
    elif kind == 'audio-play-end':
        # End is the most recent chunk, start is the first audible chunk.
        trace.events['audio_end'] = message.get('at_ms') or time.time() * 1000
    elif kind == 'audio-play-error':
        trace.fail('browser_' + str(message.get('reason') or 'playback_failure'))
        trace.log()

def recent(owner=None):
    return [t.summary() for t in TRACES.values() if owner is None or t.owner == owner][-20:]
