#!/usr/bin/python3
"""The stage's picture into OBS with no window and no portal.

gamescope runs headless (no window on the desktop, so GNOME has nothing to throttle when OBS covers the screen) and
publishes what it composites as a PipeWire video stream (node "gamescope"). This bridge converts those frames to I420
(OBS's V4L2 reader refused BGRx and NV12; never encoded) and writes them into the v4l2loopback device that OBS's
"Godot World" Video Capture Device (V4L2) reads.

Two halves:
  * the output (appsrc -> v4l2sink) opens the device ONCE for the bridge's whole life and writes every fresh frame
    the moment it arrives, keeping the game's own timing (gamescope delivers a clean 30.0 fps). Only when nothing new
    comes for 200 ms is the last frame repeated, so the device never goes quiet. (A fixed 30 fps timer of its own
    re-sampled the game's frames: phase drift held a frame twice and skipped the next 28-258 times a minute on
    stream - the picture stuck and jumped, 2026-10-17.) With exclusive_caps=1 a writer that closes the device while
    OBS reads cannot open it again (2026-10-17: every reconnect failed, the retries churned gamescope's stream until
    its PipeWire side died: "pipewire: stream state changed: error ... exiting").
  * the input (pipewiresrc -> appsink) follows gamescope: on an error or a new gamescope node it reconnects alone.
A heartbeat file is touched while fresh frames arrive; the stage loop restarts gamescope when it goes stale.

Usage: stage_bridge.py <v4l2 device, default /dev/video42> [log]
Runs with the system python3 (python3-gi + gstreamer1.0-pipewire + gstreamer1.0-plugins-good).
"""
import collections
import json
import os
import subprocess
import sys
import threading
import time

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst  # noqa: E402

DEVICE = sys.argv[1] if len(sys.argv) > 1 else "/dev/video42"
LOG = sys.argv[2] if len(sys.argv) > 2 else ""
HEARTBEAT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "logs", "stage-bridge.alive")
W, H, FPS = 1920, 1080, 30
FRAME_CAPS = f"video/x-raw,format=I420,width={W},height={H},colorimetry=bt709"
CAPS = f"{FRAME_CAPS},framerate={FPS}/1"


def log(msg: str) -> None:
    line = f"{time.strftime('%H:%M:%S')} [bridge] {msg}"
    print(line, flush=True)
    if LOG:
        with open(LOG, "a") as f:
            f.write(line + "\n")


# Only the STAGE's gamescope is followed: the one whose process runs this match (default: the stage launcher). Any
# other gamescope on the machine (a test, a preview) also publishes a node named "gamescope"; following "the newest"
# put a session's offscreen test on the live stream for 95 s (2026-10-18 05:09 and 05:12).
STAGE_MATCH = os.environ.get("STAGE_BRIDGE_MATCH", "godot-stage.sh")


def _cmdline(pid) -> str:
    try:
        return open(f"/proc/{int(pid)}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="ignore")
    except Exception:
        return ""


def stage_nodes(dump: list, match: str = "") -> list:
    """The gamescope video nodes owned by a process whose command line contains `match` (oldest first)."""
    match = match or STAGE_MATCH
    clients = {o.get("id"): o.get("info", {}).get("props", {}) for o in dump if o.get("type") == "PipeWire:Interface:Client"}
    out = []
    for o in dump:
        props = o.get("info", {}).get("props", {}) if o.get("type") == "PipeWire:Interface:Node" else {}
        if props.get("node.name") != "gamescope" or props.get("media.class") != "Video/Source":
            continue
        cp = clients.get(props.get("client.id"), {})
        pid = cp.get("pipewire.sec.pid") or cp.get("application.process.id")
        if pid and match in _cmdline(pid):
            out.append(o)
    return out


def gamescope_serial() -> str:
    """object.serial of the stage's gamescope video node, "" when there is none (other gamescopes are ignored)."""
    try:
        dump = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=10).stdout or "[]")
    except Exception:
        return ""
    found = stage_nodes(dump)
    return str(found[-1]["info"]["props"].get("object.serial", "")) if found else ""


def _err(msg) -> str:
    if msg is None:
        return "?"
    if msg.type != Gst.MessageType.ERROR:
        return "end of stream"
    e, dbg = msg.parse_error()
    return f"{e.message} [{msg.src.get_name() if msg.src else '?'}] {(dbg or '').replace(chr(10), ' | ')[-200:]}"


class Bridge:
    def __init__(self) -> None:
        self.latest = None            # bytes of the newest I420 frame
        self.fresh_at = 0.0
        self.frames_in = 0
        self.lock = threading.Lock()
        self.new_frame = threading.Condition(self.lock)
        self.queue = collections.deque(maxlen=4)   # fresh frames waiting for their paced write

    # ---- input: gamescope -> latest frame (reconnects on its own, never touches the device)
    def input_loop(self) -> None:
        while True:
            serial = gamescope_serial()
            if not serial:
                time.sleep(1)
                continue
            pipe = Gst.parse_launch(
                f"pipewiresrc target-object={serial} do-timestamp=true ! video/x-raw,format=BGRx "
                f"! videoconvert n-threads=4 ! videoscale ! {FRAME_CAPS} "
                "! appsink name=sink max-buffers=1 drop=true sync=false")
            sink = pipe.get_by_name("sink")
            bus = pipe.get_bus()
            pipe.set_state(Gst.State.PLAYING)
            log(f"gamescope stream {serial} connected")
            last_check = time.monotonic()
            while True:
                sample = sink.emit("try-pull-sample", Gst.SECOND // 2)
                if sample is not None:
                    buf = sample.get_buffer()
                    ok, info = buf.map(Gst.MapFlags.READ)
                    if ok:
                        data = bytes(info.data)
                        buf.unmap(info)
                        with self.new_frame:
                            self.latest = data
                            self.fresh_at = time.monotonic()
                            self.frames_in += 1
                            self.queue.append(data)
                            self.new_frame.notify()
                msg = bus.pop_filtered(Gst.MessageType.ERROR | Gst.MessageType.EOS)
                if msg is not None:
                    log(f"gamescope stream stopped: {_err(msg)}")
                    break
                if time.monotonic() - last_check > 5:
                    last_check = time.monotonic()
                    if gamescope_serial() not in ("", serial):
                        log("gamescope restarted: following its new stream")
                        break
            pipe.set_state(Gst.State.NULL)
            time.sleep(2)                 # never a reconnect storm

    # ---- output: frames written on an EVEN clock (a small jitter buffer), the device opened once for the bridge's life
    # Written as they arrived, the frames kept a few ms of timing jitter from this thread; OBS reads the device on its
    # own 30 fps clock, so near a frame boundary it took one frame twice and missed the next (~43 a minute on stream,
    # 2026-10-17 04:02). Now each frame waits in a short queue and is written on a steady clock whose period follows
    # the game's measured rate and whose phase keeps about one frame in hand: OBS always finds exactly one new frame
    # per tick. A frame is repeated only when the game itself stops for 200 ms (the device must not go quiet).
    def output_loop(self) -> None:
        pipe = Gst.parse_launch(f"appsrc name=src is-live=true format=time do-timestamp=true caps={CAPS} "
                                f"! videoconvert ! v4l2sink name=out device={DEVICE} sync=false")   # (passthrough)
        src = pipe.get_by_name("src")
        bus = pipe.get_bus()
        pipe.set_state(Gst.State.PLAYING)
        log(f"output open: {DEVICE} ({W}x{H} I420, paced writes, ~1 frame of buffer)")
        black = bytes([16]) * (W * H) + bytes([128]) * (W * H // 2)
        period = 1.0 / FPS
        nxt = 0.0
        last = black
        last_fresh_write = time.monotonic()
        n = written_fresh = repeats = 0
        late_sum = 0.0
        jit = []
        last_report = time.monotonic()
        checked = False
        while True:
            with self.new_frame:
                if not self.queue and nxt == 0.0:
                    self.new_frame.wait(0.2)            # (not started yet: wait for the first frame)
                qlen = len(self.queue)
            now = time.monotonic()
            if nxt == 0.0:
                if qlen == 0:
                    frame = last                        # nothing at all yet: keep the device fed
                    nxt = 0.0
                else:
                    nxt = now + period                  # start: hold one frame in hand
                    continue
            else:
                wait = nxt - now
                if wait > 0:
                    time.sleep(wait)
                now = time.monotonic()
                jit.append(now - nxt)
                with self.new_frame:
                    qlen = len(self.queue)
                    # phase: aim for ~1 frame waiting after this write; drift the clock gently toward that
                    if qlen >= 3:
                        while len(self.queue) > 2:
                            self.queue.popleft()        # far behind (a hitch's burst): drop the oldest, never fall behind
                        nxt -= period * 0.25
                    elif qlen == 0:
                        nxt += period * 0.10            # running dry: give the game a little more time
                    frame = self.queue.popleft() if self.queue else None
                if frame is None:
                    if time.monotonic() - last_fresh_write > 0.2:
                        frame = last                    # the game stopped: keep the device fed
                        repeats += 1
                    else:
                        nxt += period                   # just late: skip this tick, the next one writes it
                        continue
                else:
                    last = frame
                    last_fresh_write = time.monotonic()
                    written_fresh += 1
                nxt += period
                if nxt < time.monotonic() - 0.5:
                    nxt = time.monotonic() + period     # far behind (a suspend?): no catch-up burst
            buf = Gst.Buffer.new_wrapped(frame)
            buf.duration = Gst.SECOND // FPS
            if src.emit("push-buffer", buf) != Gst.FlowReturn.OK:
                raise RuntimeError(_err(bus.pop_filtered(Gst.MessageType.ERROR)))
            msg = bus.pop_filtered(Gst.MessageType.ERROR)
            if msg is not None:
                raise RuntimeError(_err(msg))
            n += 1
            if nxt == 0.0:
                time.sleep(period)
            if not checked and n == FPS * 3:
                checked = True
                st = pipe.get_state(0)[1]
                queued = src.get_property("current-level-bytes")
                log(f"output after 3 s: state {st.value_nick}, {queued // (W * H * 3 // 2)} frames waiting in appsrc")
                if st != Gst.State.PLAYING or queued > W * H * 3:
                    raise RuntimeError("output pipeline is not flowing")
            now = time.monotonic()
            if written_fresh and now - last_fresh_write < 1.0 and (n % FPS == 0):
                try:
                    with open(HEARTBEAT, "a"):
                        os.utime(HEARTBEAT, None)
                except OSError:
                    pass
            if now - last_report >= 60:
                secs = now - last_report
                js = sorted(abs(x) * 1000 for x in jit) or [0.0]
                log(f"{self.frames_in / max(secs, 1):.1f} fresh fps in, {written_fresh / secs:.1f} fresh fps written to {DEVICE}, "
                    f"{repeats} keep-alive repeats, write timing p50 {js[len(js) // 2]:.1f} ms p99 {js[int(len(js) * 0.99)]:.1f} ms")
                with self.new_frame:
                    self.frames_in = 0
                last_report, written_fresh, repeats, jit = now, 0, 0, []


def main() -> None:
    Gst.init(None)
    b = Bridge()
    threading.Thread(target=b.input_loop, daemon=True).start()
    try:
        b.output_loop()
    except Exception as exc:  # the stage loop starts the bridge again
        log(f"output error: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
