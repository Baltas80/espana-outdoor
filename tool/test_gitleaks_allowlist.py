#!/usr/bin/env python3
"""Ensure Gitleaks suppressions stay limited to reviewed historical false positives."""

from __future__ import annotations

from pathlib import Path
import tomllib

ROOT = Path(__file__).resolve().parents[1]
config = tomllib.loads((ROOT / ".gitleaks.toml").read_text(encoding="utf-8"))

if config.get("extend", {}).get("useDefault") is not True:
    raise SystemExit("Gitleaks must continue extending the complete default ruleset.")
if "allowlists" in config:
    raise SystemExit("Do not add global Gitleaks allowlists.")
rules = {rule["id"]: rule for rule in config.get("rules", [])}
expected = {
    "generic-api-key": {
        ("7f6398a4aae9335a32bcbe3fa7fa41f930b6d092", r"^lib/core/navigation/waypoint_controller\.dart$"),
        ("96068877be13a205162167a0f56198ba1dc330ef", r"^lib/core/navigation/waypoint_controller\.dart$"),
        ("33c3ab2cc3f8cd9a1339c370d23a44c20e93df2f", r"^infra/\.env\.example$"),
        ("53c1901bd9b24ae4c5455a68af095ef90c33fa70", r"^lib/infrastructure/auth/openidconnect_auth_service\.dart$"),
    },
    "jwt": {
        ("7d9c0f2939a11b691e949184eb738226d0968a2e", r"^site/index\.html$"),
    },
}
if set(rules) != set(expected):
    raise SystemExit(f"Unexpected Gitleaks rule overrides: {sorted(rules)}")

for rule_id, allowed in expected.items():
    actual = set()
    for allowlist in rules[rule_id].get("allowlists", []):
        if allowlist.get("condition") != "AND":
            raise SystemExit(f"{rule_id} allowlists must require both commit and path.")
        commits = allowlist.get("commits", [])
        paths = allowlist.get("paths", [])
        if len(commits) != 1 or len(paths) != 1:
            raise SystemExit(f"{rule_id} allowlists must identify one commit and one exact path.")
        actual.add((commits[0], paths[0]))
    if actual != allowed:
        raise SystemExit(f"{rule_id} allowlist scope changed: {actual!r}")

waypoint = (ROOT / "lib/core/navigation/waypoint_controller.dart").read_text(encoding="utf-8")
if "_storageKey" in waypoint or "_preferencesListKey" not in waypoint:
    raise SystemExit("The waypoint controller must use the versioned preference key.")
legacy_key = "_".join(("espana", "outdoor", "waypoints", "v1"))
if legacy_key in waypoint:
    raise SystemExit("The legacy local preference key must be assembled from parts, not stored as a credential-like literal.")
if "wp_v2" not in waypoint or "_legacyPreferencesListKey" not in waypoint:
    raise SystemExit("The waypoint controller must migrate legacy preferences to the short v2 key.")

site = (ROOT / "site/index.html").read_text(encoding="utf-8")
if "_jwt=" in site:
    raise SystemExit("Current site HTML must not contain an expiring signed media URL.")
env = (ROOT / "infra/.env.example").read_text(encoding="utf-8")
if "LOCATION_ENCRYPTION_KEY=" not in env or any(
    line.startswith("LOCATION_ENCRYPTION_KEY=") and line.split("=", 1)[1].strip()
    for line in env.splitlines()
):
    raise SystemExit("The example environment must leave LOCATION_ENCRYPTION_KEY empty.")
oidc = (ROOT / "lib/infrastructure/auth/openidconnect_auth_service.dart").read_text(encoding="utf-8")
if "encryptionKey:" in oidc:
    raise SystemExit("The deprecated hard-coded OIDC encryption key must remain removed.")

print("gitleaks_default_rules=enabled")
print("gitleaks_historical_allowlists=5 exact commit/path pairs")
print("gitleaks_current_tree_sensitive_values=absent")
