"""OBS, driven from the server (obs-websocket 5, built into OBS 28+).

Going live (VR_START_OBS=1), in this order:
  1. wait until OBS answers (go-live.sh opens it; it can take a while)
  2. find the Browser source showing the Stage (create one if there is none)
     and switch to the scene that has it
  3. reload that source WITHOUT cache, so OBS never shows an old page
  4. wait until the reloaded page has loaded Mika and Luna
  5. start streaming, then wait a few seconds for YouTube to pick it up
Only then does the class begin (STREAM_LIVE is set).

Ending: stop streaming and close OBS.

    OBS_WEBSOCKET_URL       ws://127.0.0.1:4455
    OBS_WEBSOCKET_PASSWORD  from Tools, WebSocket Server Settings
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import itertools
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any, Callable, Optional

from loguru import logger

# Set when the stream is really live (or immediately when OBS is not managed).
STREAM_LIVE = asyncio.Event()


def manage_obs() -> bool:
    return os.environ.get("VR_START_OBS", "0").strip().lower() in ("1", "true", "yes", "on")


class OBSError(RuntimeError):
    pass


# OBS keeps its settings in files on this same computer. Since OBS 30 the
# WebSocket password lives in user.ini (older: global.ini, then config.json),
# so it is read from there and never has to be copied into .env.
YOUTUBE_RTMPS = "rtmps://a.rtmps.youtube.com:443/live2"
OBS_DIRS = (
    Path.home() / ".config/obs-studio",
    Path.home() / ".var/app/com.obsproject.Studio/config/obs-studio",
)


def _ini(path: Path):
    import configparser

    parser = configparser.RawConfigParser(strict=False, interpolation=None)
    parser.optionxform = str  # OBS keys are CamelCase
    parser.read(path, encoding="utf-8-sig")
    return parser


def _obs_dir() -> Optional[Path]:
    """The settings folder of the OBS actually in use: with both the normal and
    the Flatpak OBS installed, the one OBS saved to most recently."""
    def last_used(d: Path) -> float:
        times = [p.stat().st_mtime for p in (d / "user.ini", d / "global.ini") if p.is_file()]
        return max(times or [0.0])

    found = [d for d in OBS_DIRS if d.is_dir()]
    return max(found, key=last_used) if found else None


def _settings_ini() -> Optional[Path]:
    base = _obs_dir()
    if base is None:
        return None
    for name in ("user.ini", "global.ini"):
        path = base / name
        if path.is_file() and _ini(path).has_section("OBSWebSocket"):
            return path
    for name in ("user.ini", "global.ini"):
        if (base / name).is_file():
            return base / name
    return None


def _obs_config() -> tuple[Optional[Path], dict[str, Any]]:
    """{server_enabled, server_port, auth_required, server_password}."""
    path = _settings_ini()
    if path is not None:
        ini = _ini(path)
        if ini.has_section("OBSWebSocket"):
            sec = ini["OBSWebSocket"]
            return path, {
                "server_enabled": sec.get("ServerEnabled", "false").lower() == "true",
                "server_port": int(sec.get("ServerPort", "4455") or 4455),
                "auth_required": sec.get("AuthRequired", "true").lower() == "true",
                "server_password": sec.get("ServerPassword", ""),
            }
    base = _obs_dir()
    legacy = base / "plugin_config/obs-websocket/config.json" if base else None
    try:
        return legacy, json.loads(legacy.read_text())  # type: ignore[union-attr]
    except Exception:
        return None, {}


def obs_running() -> bool:
    return subprocess.run(["pgrep", "-x", "obs"], capture_output=True).returncode == 0


def _write_ini(path: Path, ini) -> None:
    with path.open("w", encoding="utf-8") as handle:
        ini.write(handle, space_around_delimiters=False)


def prepare_obs_config(stream_key: str = "") -> None:
    """Before OBS opens: WebSocket server on, and the YouTube stream key in
    the current profile (so Start Streaming never asks to pick a broadcast)."""
    if obs_running():
        return
    # Wherever this OBS version keeps the WebSocket settings (user.ini or
    # global.ini on new versions, config.json on old ones): server on, and the
    # password from .env when there is one, so both sides always agree.
    password = os.environ.get("OBS_WEBSOCKET_PASSWORD", "").strip()
    for base in (d for d in OBS_DIRS if d.is_dir()):
        _prepare_websocket(base, password)
    if stream_key:
        _write_stream_key(stream_key)
    _write_stream_quality()


def _stream_quality() -> tuple[int, int]:
    """(frames per second, video kbps). 30 fps and 6000 kbps: smooth 1080p on
    YouTube, half the work of 60 fps for an integrated graphics chip."""
    def number(name: str, default: int, low: int, high: int) -> int:
        try:
            return max(low, min(high, int(os.environ.get(name, "") or default)))
        except ValueError:
            return default

    return number("VR_OBS_FPS", 30, 10, 60), number("VR_OBS_BITRATE", 6000, 1500, 20000)


def _write_stream_quality() -> None:
    """The same settings in the profile file, for an OBS opened from the terminal."""
    folder = _profile_dir()
    path = folder / "basic.ini" if folder else None
    if not (path and path.is_file()):
        return
    fps, kbps = _stream_quality()
    try:
        ini = _ini(path)
        for section in ("Video", "SimpleOutput"):
            if not ini.has_section(section):
                ini.add_section(section)
        ini["Video"]["FPSType"] = "0"
        ini["Video"]["FPSCommon"] = str(fps)
        ini["SimpleOutput"]["VBitrate"] = str(kbps)
        _write_ini(path, ini)
    except Exception as exc:
        logger.debug(f"OBS: stream quality not written: {exc}")
    # Advanced output mode keeps the stream encoder's bitrate in its own file;
    # only SimpleOutput was set before, so OBS in Advanced mode sent 12000+.
    encoder = folder / "streamEncoder.json"
    try:
        data = json.loads(encoder.read_text()) if encoder.is_file() else {}
        if not isinstance(data, dict):
            data = {}
        if data.get("bitrate") != kbps or data.get("rate_control", "CBR") != "CBR":
            data.update({"bitrate": kbps, "rate_control": "CBR"})
            encoder.write_text(json.dumps(data, indent=4))
            logger.info(f"OBS: stream bitrate set to {kbps} kbps (advanced output)")
    except Exception as exc:
        logger.debug(f"OBS: advanced bitrate not written: {exc}")


async def _tune_obs(obs: "OBS") -> None:
    """Before streaming starts: frame rate and bitrate (settings OBS keeps)."""
    fps, kbps = _stream_quality()
    try:
        video = await obs.call("GetVideoSettings")
        current = round(video.get("fpsNumerator", 0) / max(1, video.get("fpsDenominator", 1)))
        if current != fps:
            await obs.call("SetVideoSettings", {"fpsNumerator": fps, "fpsDenominator": 1})
            logger.info(f"OBS: frame rate set to {fps} fps")
    except Exception as exc:
        logger.debug(f"OBS: frame rate not changed: {exc}")
    try:
        await obs.call(
            "SetProfileParameter",
            {"parameterCategory": "SimpleOutput", "parameterName": "VBitrate", "parameterValue": str(kbps)},
        )
    except Exception as exc:
        logger.debug(f"OBS: bitrate not changed: {exc}")


def _prepare_websocket(base: Path, password: str) -> None:
    for name in ("user.ini", "global.ini"):
        path = base / name
        if not (path and path.is_file()):
            continue
        ini = _ini(path)
        if not ini.has_section("OBSWebSocket"):
            continue
        sec = ini["OBSWebSocket"]
        changed = sec.get("ServerEnabled", "").lower() != "true" or (password and sec.get("ServerPassword") != password)
        if changed:
            sec["ServerEnabled"] = "true"
            if password:
                sec["ServerPassword"] = password
                sec["AuthRequired"] = "true"
            try:
                _write_ini(path, ini)
                logger.info(f"OBS: WebSocket settings checked ({name})")
            except Exception as exc:
                logger.warning(f"OBS: could not update {name}: {exc}")
    legacy = base / "plugin_config/obs-websocket/config.json"
    if legacy.is_file():
        try:
            config = json.loads(legacy.read_text())
            if not config.get("server_enabled") or (password and config.get("server_password") != password):
                config["server_enabled"] = True
                if password:
                    config["server_password"] = password
                    config["auth_required"] = True
                legacy.write_text(json.dumps(config, indent=4))
                logger.info(f"OBS: WebSocket settings checked ({legacy})")
        except Exception as exc:
            logger.warning(f"OBS: could not update config.json: {exc}")


def _profile_dir() -> Optional[Path]:
    base = _obs_dir()
    path = _settings_ini()
    if base is None or path is None:
        return None
    ini = _ini(path)
    name = ini.get("Basic", "ProfileDir", fallback="") or ini.get("Basic", "Profile", fallback="")
    folder = base / "basic/profiles" / name if name else None
    if folder and folder.is_dir():
        return folder
    profiles = sorted((base / "basic/profiles").glob("*/"))
    return profiles[0] if len(profiles) == 1 else None


def _write_stream_key(key: str) -> None:
    folder = _profile_dir()
    if folder is None:
        logger.warning("OBS: profile folder not found, the stream key was not set")
        return
    service = {"type": "rtmp_custom", "settings": {"server": YOUTUBE_RTMPS, "key": key}}
    try:
        (folder / "service.json").write_text(json.dumps(service, indent=4))
        logger.info(f"OBS: YouTube stream key set in profile '{folder.name}'")
    except Exception as exc:
        logger.warning(f"OBS: could not set the stream key: {exc}")


def _clear_stale_sentinels() -> int:
    """OBS 32 has no --disable-shutdown-check: after an unclean exit (closing
    it with a signal counts) it asks for Safe Mode, which disables the
    WebSocket server, so nothing can drive it. With no OBS running, its old
    run sentinels are stale; removing them avoids that prompt."""
    if obs_running():
        return 0
    removed = 0
    for base in [_obs_dir()] + [Path.home() / ".var/app/com.obsproject.Studio/config/obs-studio", Path.home() / ".config/obs-studio"]:
        folder = base / ".sentinel" if base else None
        if folder and folder.is_dir():
            for f in folder.glob("run_*"):
                try:
                    f.unlink()
                    removed += 1
                except OSError:
                    pass
    if removed:
        logger.info(f"OBS: removed {removed} stale crash sentinel(s), so it does not start in Safe Mode")
    return removed


def launch_obs(streaming: bool) -> bool:
    """Open OBS from the terminal (minimized), optionally streaming at once."""
    _clear_stale_sentinels()
    args = ["--minimize-to-tray", "--disable-shutdown-check"] + (["--startstreaming"] if streaming else [])
    for command in (["obs"], ["flatpak", "run", "com.obsproject.Studio"]):
        if shutil.which(command[0]):
            try:
                subprocess.Popen(
                    command + args,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,  # Ctrl+C in the terminal must not kill it
                )
                return True
            except Exception as exc:
                logger.warning(f"OBS: could not open: {exc}")
    return False


async def close_obs(timeout: float = 15) -> None:
    """Close OBS like clicking X (it stops the stream first)."""
    if not obs_running():
        return
    subprocess.run(["pkill", "-x", "obs"], check=False)
    deadline = time.time() + timeout
    while time.time() < deadline and obs_running():
        await asyncio.sleep(0.5)
    if obs_running():
        subprocess.run(["pkill", "-9", "-x", "obs"], check=False)
    logger.info("OBS: closed")


class OBS:
    """One authenticated obs-websocket connection: ``async with OBS() as obs``."""

    def __init__(self, password: Optional[str] = None) -> None:
        _path, config = _obs_config()
        port = config.get("server_port") or 4455
        self.url = os.environ.get("OBS_WEBSOCKET_URL", "").strip() or f"ws://127.0.0.1:{port}"
        self.password = password if password is not None else (_passwords() or [""])[0]
        self.ws = None
        self._ids = itertools.count(1)

    async def __aenter__(self) -> "OBS":
        import websockets

        self.ws = await websockets.connect(self.url, open_timeout=5, max_size=8 * 1024 * 1024)
        hello = json.loads(await asyncio.wait_for(self.ws.recv(), 5))
        identify: dict[str, Any] = {"rpcVersion": 1, "eventSubscriptions": 0}
        auth = (hello.get("d") or {}).get("authentication")
        if auth:
            secret = base64.b64encode(
                hashlib.sha256((self.password + auth["salt"]).encode()).digest()
            ).decode()
            identify["authentication"] = base64.b64encode(
                hashlib.sha256((secret + auth["challenge"]).encode()).digest()
            ).decode()
        await self.ws.send(json.dumps({"op": 1, "d": identify}))
        try:
            reply = json.loads(await asyncio.wait_for(self.ws.recv(), 5))
        except Exception as exc:
            if "4009" in str(exc):
                raise OBSError("OBS refused the WebSocket password") from None
            raise
        if reply.get("op") != 2:
            raise OBSError("OBS refused the WebSocket password")
        return self

    async def __aexit__(self, *exc: Any) -> None:
        if self.ws is not None:
            await self.ws.close()

    async def call(self, request_type: str, data: Optional[dict[str, Any]] = None) -> dict[str, Any]:
        request_id = str(next(self._ids))
        payload: dict[str, Any] = {"requestType": request_type, "requestId": request_id}
        if data:
            payload["requestData"] = data
        await self.ws.send(json.dumps({"op": 6, "d": payload}))
        while True:
            message = json.loads(await asyncio.wait_for(self.ws.recv(), 10))
            body = message.get("d") or {}
            if message.get("op") == 7 and body.get("requestId") == request_id:
                status = body.get("requestStatus") or {}
                if not status.get("result"):
                    raise OBSError(f"{request_type}: {status.get('comment') or status.get('code')}")
                return body.get("responseData") or {}


def _passwords() -> list[str]:
    """Every password worth trying: .env first, then OBS's own settings files."""
    found = [os.environ.get("OBS_WEBSOCKET_PASSWORD", "").strip()]
    # Every OBS install: the normal one and the Flatpak one can both exist,
    # and the running OBS may be either.
    for base in (d for d in OBS_DIRS if d.is_dir()):
        for name in ("user.ini", "global.ini"):
            path = base / name
            if path.is_file():
                found.append(_ini(path).get("OBSWebSocket", "ServerPassword", fallback=""))
        try:
            found.append(json.loads((base / "plugin_config/obs-websocket/config.json").read_text()).get("server_password", ""))
        except Exception:
            pass
    return list(dict.fromkeys(p for p in found if p)) or [""]


def _config_report() -> str:
    """Where OBS keeps its WebSocket settings and whether they match .env.
    Never prints a password."""
    env = os.environ.get("OBS_WEBSOCKET_PASSWORD", "").strip()
    parts = []
    for base in OBS_DIRS:
        if not base.is_dir():
            continue
        for name in ("user.ini", "global.ini"):
            path = base / name
            if path.is_file() and _ini(path).has_section("OBSWebSocket"):
                sec = _ini(path)["OBSWebSocket"]
                same = "same as .env" if env and sec.get("ServerPassword") == env else "NOT the .env password"
                parts.append(f"{path} (on={sec.get('ServerEnabled')}, auth={sec.get('AuthRequired')}, {same})")
        legacy = base / "plugin_config/obs-websocket/config.json"
        if legacy.is_file():
            try:
                cfg = json.loads(legacy.read_text())
                same = "same as .env" if env and cfg.get("server_password") == env else "NOT the .env password"
                parts.append(f"{legacy} (on={cfg.get('server_enabled')}, {same})")
            except Exception:
                parts.append(f"{legacy} (unreadable)")
    return "; ".join(parts) or "no OBS WebSocket settings found"


async def _connect_when_ready(wait_seconds: float) -> Optional[OBS]:
    deadline = time.time() + wait_seconds
    last = ""
    refused_since = 0.0
    while time.time() < deadline:
        refused = 0
        candidates = _passwords()
        for password in candidates:
            try:
                return await OBS(password).__aenter__()
            except OBSError:
                refused += 1
            except Exception as exc:
                last = str(exc)
                break
        if refused == len(candidates):
            # A freshly opened OBS can answer before its settings are loaded:
            # keep trying for 20 s before giving up on the password.
            refused_since = refused_since or time.time()
            if time.time() - refused_since > 20:
                logger.error("OBS: OBS refused every known WebSocket password (check OBS_WEBSOCKET_PASSWORD)")
                logger.error(f"OBS: WebSocket settings found: {_config_report()}")
                return None
        await asyncio.sleep(3)
    logger.warning(f"OBS: no answer after {wait_seconds:.0f}s ({last[:80]}). Is OBS open with its WebSocket server on?")
    return None


def _image_bytes(image_data: str) -> bytes:
    """OBS returns either raw base64 or a data URL; callers need bytes."""
    if "," in image_data and image_data[:32].lower().startswith("data:image"):
        image_data = image_data.split(",", 1)[1]
    return base64.b64decode(image_data)


async def current_program_scene() -> str:
    obs = await _connect_when_ready(6)
    if obs is None:
        raise OBSError("no remote control")
    try:
        data = await obs.call("GetCurrentProgramScene")
        return data.get("currentProgramSceneName") or data.get("sceneName") or ""
    finally:
        await obs.__aexit__()


async def set_program_scene(scene: str) -> str:
    """Switch OBS to a scene and return the previous scene name."""
    obs = await _connect_when_ready(6)
    if obs is None:
        raise OBSError("no remote control")
    try:
        before = (await obs.call("GetCurrentProgramScene")).get("currentProgramSceneName") or ""
        if scene and scene != before:
            await obs.call("SetCurrentProgramScene", {"sceneName": scene})
        return before
    finally:
        await obs.__aexit__()


async def capture_obs_frame(
    width: int,
    height: int,
    quality: int,
    save_path: str | Path | None = None,
    source_name: str = "",
) -> bytes:
    """Capture the rendered OBS output or a named source/scene.

    ``source_name`` defaults to the current program scene. Watchdogs keep this
    in memory; social screenshots pass ``save_path``.
    """
    obs = await _connect_when_ready(float(os.environ.get("OBS_CAPTURE_CONNECT_TIMEOUT", "6") or 6))
    if obs is None:
        raise OBSError("no remote control")
    try:
        if not source_name:
            source_name = (await obs.call("GetCurrentProgramScene")).get("currentProgramSceneName") or ""
        data = await obs.call(
            "GetSourceScreenshot",
            {
                "sourceName": source_name,
                "imageFormat": "jpg",
                "imageWidth": int(width),
                "imageHeight": int(height),
                "imageCompressionQuality": int(quality),
            },
        )
        image = _image_bytes(str(data.get("imageData") or ""))
        if save_path:
            path = Path(save_path)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(image)
        return image
    finally:
        await obs.__aexit__()


async def record_status() -> dict[str, Any]:
    obs = await _connect_when_ready(6)
    if obs is None:
        raise OBSError("no remote control")
    try:
        return await obs.call("GetRecordStatus")
    finally:
        await obs.__aexit__()


async def start_recording() -> bool:
    """Start OBS recording without touching streaming. True when recording."""
    obs = await _connect_when_ready(6)
    if obs is None:
        raise OBSError("no remote control")
    try:
        status = await obs.call("GetRecordStatus")
        if status.get("outputActive"):
            return True
        await obs.call("StartRecord")
        return True
    finally:
        await obs.__aexit__()


async def stop_recording() -> Optional[Path]:
    """Stop OBS recording and return the local output path when OBS reports it."""
    obs = await _connect_when_ready(6)
    if obs is None:
        raise OBSError("no remote control")
    try:
        status = await obs.call("GetRecordStatus")
        if not status.get("outputActive"):
            return None
        data = await obs.call("StopRecord")
        output = data.get("outputPath") or data.get("outputFilename") or ""
        return Path(output) if output else None
    finally:
        await obs.__aexit__()


# The Stage Browser source in use (thumbnail frames are taken from it).
STAGE_SOURCE = ""


async def _ready_godot_stage(obs: OBS, stage_loaded_since: Callable[[float], bool]) -> bool:
    """VR_WORLD_RENDERER=godot: the world scene shows the Godot window; ready once Godot (the Stage) has
    reported Mika and Luna drawn. Godot is started by mika-live.sh; it can take a minute to open."""
    global STAGE_SOURCE, WORLD_SCENE
    from .godot_stage import WINDOW_SOURCE, ensure_world_scene, follow_window, rebind_window, stage_window_open

    scene = os.environ.get("OBS_STAGE_SCENE", "").strip() or "Mika World"
    since = time.time()
    for attempt in range(36):
        await ensure_world_scene(obs, scene)
        if attempt == 0:
            await obs.call("SetCurrentProgramScene", {"sceneName": scene})
            logger.info(f"OBS: scene '{scene}' (the Godot window), waiting for the world to report Mika and Luna")
        STAGE_SOURCE = WINDOW_SOURCE
        WORLD_SCENE = scene
        await revive_v4l2_stage(obs)
        if stage_loaded_since(since - 30) and stage_window_open():   # drawn AND its window is there to capture
            await asyncio.sleep(2)
            await ensure_world_scene(obs, scene)   # the window is open now: the capture follows it
            await rebind_window(obs)               # (a restarted Godot can reuse the old window id)
            _keep_task(asyncio.create_task(follow_window(), name="godot-window-follow"))
            logger.info("OBS: the Godot world is drawn")
            return True
        await asyncio.sleep(5)
    return False


# The scene that is on air after the intro (the Stage's scene).
WORLD_SCENE = ""


async def _ready_stage(obs: OBS, stage_loaded_since: Callable[[float], bool]) -> bool:
    """The world scene on air: the Godot window (the Stage), ready once Mika and Luna are drawn."""
    return await _ready_godot_stage(obs, stage_loaded_since)


# ---- the encoder the outputs use must exist in THIS OBS session ----------------------------------------------
# NVENC's start-up self-test can fail when OBS opens while the GPU is busy ("[NVENC] Test process failed",
# 2026-10-17 01:37): the NVENC encoders are then missing for the whole session and Start Streaming / Start Recording
# fail with "Starting the output failed". Checked before streaming: OBS is reopened once (the test passes on a quiet
# start), and if NVENC is still missing the outputs switch to a hardware encoder that is there.
ENCODER_FALLBACKS = ("obs_nvenc_h264_tex", "obs_qsv11_v2", "ffmpeg_vaapi_tex", "obs_x264")
_ENCODER_RESTARTED = False

def _session_encoders() -> set[str]:
    """Video encoder ids listed in the current OBS session's log ("Available Encoders"), empty when unknown."""
    base = _obs_dir()
    logs = sorted((base / "logs").glob("*.txt"), key=lambda p: p.stat().st_mtime) if base and (base / "logs").is_dir() else []
    if not logs:
        return set()
    found, inside = set(), False
    for line in logs[-1].read_text(errors="replace").splitlines():
        if "Video Encoders:" in line:
            inside = True
            continue
        if inside:
            m = re.search(r"\t- (\S+) \(", line)
            if m:
                found.add(m.group(1))
            elif "Audio Encoders:" in line or "====" in line:
                break
    return found


async def ensure_encoder(obs: "OBS") -> "OBS":
    """The outputs' video encoder exists in this session, or OBS is reopened once / a working encoder is chosen.
    Returns the connection to use (a new one when OBS was reopened)."""
    global _ENCODER_RESTARTED
    try:
        enc = (await obs.call("GetProfileParameter", {"parameterCategory": "AdvOut", "parameterName": "Encoder"})).get("parameterValue") or ""
    except Exception:
        return obs
    have = _session_encoders()
    if not have or not enc or enc in have:
        return obs
    logger.warning(f"OBS: the stream encoder {enc} is missing in this session (NVENC self-test failed?)")
    if not _ENCODER_RESTARTED:
        _ENCODER_RESTARTED = True
        await obs.__aexit__(None, None, None)
        await close_obs(20)
        launch_obs(streaming=False)
        reopened = await _connect_when_ready(90)
        if reopened is None:
            raise OBSError("OBS did not come back after reopening it for its encoder")
        obs = reopened
        have = _session_encoders()
        if enc in have:
            logger.info(f"OBS: reopened, {enc} is there now")
            return obs
    pick = next((e for e in ENCODER_FALLBACKS if e in have), "")
    if pick:
        for name in ("Encoder", "RecEncoder"):
            await obs.call("SetProfileParameter", {"parameterCategory": "AdvOut", "parameterName": name, "parameterValue": pick})
        logger.warning(f"OBS: outputs switched from {enc} to {pick} for this session")
    return obs


async def revive_v4l2_stage(obs: "OBS") -> bool:
    """The headless stage reaches OBS as a V4L2 device: a source opened before the bridge wrote its first frame
    failed for good ("Unable to set input 0"); re-applying its settings opens it again. True when it draws."""
    from .godot_stage import WINDOW_SOURCE
    try:
        kinds = {i["inputName"]: i.get("inputKind", "") for i in (await obs.call("GetInputList")).get("inputs") or []}
        if kinds.get(WINDOW_SOURCE) != "v4l2_input":
            return True
        try:
            await obs.call("GetSourceScreenshot", {"sourceName": WINDOW_SOURCE, "imageFormat": "jpg", "imageWidth": 64})
            return True
        except OBSError:
            pass
        settings = (await obs.call("GetInputSettings", {"inputName": WINDOW_SOURCE})).get("inputSettings") or {}
        await obs.call("SetInputSettings", {"inputName": WINDOW_SOURCE, "inputSettings": dict(settings, device_id="")})
        await asyncio.sleep(0.5)
        await obs.call("SetInputSettings", {"inputName": WINDOW_SOURCE, "inputSettings": settings})
        await asyncio.sleep(2.0)
        await obs.call("GetSourceScreenshot", {"sourceName": WINDOW_SOURCE, "imageFormat": "jpg", "imageWidth": 64})
        logger.info("OBS: the stage device was reopened and draws again")
        return True
    except Exception as exc:
        logger.warning(f"OBS: the stage device does not draw yet ({_short(exc) if isinstance(exc, Exception) else exc})")
        return False


# ---- the stream day: hours live counted every minute; past midnight (Asia/Manila) the live title moves to the new
# day once (launch_days)
async def _day_tick() -> None:
    try:
        from . import launch_days
        new_day = launch_days.tick()
        if not new_day or not TARGET_BROADCAST:
            return
        from .settings import PublishSettings
        from .youtube import YouTubeClient
        s = PublishSettings.from_env(read_dotenv=False)
        client = YouTubeClient(s.youtube_client_id, s.youtube_client_secret, s.youtube_refresh_token)
        snippet = await asyncio.to_thread(client.get_snippet, TARGET_BROADCAST)
        title = launch_days.title_with_day(snippet.get("title", ""), new_day)
        await asyncio.to_thread(client.set_title_and_description, TARGET_BROADCAST, snippet, title, snippet.get("description", ""))
        logger.info(f"Stream day: past midnight, the live title is now '{title}'")
    except Exception as exc:
        logger.warning(f"Stream day: could not update the title ({_short(exc)})")


# ---- the disk: a long unattended stream must never fill /home --------------------------------------------------
# OBS records at ~26 Mbit/s (~12 GB an hour: one 3-hour recording was 39 GB). Clips start only with
# VR_CLIP_MIN_FREE_GB free (default 15); any recording is stopped below VR_RECORD_STOP_FREE_GB (default 5).
RECORD_DIR_FALLBACK = Path.home() / "Documents" / "Recordings"


def free_gb(path: Optional[Path] = None) -> float:
    p = path or RECORD_DIR_FALLBACK
    while not p.exists() and p != p.parent:
        p = p.parent
    return shutil.disk_usage(p).free / 1e9


async def guard_disk(obs: "OBS") -> None:
    """Stops a running recording when the recordings' disk is nearly full (checked every minute while streaming)."""
    limit = float(os.environ.get("VR_RECORD_STOP_FREE_GB", "5") or 5)
    try:
        rec_dir = Path((await obs.call("GetRecordDirectory")).get("recordDirectory") or RECORD_DIR_FALLBACK)
    except Exception:
        rec_dir = RECORD_DIR_FALLBACK
    free = free_gb(rec_dir)
    if free >= limit:
        return
    try:
        if (await obs.call("GetRecordStatus")).get("outputActive"):
            await obs.call("StopRecord")
            logger.warning(f"OBS: recording stopped, only {free:.1f} GB free on {rec_dir} (the stream goes on)")
    except Exception as exc:
        logger.warning(f"OBS: disk guard could not stop the recording: {_short(exc)}")


async def youtube_stream_key() -> str:
    """YOUTUBE_STREAM_KEY from .env, else the channel's default key from the
    YouTube API (same sign-in as the rest). Never logged."""
    key = os.environ.get("YOUTUBE_STREAM_KEY", "").strip()
    if key:
        return key
    try:
        from .settings import PublishSettings
        from .youtube import YouTubeClient

        s = PublishSettings.from_env(read_dotenv=False)
        if not s.youtube_ready:
            return ""
        client = YouTubeClient(s.youtube_client_id, s.youtube_client_secret, s.youtube_refresh_token)
        keys = await asyncio.to_thread(client.stream_keys)
    except Exception as exc:
        logger.warning(f"OBS: could not read the YouTube stream key: {str(exc)[:120]}")
        return ""
    if not keys:
        return ""
    chosen = next((k for k in keys if "default" in k["title"].lower()), keys[0])
    logger.info(f"OBS: using the YouTube stream key '{chosen['title']}'")
    return chosen["key"]


async def go_live(stage_loaded_since: Callable[[float], bool]) -> bool:
    """The whole start sequence. Sets STREAM_LIVE when the stream is up."""
    if not manage_obs():
        STREAM_LIVE.set()
        return False
    stream_key = await youtube_stream_key()
    prepare_obs_config(stream_key)
    if not obs_running():
        logger.info("OBS: opening it (minimized)")
        launch_obs(streaming=False)
    started = time.time()
    logger.info("OBS: waiting for OBS to answer (WebSocket server)")
    obs = await _connect_when_ready(90)
    if obs is None:
        # No remote control: restart OBS from the terminal, streaming at once.
        # The server is already up, so the Stage page loads straight away.
        logger.warning("OBS: no remote control, so OBS is reopened and told to stream from the terminal")
        await _terminal_stream(stream_key)
        return False
    logger.info("OBS: connected")
    try:
        obs = await ensure_encoder(obs)
        if stream_key:
            # Stream key mode: Start Streaming goes straight to YouTube, no
            # "Select stream" step from the account connection.
            try:
                await obs.call(
                    "SetStreamServiceSettings",
                    {
                        # The YouTube address written out: "auto" set this way left
                        # OBS "streaming" with nothing reaching YouTube.
                        "streamServiceType": "rtmp_custom",
                        "streamServiceSettings": {"server": YOUTUBE_RTMPS, "key": stream_key},
                    },
                )
            except Exception as exc:
                logger.debug(f"OBS: stream key not applied now: {exc}")
        streaming = (await obs.call("GetStreamStatus")).get("outputActive")
        if not streaming:
            await _tune_obs(obs)
        ready = await _ready_stage(obs, stage_loaded_since)
        if streaming:
            logger.info("OBS: already streaming (the Stage was reloaded)")
        else:
            if not ready:
                logger.error("OBS: the Stage never loaded, so the stream is NOT started. Check the Browser source.")
                return False
            from .prelive import PRELIVE

            if PRELIVE.active:
                # Publishing barrier: metadata, thumbnail and the broadcast are
                # ready and the go-live was confirmed, or nothing is sent.
                await obs.__aexit__()
                await PRELIVE.prepare(stage_frame)
                await PRELIVE.gate()
                obs = await _connect_when_ready(30)
                if obs is None:
                    raise OBSError("OBS stopped answering before Start Streaming")
            await asyncio.sleep(2)  # first frames drawn
            intro = await _intro_standby(obs)
            await obs.call("StartStream")
            if await _really_streaming(obs):
                logger.info(f"OBS: streaming started ({time.time() - started:.0f}s after the server)")
            else:
                # OBS said yes but nothing reached YouTube: try once more with
                # the YouTube address written out, then the terminal way.
                logger.warning("OBS: Start Streaming did not connect to YouTube, trying again")
                try:
                    await obs.call("StopStream")
                except Exception:
                    pass
                await asyncio.sleep(2)
                if stream_key:
                    await obs.call(
                        "SetStreamServiceSettings",
                        {"streamServiceType": "rtmp_custom", "streamServiceSettings": {"server": YOUTUBE_RTMPS, "key": stream_key}},
                    )
                await obs.call("StartStream")
                if not await _really_streaming(obs):
                    raise OBSError("OBS could not connect to YouTube twice")
                logger.info("OBS: streaming started on the second try")
        if not streaming:
            # YouTube's Go live runs while the intro plays; the world (and Mika's first words) after it
            _keep_task(asyncio.create_task(_go_live_then_follow_up(stream_key), name="youtube-go-live"))
            if intro:
                await _play_intro(obs)
            elif WORLD_SCENE:
                try:
                    await obs.call("SetCurrentProgramScene", {"sceneName": WORLD_SCENE})
                except Exception as exc:  # streaming already: never a reason to reopen OBS
                    logger.warning(f"OBS: could not show '{WORLD_SCENE}': {exc}")
    except Exception as exc:
        logger.warning(f"OBS: start sequence failed ({exc}), reopening OBS to stream from the terminal")
        try:
            await obs.__aexit__()
        except Exception:
            pass
        await _terminal_stream(stream_key)
        return False
    finally:
        try:
            await obs.__aexit__()
        except Exception:
            pass
    if streaming:
        _keep_task(asyncio.create_task(_go_live_then_follow_up(stream_key), name="youtube-go-live"))
    await asyncio.sleep(8)  # YouTube needs a few seconds to show the stream
    STREAM_LIVE.set()
    _clips_live()
    _keep_task(asyncio.create_task(watch_stream(stream_key), name="obs-watch"))
    return True


async def _intro_standby(obs: OBS) -> bool:
    """Before Start Streaming: the Intro scene on air with its video hidden (black), so the broadcast opens
    on the intro from its first frame. False when there is no intro (the Stage stays on air)."""
    from .godot_stage import INTRO_SOURCE, ensure_intro_scene

    try:
        scene = await ensure_intro_scene(obs)
        if not scene:
            return False
        item = await obs.call("GetSceneItemId", {"sceneName": scene, "sourceName": INTRO_SOURCE})
        await obs.call("SetSceneItemEnabled", {"sceneName": scene, "sceneItemId": item.get("sceneItemId"), "sceneItemEnabled": False})
        await obs.call("SetCurrentProgramScene", {"sceneName": scene})
        return True
    except Exception as exc:
        logger.warning(f"OBS: no intro this time ({exc})")
        return False


async def _play_intro(obs: OBS) -> None:
    """Streaming is confirmed: the intro plays once from the start, then the Stage's scene."""
    from .godot_stage import INTRO_SOURCE, intro_scene, play_intro_then

    try:
        scene = intro_scene()
        item = await obs.call("GetSceneItemId", {"sceneName": scene, "sourceName": INTRO_SOURCE})
        await obs.call("SetSceneItemEnabled", {"sceneName": scene, "sceneItemId": item.get("sceneItemId"), "sceneItemEnabled": True})
    except Exception as exc:
        logger.debug(f"OBS: intro item not shown: {exc}")
    await play_intro_then(obs, WORLD_SCENE or os.environ.get("OBS_STAGE_SCENE", "") or "Mika World")


async def _terminal_stream(stream_key: str) -> None:
    """The way that always worked: OBS closed and reopened with --startstreaming
    (the stream key is in its profile), then YouTube gets its Go live."""
    from .prelive import PRELIVE

    if PRELIVE.active and not (PRELIVE.status()["ready"] and PRELIVE.confirmed()):
        logger.error("OBS: not streaming from the terminal: the pre-live gate is not passed (see /prelive/status)")
        return
    await close_obs()
    prepare_obs_config(stream_key)  # OBS may have saved other settings when it closed
    if launch_obs(streaming=True):
        await asyncio.sleep(20)
        logger.info("OBS: reopened with streaming on")
        obs = await _connect_when_ready(20)
        if obs is not None:
            try:
                await _play_intro(obs)
            finally:
                try:
                    await obs.__aexit__()
                except Exception:
                    pass
    STREAM_LIVE.set()
    _clips_live()
    _keep_task(asyncio.create_task(_go_live_then_follow_up(stream_key), name="youtube-go-live"))
    _keep_task(asyncio.create_task(watch_stream(stream_key), name="obs-watch"))


async def stage_frame() -> bytes:
    """A real frame of the Stage source (thumbnail reference), 1536x864 JPEG."""
    return await capture_obs_frame(1536, 864, 92, source_name=STAGE_SOURCE)


async def _go_live_then_follow_up(stream_key: str) -> bool:
    live = await ensure_youtube_live(stream_key)
    if live and TARGET_BROADCAST:
        from .prelive import PRELIVE

        try:
            await PRELIVE.on_live(TARGET_BROADCAST)
        except Exception as exc:
            logger.warning(f"Pre-live follow-up failed: {exc}")
    return live


WATCH_EVERY = 60.0  # seconds between checks that OBS is still streaming
STALLED_RESTART = 180.0  # OBS "reconnecting" this long: the stream is stopped and started again


async def watch_stream(stream_key: str) -> None:
    """Nothing checked OBS after the start: a 2 minute internet drop at hour 7
    could end the stream while the girls played on for 9 hours to nobody.
    Every minute: is OBS still sending? Stopped twice in a row: started
    again (and YouTube's Go live done again). Reconnecting for 3 minutes:
    stopped and started. stop_and_close cancels this first (Ctrl+C)."""
    down = 0
    reconnecting_since = 0.0
    await asyncio.sleep(120)  # the start settles first
    while True:
        await asyncio.sleep(WATCH_EVERY)
        try:
            obs = await _connect_when_ready(10)
            if obs is None:
                logger.warning("OBS watch: OBS does not answer (closed or frozen?)")
                down += 1
                continue
            try:
                await revive_v4l2_stage(obs)
                await guard_disk(obs)
                await _day_tick()
                status = await obs.call("GetStreamStatus")
                if status.get("outputReconnecting"):
                    reconnecting_since = reconnecting_since or time.time()
                    if time.time() - reconnecting_since > STALLED_RESTART:
                        logger.warning("OBS watch: reconnecting for 3 minutes, starting the stream again")
                        await obs.call("StopStream")
                        await asyncio.sleep(3)
                        await obs.call("StartStream")
                        reconnecting_since = 0.0
                    continue
                reconnecting_since = 0.0
                if status.get("outputActive"):
                    if down:
                        logger.info("OBS watch: streaming again")
                    down = 0
                    continue
                down += 1
                if down >= 2:
                    logger.warning("OBS watch: OBS stopped streaming, starting it again")
                    await obs.call("StartStream")
                    down = 0
                    _keep_task(asyncio.create_task(_go_live_then_follow_up(stream_key), name="youtube-go-live"))
            finally:
                await obs.__aexit__()
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.debug(f"OBS watch: check failed: {exc}")


def _clips_live() -> None:
    from ..live.clip_marks import CLIPS

    CLIPS.set_live(time.time(), exact=False)


_TASKS: set = set()


def _keep_task(task: asyncio.Task) -> None:
    _TASKS.add(task)
    task.add_done_callback(_TASKS.discard)


async def ensure_youtube_live(stream_key: str, timeout: float = 300.0) -> bool:
    """OBS is sending, but YouTube can hold the stream in "Preparing" until
    someone clicks Go live (often after a few quick restarts). This does the
    click: the waiting broadcast on our stream key is moved to live, and if
    there is none, a new one is made, bound to the key and started.

    YOUTUBE_AUTO_GO_LIVE=0 turns it off. Never raises.
    """
    if os.environ.get("YOUTUBE_AUTO_GO_LIVE", "1").strip().lower() in ("0", "false", "no", "off"):
        return False
    if not stream_key:
        return False
    try:
        from .settings import PublishSettings
        from .youtube import YouTubeClient

        s = PublishSettings.from_env(read_dotenv=False)
        if not s.youtube_ready:
            return False
        client = YouTubeClient(s.youtube_client_id, s.youtube_client_secret, s.youtube_refresh_token)
    except Exception as exc:
        logger.debug(f"YouTube go live check unavailable: {exc}")
        return False

    async def call(fn, *args):
        return await asyncio.to_thread(fn, *args)

    async def status(bid: str) -> str:
        try:
            return await call(client.broadcast_status, bid)
        except Exception:
            return ""

    async def wait_for(bid: str, wanted: tuple[str, ...], seconds: float) -> str:
        life = ""
        stop = time.time() + seconds
        while time.time() < stop:
            life = await status(bid)
            if life in wanted:
                return life
            await asyncio.sleep(4)
        return life

    async def start(bid: str) -> bool:
        """The documented manual way: ready, preview (testing), then live."""
        life = await status(bid)
        if life in ("ready", "created"):
            try:
                await call(client.transition, bid, "testing")
                logger.info("YouTube: preview started")
            except Exception as exc:
                logger.info(f"YouTube: preview refused ({_short(exc)})")
            life = await wait_for(bid, ("testing", "live"), 60)
        if life == "live":
            return True
        try:
            await call(client.transition, bid, "live")
        except Exception as exc:
            logger.warning(f"YouTube: Go live refused ({_short(exc)})")
            return False
        if await wait_for(bid, ("live",), 60) == "live":
            logger.info("YouTube: Go live done, the stream is public")
            return True
        return False

    end = time.time() + timeout
    tried: set[str] = set()
    created = 0
    await asyncio.sleep(25)  # the normal auto start usually happens by now
    while time.time() < end:
        try:
            stream = await call(client.stream_for_key, stream_key)
            if not stream.get("id"):
                logger.warning("YouTube: no stream found for the stream key, cannot press Go live")
                return False
            # Only a broadcast that is really live AND fed by this stream key
            # counts. An older broadcast still marked active, or one stuck in
            # its preview, made this say "live" while viewers saw "Waiting".
            ours = [b for b in await call(client.active_broadcasts) if b["stream"] == stream["id"]]
            live = [b for b in ours if b["life"] == "live"]
            if live:
                set_target_broadcast(live[0]["id"])
                logger.info("YouTube: the stream is live")
                return True
            if stream.get("status") != "active":
                logger.info(f"YouTube: waiting for video to arrive (stream {stream.get('status') or 'unknown'})")
                await asyncio.sleep(10)
                continue
            stuck = [b for b in ours if b["life"] in ("testing", "testStarting", "liveStarting")]
            if stuck:
                set_target_broadcast(stuck[0]["id"])
                if await start(stuck[0]["id"]):
                    return True
                await asyncio.sleep(10)
                continue
            waiting = [b for b in await call(client.upcoming_broadcasts) if b["stream"] == stream["id"]]
            if os.environ.get("VR_TEST_STREAM", "").strip() == "1":
                waiting = [b for b in waiting if b["id"] == TARGET_BROADCAST]   # only the test's own unlisted broadcast
            fresh = [b for b in waiting if b["id"] not in tried]
            if fresh:
                broadcast = fresh[0]
                tried.add(broadcast["id"])
                set_target_broadcast(broadcast["id"])
                logger.warning("YouTube: the stream is waiting for Go live, starting it")
                if await start(broadcast["id"]):
                    return True
                if broadcast["id"] in _made_broadcasts():
                    # one of ours that YouTube will not start: remove it, so the
                    # channel does not fill up with "Upcoming" videos
                    try:
                        await call(client.delete_broadcast, broadcast["id"])
                        _forget_broadcast(broadcast["id"])
                        logger.info("YouTube: removed a broadcast that could not start")
                    except Exception as exc:
                        logger.debug(f"YouTube: could not remove it: {_short(exc)}")
                continue
            if created < 2 and os.environ.get("VR_TEST_STREAM", "").strip() != "1":
                created += 1
                logger.warning("YouTube: no broadcast can start on the stream key, making a new one")
                title, description = PENDING_DETAILS
                broadcast_id = await call(client.create_broadcast, title or "VR Agent LIVE 🔴", description)
                if broadcast_id:
                    _remember_broadcast(broadcast_id)
                    set_target_broadcast(broadcast_id)
                    await call(client.bind, broadcast_id, stream["id"])
                    tried.add(broadcast_id)
                    if await start(broadcast_id):
                        return True
                continue
        except Exception as exc:
            logger.warning(f"YouTube go live check failed: {_short(exc)}")
        await asyncio.sleep(15)
    logger.error("YouTube: still not live after 5 minutes. Open YouTube Studio and press Go live.")
    return False


# The broadcast we are trying to make live: titles and the thumbnail go on it
# even while it is still upcoming (no expensive search needed).
TARGET_BROADCAST = ""
# Title and description of the show, for a broadcast we have to make ourselves.
PENDING_DETAILS: tuple[str, str] = ("", "")
_MADE_FILE = Path("data/youtube_made_broadcasts.json")


def set_target_broadcast(broadcast_id: str) -> None:
    global TARGET_BROADCAST
    TARGET_BROADCAST = broadcast_id or TARGET_BROADCAST


def set_pending_details(title: str, description: str) -> None:
    global PENDING_DETAILS
    PENDING_DETAILS = (title, description)


def _made_broadcasts() -> list[str]:
    try:
        data = json.loads(_MADE_FILE.read_text())
        return [str(x) for x in data] if isinstance(data, list) else []
    except Exception:
        return []


def _remember_broadcast(broadcast_id: str) -> None:
    try:
        _MADE_FILE.parent.mkdir(parents=True, exist_ok=True)
        _MADE_FILE.write_text(json.dumps((_made_broadcasts() + [broadcast_id])[-50:]))
    except Exception:
        pass


def _forget_broadcast(broadcast_id: str) -> None:
    try:
        _MADE_FILE.write_text(json.dumps([b for b in _made_broadcasts() if b != broadcast_id]))
    except Exception:
        pass


def _short(exc: Exception) -> str:
    text = str(exc)
    match = re.search(r'"message":\s*"([^"]+)"', text)
    return (match.group(1) if match else text)[:160]


async def _really_streaming(obs: "OBS", seconds: float = 15) -> bool:
    """True once OBS is connected and the bytes sent keep growing."""
    end = time.time() + seconds
    last = -1
    while time.time() < end:
        await asyncio.sleep(2.5)
        try:
            status = await obs.call("GetStreamStatus")
        except Exception:
            continue
        sent = int(status.get("outputBytes") or 0)
        if status.get("outputActive") and not status.get("outputReconnecting") and last >= 0 and sent > last:
            return True
        last = sent if status.get("outputActive") else -1
    return False


def keep_task(task: asyncio.Task) -> None:
    """A background OBS/YouTube task that stop_and_close cancels (go-live)."""
    _keep_task(task)


async def stop_and_close() -> None:
    """Stop streaming, then close OBS (only when VR_START_OBS manages it)."""
    # A start still running (waiting for OBS, reopening it, YouTube's Go live)
    # would open OBS again right after it is closed: stop those first.
    me = asyncio.current_task()
    for task in list(_TASKS):
        if task is not me and not task.done():
            task.cancel()
    try:
        obs = await _connect_when_ready(6)
        if obs is None:
            raise OBSError("no remote control")
        try:
            status = await obs.call("GetStreamStatus")
            if status.get("outputActive"):
                await obs.call("StopStream")
                logger.info("OBS: streaming stopped")
                for _ in range(20):
                    await asyncio.sleep(0.5)
                    if not (await obs.call("GetStreamStatus")).get("outputActive"):
                        break
        finally:
            await obs.__aexit__()
    except Exception as exc:
        logger.warning(f"OBS: could not stop streaming: {exc}")
    if manage_obs():
        try:
            await close_obs()
        except Exception as exc:
            logger.debug(f"OBS: close failed: {exc}")
