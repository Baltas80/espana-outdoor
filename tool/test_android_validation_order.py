#!/usr/bin/env python3
"""Guard the Android emulator validation order and cancellation policy.

The native online/download/offline routing proof is the highest-value check.
Run it before the release APK smoke so an interrupted emulator run does not
spend its first validation window only on the separate UI smoke. New commits
must queue behind an active emulator run instead of cancelling its evidence.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "staging-android.yml"
ORCHESTRATOR = ROOT / "tool" / "staging_android_emulator_validation.sh"

workflow = WORKFLOW.read_text(encoding="utf-8")
orchestrator = ORCHESTRATOR.read_text(encoding="utf-8")

if "cancel-in-progress: false" not in workflow:
    raise SystemExit(
        "Android staging must not cancel an active emulator run when a newer "
        "commit is queued; preserve its diagnostic artifacts."
    )

route_call = 'bash "${script_dir}/staging_android_route_integration.sh"'
smoke_call = 'bash "${script_dir}/smoke_android_map.sh" "${apk_path}" online'
route_index = orchestrator.find(route_call)
smoke_index = orchestrator.find(smoke_call)
if route_index < 0 or smoke_index < 0:
    raise SystemExit("Both Android routing integration and release map smoke must run.")
if route_index > smoke_index:
    raise SystemExit(
        "Run online/download/offline routing before the separate release APK map smoke."
    )

for phase in ("online_offline_routing", "map_smoke"):
    if f"ANDROID_VALIDATION_PHASE_RESULT phase={phase}" not in orchestrator:
        raise SystemExit(f"Android validation must report the {phase} result independently.")

if "if: always()" not in workflow:
    raise SystemExit("Android staging must retain unconditional evidence-upload steps.")

print("android_validation_order=routing_before_release_smoke")
print("android_validation_concurrency=non_cancelling")
print("android_validation_evidence_upload=always")
