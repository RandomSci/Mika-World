"""mika-live.sh turns CPU turbo boost off while the stream runs and puts it back exactly as it was on exit
(Selwyn, 2026-10-18). Run against a stand-in for /sys/.../no_turbo and a fake sudo."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _run(tmp_path, before: str, script: str) -> tuple[str, str]:
    flag = tmp_path / "no_turbo"
    flag.write_text(before)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "sudo").write_text('#!/bin/sh\n[ "$1" = -n ] && shift\nexec "$@"\n')
    (bin_dir / "sudo").chmod(0o755)
    helper = bin_dir / "mika-turbo"     # the real helper, pointed at the stand-in file
    helper.write_text((ROOT / "tools" / "mika-turbo").read_text().replace(
        "/sys/devices/system/cpu/intel_pstate/no_turbo", str(flag)))
    helper.chmod(0o755)
    block = subprocess.run(["sed", "-n", "/^NO_TURBO=/,/^turbo_off$/p", str(ROOT / "mika-live.sh")],
                           capture_output=True, text=True, check=True).stdout
    block = block.replace("NO_TURBO=/sys/devices/system/cpu/intel_pstate/no_turbo", f"NO_TURBO={flag}")
    block = block.replace("MIKA_TURBO=/usr/local/sbin/mika-turbo", f"MIKA_TURBO={helper}")
    out = subprocess.run(["bash", "-c", block + "\n" + script], capture_output=True, text=True,
                         env={"PATH": f"{bin_dir}:/usr/bin:/bin"})
    return out.stdout, flag.read_text().strip()


def test_turbo_is_off_during_the_stream_and_restored_on_exit(tmp_path):
    out, after = _run(tmp_path, "0", 'echo "during=$(cat $NO_TURBO)"')
    assert "during=1" in out and "off for the stream" in out
    assert after == "0" and "back on" in out          # the EXIT trap put it back


def test_turbo_already_off_is_left_alone(tmp_path):
    out, after = _run(tmp_path, "1", 'echo "during=$(cat $NO_TURBO)"')
    assert "during=1" in out and after == "1" and "back on" not in out


def test_the_helper_accepts_only_on_and_off(tmp_path):
    helper = ROOT / "tools" / "mika-turbo"
    for bad in ("", "1", "on; id", "--help"):
        r = subprocess.run(["sh", str(helper), bad], capture_output=True, text=True)
        assert r.returncode == 2 and "usage" in r.stderr
