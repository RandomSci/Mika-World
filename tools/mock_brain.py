#!/usr/bin/env python3
"""Mock autonomous brain for Mika World (DEV). Talks ONLY to the isolated bridge on 127.0.0.1:47651.

Loop: list_locations → choose nearest unvisited playable location (route hops) → travel_to →
observe → nearby_interactables → navigate into reach → interact → occasionally cast → repeat.
Also checks honesty: scenic/unfinished landmarks must be refused by travel_to.
Writes a JSON report (default screenshots/mock_brain_report.json).

usage: mock_brain.py [--max N] [--report path] [--cast-every K]
"""
import argparse, json, os, socket, sys, time

ap = argparse.ArgumentParser()
ap.add_argument("--port", type=int, default=47651)
ap.add_argument("--max", type=int, default=24)
ap.add_argument("--cast-every", type=int, default=4)
ap.add_argument("--report", default=os.path.join(os.path.dirname(__file__), "..", "screenshots", "mock_brain_report.json"))
args = ap.parse_args()


class Bridge:
    def __init__(self, port):
        t0 = time.time()
        while True:
            try:
                self.s = socket.create_connection(("127.0.0.1", port), timeout=2)
                break
            except OSError:
                if time.time() - t0 > 120:
                    raise
                time.sleep(0.5)
        self.s.settimeout(0.2)
        self.buf = b""
        self.rid = 0
        self.events = []

    def _read(self, wait):
        end = time.time() + wait
        while time.time() < end:
            try:
                c = self.s.recv(1 << 16)
                if not c:
                    raise ConnectionError("bridge closed")
                self.buf += c
            except socket.timeout:
                pass
            while b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                if line.strip():
                    yield json.loads(line)

    def req(self, cmd, timeout=60, fresh=False, **kw):
        if fresh:
            self.drain()
            self.events.clear()  # anything older belongs to previous actions
        self.rid += 1
        rid = self.rid
        self.s.sendall((json.dumps({"id": rid, "cmd": cmd, **kw}) + "\n").encode())
        for m in self._read(timeout):
            if m.get("id") == rid:
                return m
            self.events.append(m)
        raise TimeoutError(cmd)

    def drain(self):
        for m in self._read(0.25):
            self.events.append(m)

    def wait_event(self, pred, timeout):
        for i, e in enumerate(self.events):
            if pred(e):
                del self.events[: i + 1]
                return e
        self.events.clear()
        for m in self._read(timeout):
            if pred(m):
                return m
            self.events.append(m)
        return None


def log(*a):
    print("[brain]", *a, flush=True)


b = Bridge(args.port)
report = {"visits": [], "honesty_checks": [], "started": time.time()}

# --- honesty checks on landmarks visible from the start
lm = b.req("landmarks")["landmarks"]
for l in lm:
    if l["kind"] in ("scenic", "unfinished"):
        target = l.get("location", l["id"])
        r = b.req("travel_to", location=target)
        report["honesty_checks"].append({"landmark": l["id"], "kind": l["kind"], "reachable_flag": l["reachable"], "travel_reply": r.get("error", r.get("status"))})
        log("honesty:", l["id"], l["kind"], "reachable=", l["reachable"], "travel_to ->", r.get("ok"), r.get("error", ""))
r = b.req("travel_to", location="sunken_citadel")
report["honesty_checks"].append({"landmark": "sunken_citadel (by id)", "travel_reply": r.get("error", r.get("status")), "ok": r.get("ok")})
log("honesty: travel_to sunken_citadel ->", r.get("ok"), r.get("error", ""))

visited = set()
step = 0
while len(report["visits"]) < args.max:
    locs = b.req("list_locations")["locations"]
    here = [l for l in locs if l["current"]]
    if here:
        visited.add(here[0]["id"])
    cands = [l for l in locs if l["playable"] and l["id"] not in visited and l["route_hops"] >= 0]
    if not cands:
        break
    cands.sort(key=lambda l: (l["route_hops"], l["id"]))
    goal = cands[0]
    log(f"choosing {goal['id']} ({goal['name']}), hops={goal['route_hops']}, loaded={goal['loaded']}")
    t0 = time.time()
    r = b.req("travel_to", fresh=True, location=goal["id"])
    visit = {"location": goal["id"], "hops": goal["route_hops"], "travel_reply": {k: r.get(k) for k in ("ok", "status", "route", "error")}}
    if not r.get("ok"):
        visit["result"] = "refused: " + str(r.get("error"))
        visited.add(goal["id"])
        report["visits"].append(visit)
        continue
    fin = b.wait_event(lambda e: e.get("event") == "journey_finished", 300)
    visit["journey"] = {k: fin.get(k) for k in ("ok", "detail", "location", "area", "seconds")} if fin else {"ok": False, "detail": "no journey_finished event"}
    visit["transitions"] = [{k: t.get(k) for k in ("to", "total_ms", "build_ms", "nav_bake_ms")} for t in (fin or {}).get("transitions", [])]
    visited.add(goal["id"])
    obs = b.req("observe")["observation"]
    visit["observed"] = {k: obs.get(k) for k in ("location", "area_loaded", "region", "visible", "visible_landmarks", "transition")}
    # do one real activity here
    its = [i for i in b.req("nearby_interactables", radius=40)["interactables"] if i["location"] == goal["id"] and i["available"]]
    if its:
        it = its[0]
        if not it["in_reach"]:
            b.req("navigate_to", fresh=True, target=it["id"], run=True)
            b.wait_event(lambda e: e.get("event") == "action_finished" and e.get("action") == "navigate_to", 60)
        res = b.req("interact", object=it["id"], timeout=40)
        visit["interaction"] = {"object": it["id"], "ok": res.get("ok"), "detail": res.get("detail"), "changes": res.get("changes")}
        log("  interact", it["id"], "->", res.get("ok"), res.get("detail"), res.get("changes"))
    else:
        visit["interaction"] = {"object": None, "detail": "no available interaction (requirements unmet or none here)"}
    step += 1
    if args.cast_every and step % args.cast_every == 0:
        c = b.req("cast_spell", fresh=True, spell="arcane_orb")
        done = b.wait_event(lambda e: e.get("event") == "action_finished" and e.get("action") == "cast_spell", 30) if c.get("ok") else None
        visit["cast"] = {"started": c.get("ok"), "error": c.get("error"), "finished": done.get("ok") if done else None}
        log("  cast ->", c.get("ok"), c.get("error", ""), "finished", done.get("detail") if done else None)
    visit["wall_seconds"] = round(time.time() - t0, 1)
    log(f"  arrived={visit['journey'].get('ok')} at {visit['observed'].get('location')} area={visit['observed'].get('area_loaded')} in {visit['wall_seconds']}s")
    report["visits"].append(visit)

report["final_state"] = b.req("world_state")["state"]
report["transition_state"] = b.req("transition_state")
report["elapsed_s"] = round(time.time() - report["started"], 1)
os.makedirs(os.path.dirname(os.path.abspath(args.report)), exist_ok=True)
json.dump(report, open(args.report, "w"), indent=1)
ok = sum(1 for v in report["visits"] if v.get("journey", {}).get("ok"))
log(f"done: {ok}/{len(report['visits'])} journeys ok, visited {len(report['final_state']['visited'])} locations, {report['elapsed_s']} s")
