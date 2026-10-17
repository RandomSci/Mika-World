"""The Godot world as the Stage, and the broadcast intro.

    The stream is the Godot world (Mika World 2.0): Mika and Luna live there, its picture
                                 reaches OBS as "Godot World", and Godot connects to this server as the Stage
                                 (scripts/live/live_link.gd in the Godot project). mika-live.sh
                                 starts Godot (tools/godot-stage.sh).
    VR_GODOT_WINDOW="Mika World Stage"   the Godot window's title (set by the live link)
    VR_GODOT_AUDIO_SINK=MikaWorld        Godot plays into this PipeWire sink; OBS captures only it
    VR_INTRO_VIDEO=assets/intro/Mika_AMV_720p_preview.mp4
                                 played once, full screen with its sound, at the start of every
                                 broadcast (also the unattended one after the 11h55m end), then
                                 the world scene; empty = no intro
    OBS_INTRO_SCENE=Intro        the OBS scene that plays it

Everything here is idempotent: the OBS scenes and sources are made when missing and corrected
when they differ, every start.
"""

from __future__ import annotations

import asyncio
import os
import time
from pathlib import Path
from typing import Any

from loguru import logger

ROOT = Path(__file__).resolve().parents[3]
WINDOW_SOURCE = "Godot World"
# The stage on native Wayland (tools/godot-stage.sh): OBS captures it with a PipeWire source chosen once by hand in
# the portal dialog (its restore token keeps the choice). Such a source is used as it is: never re-pointed, never
# replaced by an X window capture (an X capture of the XWayland window read frames mid-swap: frames out of order).
# The headless stage (tools/stage_bridge.py) reaches OBS as a Video Capture Device (V4L2) under the same name: kept too.
PIPEWIRE_KINDS = ("pipewire-screen-capture-source", "pipewire-window-capture-source", "pipewire-desktop-capture-source",
                  "v4l2_input")
AUDIO_SOURCE = "Godot World Audio"
INTRO_SOURCE = "Intro Video"


def godot_renderer() -> bool:
    return True          # the Godot world is the only Stage


def window_title() -> str:
    return os.environ.get("VR_GODOT_WINDOW", "Mika World Stage").strip() or "Mika World Stage"


def audio_sink() -> str:
    return os.environ.get("VR_GODOT_AUDIO_SINK", "MikaWorld").strip() or "MikaWorld"


def audio_monitor() -> str:
    """What OBS's audio output capture listens to: the sink's monitor source (the bare sink name captures nothing)."""
    return audio_sink() + ".monitor"


def intro_path() -> str:
    raw = os.environ.get("VR_INTRO_VIDEO", "assets/intro/Mika_AMV_720p_preview.mp4").strip()
    if not raw:
        return ""
    p = Path(raw).expanduser()
    p = p if p.is_absolute() else ROOT / p
    return str(p) if p.is_file() else ""


def intro_scene() -> str:
    return os.environ.get("OBS_INTRO_SCENE", "Intro").strip() or "Intro"


async def _scenes(obs: Any) -> list[str]:
    return [x["sceneName"] for x in (await obs.call("GetSceneList")).get("scenes") or []]


async def _inputs(obs: Any) -> dict[str, str]:
    return {i["inputName"]: i.get("inputKind", "") for i in (await obs.call("GetInputList")).get("inputs") or []}


async def _full_screen(obs: Any, scene: str, item_id: int) -> None:
    await obs.call(
        "SetSceneItemTransform",
        {
            "sceneName": scene,
            "sceneItemId": item_id,
            "sceneItemTransform": {
                "positionX": 0, "positionY": 0, "alignment": 5,
                "boundsType": "OBS_BOUNDS_SCALE_INNER", "boundsWidth": 1920, "boundsHeight": 1080, "boundsAlignment": 0,
            },
        },
    )


async def _item(obs: Any, scene: str, source: str) -> int:
    """The scene item id of `source` in `scene` (added when missing, full screen)."""
    items = (await obs.call("GetSceneItemList", {"sceneName": scene})).get("sceneItems") or []
    for i in items:
        if i.get("sourceName") == source:
            return int(i.get("sceneItemId"))
    made = await obs.call("CreateSceneItem", {"sceneName": scene, "sourceName": source, "sceneItemEnabled": True})
    item_id = int(made.get("sceneItemId"))
    await _full_screen(obs, scene, item_id)
    return item_id


def _x(args: list[str]) -> str:
    import subprocess

    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return ""


def _godot_window() -> tuple[str, str, int]:
    """(capture value, window id, Godot pid) of the Godot window, read straight from X (xdotool/xprop);
    ("", "", 0) when it is not open."""
    import re

    for wid in _x(["xdotool", "search", "--name", window_title()]).split():
        props = _x(["xprop", "-id", wid, "WM_CLASS", "_NET_WM_NAME", "_NET_WM_PID"])
        cls = re.search(r'WM_CLASS\(STRING\) = "([^"]*)", "([^"]*)"', props)
        name = re.search(r'_NET_WM_NAME\(UTF8_STRING\) = "(.*)"', props)
        pid = re.search(r"_NET_WM_PID\(CARDINAL\) = (\d+)", props)
        if not cls or not name or cls.group(1) != "Godot_Engine":
            continue                     # the window manager's frame, never Godot's own window
        return f"{int(wid)}\r\n{name.group(1)}\r\n{cls.group(1)}", wid, int(pid.group(1)) if pid else 0
    return "", "", 0


def stage_pid() -> int:
    """The running Godot stage's pid (tools/godot-stage.sh writes it), 0 when it is not running."""
    try:
        pid = int((ROOT / "logs" / "godot-stage.pid").read_text().strip() or 0)
        os.kill(pid, 0)
        return pid
    except Exception:
        return 0


async def pipewire_capture(obs: Any) -> bool:
    """True when the world's window source is a PipeWire capture (the Wayland stage)."""
    return (await _inputs(obs)).get(WINDOW_SOURCE, "") in PIPEWIRE_KINDS


def stage_window_open() -> bool:
    """The stage window is there to capture: found on X (XWayland stage) or, on Wayland where windows cannot be
    listed, its process is running."""
    return bool(_window_capture_value()) or stage_pid() > 0


def _window_capture_value() -> str:
    """The xcomposite 'capture_window' value of the Godot window: "<id>\r\n<name>\r\n<WM_CLASS instance>", the
    format OBS's X window capture stores. Built here: asking OBS for its window list
    (GetInputPropertiesListPropertyItems on capture_window) crashes OBS 32.2.2. "" when the window is not open."""
    return _godot_window()[0]


async def rebind_window(obs: Any, source: str = "") -> None:
    """Point the window capture at the Godot window again. A restarted Godot can get the very same X window id,
    and OBS then keeps its last frame of the old window: clearing and re-setting the value makes it bind anew."""
    source = source or WINDOW_SOURCE
    value = _window_capture_value()
    if not value or (await _inputs(obs)).get(source, "") in PIPEWIRE_KINDS:
        return
    await obs.call("SetInputSettings", {"inputName": source, "inputSettings": {"capture_window": ""}})
    await asyncio.sleep(0.5)
    await obs.call("SetInputSettings", {"inputName": source, "inputSettings": {"capture_window": value}})


_FOLLOWING = False


async def follow_window(every: float = 5.0) -> None:
    """For the server's whole life: when Godot is restarted (tools/godot-stage.sh brings it back after a
    crash), the OBS window capture is bound to the new window, so the stream never freezes on its last frame."""
    global _FOLLOWING
    if _FOLLOWING:
        return
    _FOLLOWING = True
    from .obs_control import _connect_when_ready, obs_running

    last = _godot_window()[2]
    while True:
        await asyncio.sleep(every)
        pid = _godot_window()[2]
        if not pid or pid == last:
            continue
        if not obs_running():
            last = pid                   # OBS binds it itself when it opens (ensure_world_scene)
            continue
        await asyncio.sleep(6)           # the new window draws its first frames
        obs = await _connect_when_ready(10)
        if obs is None:
            continue                     # tried again on the next round
        try:
            await rebind_window(obs)
            last = pid
            logger.info(f"OBS: Godot restarted (pid {pid}), the window capture follows the new window")
        except Exception as exc:
            logger.warning(f"OBS: could not rebind the Godot window capture: {exc}")
        finally:
            await obs.__aexit__(None, None, None)


async def ensure_world_scene(obs: Any, scene: str) -> str:
    """`scene` holds the Godot window (full screen) and its own audio, nothing else visible."""
    scenes = await _scenes(obs)
    inputs = await _inputs(obs)
    if scene not in scenes:
        await obs.call("CreateScene", {"sceneName": scene})
        logger.info(f"OBS: created the scene '{scene}' for the Godot world")
    # the Godot window (a PipeWire capture under that name is kept exactly as it was chosen)
    pipewire = inputs.get(WINDOW_SOURCE, "") in PIPEWIRE_KINDS
    if WINDOW_SOURCE not in inputs:
        await obs.call(
            "CreateInput",
            {"sceneName": scene, "inputName": WINDOW_SOURCE, "inputKind": "xcomposite_input",
             "inputSettings": {"capture_cursor": False, "show_cursor": False, "exclude_alpha": True}, "sceneItemEnabled": True},
        )
        logger.info(f"OBS: added the window capture '{WINDOW_SOURCE}'")
    value = "" if pipewire else _window_capture_value()
    if value:
        current = (await obs.call("GetInputSettings", {"inputName": WINDOW_SOURCE})).get("inputSettings") or {}
        if current.get("capture_window") != value:
            await obs.call("SetInputSettings", {"inputName": WINDOW_SOURCE, "inputSettings": {
                "capture_window": value, "capture_cursor": False, "show_cursor": False, "exclude_alpha": True}})
            logger.info("OBS: the window capture follows the Godot window")
    win_id = await _item(obs, scene, WINDOW_SOURCE)
    await _full_screen(obs, scene, win_id)
    # its sound: only the Godot sink's monitor (never the desktop, notifications or a browser)
    if AUDIO_SOURCE not in inputs:
        await obs.call(
            "CreateInput",
            {"sceneName": scene, "inputName": AUDIO_SOURCE, "inputKind": "pulse_output_capture",
             "inputSettings": {"device_id": audio_monitor()}, "sceneItemEnabled": True},
        )
        logger.info(f"OBS: added the world audio '{AUDIO_SOURCE}' ({audio_sink()})")
    else:
        await obs.call("SetInputSettings", {"inputName": AUDIO_SOURCE, "inputSettings": {"device_id": audio_monitor()}})
    await _item(obs, scene, AUDIO_SOURCE)
    await mute_desktop_audio(obs)
    # anything else in this scene is hidden
    items = (await obs.call("GetSceneItemList", {"sceneName": scene})).get("sceneItems") or []
    for i in items:
        name = i.get("sourceName")
        if name in (WINDOW_SOURCE, AUDIO_SOURCE):
            if not i.get("sceneItemEnabled"):
                await obs.call("SetSceneItemEnabled", {"sceneName": scene, "sceneItemId": i["sceneItemId"], "sceneItemEnabled": True})
            continue
        if i.get("sceneItemEnabled"):
            await obs.call("SetSceneItemEnabled", {"sceneName": scene, "sceneItemId": i["sceneItemId"], "sceneItemEnabled": False})
            logger.info(f"OBS: '{name}' hidden in '{scene}'")
    return scene


MUTED_FILE = ROOT / "logs" / "obs-desktop-audio-muted-by-godot.json"


async def mute_desktop_audio(obs: Any) -> None:
    """The world's sound reaches OBS only through its own sink: the global desktop capture (every app,
    notifications) is muted for the show."""
    import json as _json

    muted = []
    try:
        for name, kind in (await _inputs(obs)).items():
            if kind != "pulse_output_capture" or name == AUDIO_SOURCE:
                continue
            if not (await obs.call("GetInputMute", {"inputName": name})).get("inputMuted"):
                await obs.call("SetInputMute", {"inputName": name, "inputMuted": True})
                muted.append(name)
                logger.info(f"OBS: '{name}' (all desktop sound) muted for the Godot world")
        if muted:
            old = _json.loads(MUTED_FILE.read_text()) if MUTED_FILE.is_file() else []
            MUTED_FILE.parent.mkdir(exist_ok=True)
            MUTED_FILE.write_text(_json.dumps(sorted(set(old) | set(muted))))
    except Exception as exc:
        logger.warning(f"OBS: desktop audio not checked: {exc}")


async def ensure_intro_scene(obs: Any) -> str:
    """The Intro scene: the intro video, full screen (1080p bounds), with its sound, played once from the start
    each time the scene is shown. "" when there is no intro video."""
    path = intro_path()
    if not path:
        return ""
    scene = intro_scene()
    if scene not in await _scenes(obs):
        await obs.call("CreateScene", {"sceneName": scene})
        logger.info(f"OBS: created the scene '{scene}'")
    settings = {"local_file": path, "is_local_file": True, "looping": False, "restart_on_activate": True,
                "close_when_inactive": True, "clear_on_media_end": False, "hw_decode": True}
    if INTRO_SOURCE not in await _inputs(obs):
        await obs.call("CreateInput", {"sceneName": scene, "inputName": INTRO_SOURCE, "inputKind": "ffmpeg_source",
                                       "inputSettings": settings, "sceneItemEnabled": True})
        logger.info(f"OBS: added the intro video to '{scene}'")
    else:
        await obs.call("SetInputSettings", {"inputName": INTRO_SOURCE, "inputSettings": settings})
    item_id = await _item(obs, scene, INTRO_SOURCE)
    await _full_screen(obs, scene, item_id)
    # heard on the stream (the media source's own audio track, not monitored locally)
    try:
        await obs.call("SetInputAudioMonitorType", {"inputName": INTRO_SOURCE, "monitorType": "OBS_MONITORING_TYPE_NONE"})
        await obs.call("SetInputMute", {"inputName": INTRO_SOURCE, "inputMuted": False})
    except Exception:
        pass
    return scene


async def play_intro_then(obs: Any, world_scene: str, max_seconds: float = 600.0) -> bool:
    """On air: the Intro scene until the video has played through once, then the world scene. True when the
    intro played. Never raises (the world scene is always switched to)."""
    played = False
    try:
        scene = await ensure_intro_scene(obs)
        if scene:
            await obs.call("SetCurrentProgramScene", {"sceneName": scene})
            await asyncio.sleep(0.5)
            try:
                await obs.call("TriggerMediaInputAction", {"inputName": INTRO_SOURCE, "mediaAction": "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART"})
            except Exception:
                pass
            logger.info("OBS: the intro is playing")
            started = time.time()
            seen_playing = False
            while time.time() - started < max_seconds:
                await asyncio.sleep(1)
                st = await obs.call("GetMediaInputStatus", {"inputName": INTRO_SOURCE})
                state = str(st.get("mediaState", ""))
                if state.endswith("PLAYING"):
                    seen_playing = True
                if state.endswith("ENDED") or (seen_playing and state.endswith("STOPPED")):
                    break
                dur, cur = st.get("mediaDuration") or 0, st.get("mediaCursor") or 0
                if seen_playing and dur and cur and cur >= dur - 150:
                    await asyncio.sleep(0.3)
                    break
                if not seen_playing and time.time() - started > 20:
                    logger.warning("OBS: the intro did not start playing in 20 s, going to the world")
                    break
            played = seen_playing
            logger.info(f"OBS: intro done ({time.time() - started:.0f} s)")
    except Exception as exc:
        logger.warning(f"OBS: intro failed ({exc}), going to the world")
    try:
        await obs.call("SetCurrentProgramScene", {"sceneName": world_scene})
        logger.info(f"OBS: on air: '{world_scene}'")
    except Exception as exc:
        logger.warning(f"OBS: could not switch to '{world_scene}': {exc}")
    return played
