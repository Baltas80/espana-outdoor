#!/usr/bin/env python3
"""Enforce upper bounds for GitHub Actions jobs that build or test the app."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
STAGING_WORKFLOW = ROOT / ".github" / "workflows" / "staging-android.yml"


def job_block(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^  {re.escape(name)}:\n(.*?)(?=^  [a-z0-9-]+:|\Z)",
        source,
    )
    if match is None:
        raise SystemExit(f"Workflow is missing job: {name}")
    return match.group(1)


ci = CI_WORKFLOW.read_text(encoding="utf-8")
staging = STAGING_WORKFLOW.read_text(encoding="utf-8")

for job, minutes in (
    ("rescue-link", 20),
    ("source-gateway", 30),
    ("flutter", 75),
    ("ios-build", 60),
):
    if not re.search(rf"(?m)^    timeout-minutes: {minutes}$", job_block(ci, job)):
        raise SystemExit(f"CI job {job} must have a job-level {minutes}-minute timeout.")

if not re.search(r"(?m)^    timeout-minutes: 105$", job_block(staging, "android-staging")):
    raise SystemExit("Android staging must have a 105-minute job-level timeout for three APK builds and the bounded A/B smoke.")

print("github_actions_job_timeouts=true")
