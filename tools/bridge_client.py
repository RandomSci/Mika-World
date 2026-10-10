#!/usr/bin/env python3
"""Minimal client for the Mika World DEV action bridge (newline-delimited JSON over TCP).

This is the seam where Mika's existing Python intelligence can later plug in: it sends
structured actions and receives real outcomes + observations. DEV ONLY: 127.0.0.1:47651,
no production ports, no credentials.

usage: bridge_client.py [--port 47651] demo
"""
import argparse, json, socket, sys, time


class Bridge:
    def __init__(self, port: int, connect_timeout: float = 60.0):
        deadline = time.time() + connect_timeout
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), timeout=2)
                break
            except OSError:
                if time.time() > deadline:
                    raise
                time.sleep(0.5)
        self.sock.settimeout(0.2)
        self.buf = b""
        self.next_id = 1
        self.pending = []  # events received while waiting for a reply

    def _lines(self, wait: float):
        end = time.time() + wait
        while time.time() < end:
            try:
                chunk = self.sock.recv(65536)
                if not chunk:
                    return
                self.buf += chunk
            except socket.timeout:
                pass
            while b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                if line.strip():
                    yield json.loads(line)

    def request(self, cmd: str, **kw) -> dict:
        rid = self.next_id
        self.next_id += 1
        msg = {"id": rid, "cmd": cmd, **kw}
        self.sock.sendall((json.dumps(msg) + "\n").encode())
        for m in self._lines(10.0):
            if m.get("id") == rid:
                return m
            self.on_event(m)
            self.pending.append(m)
        raise TimeoutError(cmd)

    def wait_for(self, action: str, timeout: float = 60.0) -> dict:
        for i, m in enumerate(self.pending):
            if m.get("event") == "action_finished" and m.get("action") == action:
                del self.pending[: i + 1]
                return m
        self.pending.clear()
        for m in self._lines(timeout):
            self.on_event(m)
            if m.get("event") == "action_finished" and m.get("action") == action:
                return m
        raise TimeoutError(action)

    def on_event(self, m: dict):
        if m.get("event") in ("hello", "cast_phase", "action_started"):
            print("  <event>", json.dumps({k: m[k] for k in m if k not in ("observation",)}))


def short_obs(o: dict) -> dict:
    return {"position": o["position"], "area": o["area"], "action": o["current_action"],
            "visible": o["visible"], "nearby": [n["id"] + f"@{n['distance']}m" for n in o["nearby"][:4]],
            "interactions": o["interactions"]}


def demo(port: int):
    b = Bridge(port)
    print("> observe")
    r = b.request("observe")
    print("  ", json.dumps(short_obs(r["observation"])))
    print("> navigate_to spell_altar")
    print("  ", b.request("navigate_to", target="spell_altar"))
    done = b.wait_for("navigate_to")
    print("  result:", done["ok"], done["detail"], short_obs(done["observation"]))
    print("> look_at north_arch")
    print("  ", b.request("look_at", target="north_arch"))
    done = b.wait_for("look_at", 10)
    print("  result:", done["ok"], done["detail"])
    print("> cast_spell arcane_orb")
    print("  ", b.request("cast_spell", spell="arcane_orb"))
    print("> cast_spell fireball (expected failure: unknown spell)")
    print("  ", b.request("cast_spell", spell="fireball"))
    done = b.wait_for("cast_spell", 30)
    print("  result:", done["ok"], done["detail"])
    print("> navigate_to [999, 0, 999] (expected failure: unreachable)")
    print("  ", b.request("navigate_to", target=[999, 0, 999]))
    b.pending.clear()  # drop the refusal event so it isn't mistaken for the next navigation result
    print("> start_training (walk to the standing stones, face them, practice cast)")
    print("  ", b.request("start_training"))
    done = b.wait_for("navigate_to", 60)
    print("  navigate result:", done["ok"], done["detail"], short_obs(done["observation"])["area"])
    done = b.wait_for("cast_spell", 40)
    print("  practice cast result:", done["ok"], done["detail"])
    print("> observe")
    print("  ", json.dumps(short_obs(b.request("observe")["observation"])))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=47651)
    ap.add_argument("mode", nargs="?", default="demo")
    a = ap.parse_args()
    demo(a.port)
