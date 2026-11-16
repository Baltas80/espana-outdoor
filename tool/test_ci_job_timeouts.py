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


def has_job_timeout(block: str, minutes: int) -> bool:
    return re.search(rf"(?m)^    timeout-minutes: {minutes}$", block) is not None


step_only_timeout = """    steps:
      - name: smoke
        timeout-minutes: 75
"""
if has_job_timeout(step_only_timeout, 75):
    raise SystemExit("A step-level timeout must not satisfy the job-level guard.")


ci = CI_WORKFLOW.read_text(encoding="utf-8")
staging = STAGING_WORKFLOW.read_text(encoding="utf-8")

for job, minutes in (
    ("rescue-link", 20),
    ("source-gateway", 30),
    ("flutter", 75),
    ("ios-build", 60),
):
    if not has_job_timeout(job_block(ci, job), minutes):
        raise SystemExit(f"CI job {job} must have a job-level {minutes}-minute timeout.")

if not has_job_timeout(job_block(staging, "android-staging"), 75):
    raise SystemExit("Android staging must have a job-level 75-minute timeout.")

print("github_actions_job_timeouts=true")
