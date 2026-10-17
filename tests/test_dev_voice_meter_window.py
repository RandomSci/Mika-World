"""A full diagnostic ring must not claim that a spoken reply had no voice."""
from tests.harness.full_dev_server import voice_events_since


def test_new_voice_survives_full_history_rollover():
    history=[{'at':i,'ok':True} for i in range(200)]
    previous_length=len(history)
    history.extend([{'at':201,'ok':True},{'at':202,'ok':False,'error':'network'}])
    history[:]=history[-200:]
    assert len(history)==previous_length
    assert voice_events_since(history,200)==[{'at':201,'ok':True},{'at':202,'ok':False,'error':'network'}]
    assert voice_events_since(history,203)==[]
