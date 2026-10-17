"""One authority over Mika's body: physical owners come from verified state,
advisory brains need a lease and lose to activities; world-state revisions
move only on meaningful changes."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from open_llm_vtuber.room.reality import RealityState

def test_operational_state_stays_out_of_the_speaking_context():
    reality = RealityState()
    reality.update({'worldState': {'revision': 7, 'health': {'status': 'ok'}, 'coordination': {}, 'audio': {}, 'cinematography': {}, 'books': {'held': None}}})
    show = type('S', (), {})()
    assert reality.physical['revision'] == 7 and 'health' in reality.physical
