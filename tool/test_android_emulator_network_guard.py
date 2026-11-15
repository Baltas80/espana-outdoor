#!/usr/bin/env python3
"""Exercise the CI emulator network preflight with a deterministic fake adb."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tool" / "ensure_android_emulator_online.sh"


class AndroidEmulatorNetworkGuardTests(unittest.TestCase):
    def make_fake_adb(self, directory: Path) -> Path:
        adb = directory / "adb"
        adb.write_text(
            """#!/usr/bin/env python3
import os
import sys

args = sys.argv[1:]
log = os.environ.get("FAKE_ADB_LOG")
if log:
    with open(log, "a", encoding="utf-8") as stream:
        stream.write(" ".join(args) + "\\n")

if args[-1:] == ["get-state"]:
    print("device")
elif args[-1:] == ["airplane_mode_on"]:
    print("0")
elif "connect-network" in args:
    if os.environ.get("FAKE_ADB_WIFI_CONNECT_SUCCEEDS") == "true":
        print("Success")
    else:
        print("Unable to connect")
        raise SystemExit(1)
elif "wifi" in args and "status" in args:
    log_text = open(log, encoding="utf-8").read() if log and os.path.exists(log) else ""
    connected = os.environ.get("FAKE_ADB_WIFI_CONNECTED") == "true"
    connected = connected or (
        os.environ.get("FAKE_ADB_WIFI_CONNECT_SUCCEEDS") == "true"
        and "connect-network VirtWifi open" in log_text
    )
    print("Wifi is connected" if connected else "Wifi is enabled")
elif "dumpsys" in args and "connectivity" in args:
    print("Active default network: 101")
    suffix = "&VALIDATED" if os.environ.get("FAKE_ADB_VALIDATED") == "true" else ""
    print("  NetworkCapabilities: INTERNET&NOT_RESTRICTED&TRUSTED" + suffix)
elif "get" in args and "wifi_on" in args:
    print("1")
""",
            encoding="utf-8",
        )
        adb.chmod(0o755)
        return adb

    def run_guard(self, *, validated: bool, timeout: str = "2", ci: bool = True, wifi_connects: bool = True):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            adb = self.make_fake_adb(directory)
            log = directory / "adb.log"
            env = os.environ.copy()
            env.update(
                {
                    "ANDROID_EMULATOR_CI": "true" if ci else "false",
                    "ADB": str(adb),
                    "FAKE_ADB_VALIDATED": "true" if validated else "false",
                    "FAKE_ADB_WIFI_CONNECTED": "false",
                    "FAKE_ADB_WIFI_CONNECT_SUCCEEDS": "true" if wifi_connects else "false",
                    "FAKE_ADB_LOG": str(log),
                    "ANDROID_EMULATOR_NETWORK_TIMEOUT_SECONDS": timeout,
                    "ANDROID_EMULATOR_WIFI_CONNECT_WAIT_SECONDS": "1",
                    "ANDROID_SERIAL": "emulator-test",
                }
            )
            result = subprocess.run(
                ["bash", str(SCRIPT)],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            commands = log.read_text(encoding="utf-8") if log.exists() else ""
            return result, commands

    def test_skips_outside_ci_without_touching_adb(self) -> None:
        result, commands = self.run_guard(validated=False, ci=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("preflight=skipped", result.stdout)
        self.assertEqual(commands, "")

    def test_enables_radios_connects_virtual_wifi_and_requires_validated_default_network(self) -> None:
        result, commands = self.run_guard(validated=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("online=validated wifi=connected", result.stdout)
        self.assertIn("airplane-mode disable", commands)
        self.assertIn("svc wifi enable", commands)
        self.assertIn("svc data enable", commands)
        self.assertIn("cmd wifi connect-network VirtWifi open", commands)
        self.assertIn("cmd wifi status", commands)
        self.assertIn("dumpsys connectivity", commands)

    def test_fails_when_default_network_is_not_validated(self) -> None:
        result, _ = self.run_guard(validated=False, timeout="1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("did not obtain a connected, validated internet default network", result.stdout)

    def test_rejects_stale_validated_capabilities_without_wifi_association(self) -> None:
        result, commands = self.run_guard(validated=True, timeout="1", wifi_connects=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("wifi_status=Wifi is enabled", result.stdout)
        self.assertIn("cmd wifi connect-network VirtWifi open", commands)


if __name__ == "__main__":
    unittest.main()
