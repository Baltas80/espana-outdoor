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
    raise SystemExit("Android staging must have a 105-minute job-level timeout for build, upload and smoke evidence.")

smoke_step = re.search(
    r"(?ms)^      - name: Android map native smoke\n(.*?)(?=^      - name: Upload Android map smoke evidence)",
    staging,
)
if smoke_step is None:
    raise SystemExit("Android staging is missing its bounded native smoke step.")
if not re.search(r"(?m)^        timeout-minutes: 55$", smoke_step.group(1)):
    raise SystemExit("Android map native smoke must have a 55-minute step timeout.")
if not re.search(r"(?m)^          emulator-boot-timeout: 600$", smoke_step.group(1)):
    raise SystemExit("Android emulator boot must be bounded to 600 seconds.")

def step_block(source: str, name: str) -> str:
    lines = source.splitlines()
    marker = f"      - name: {name}"
    try:
        start = lines.index(marker)
    except ValueError as exc:
        raise SystemExit(f"Workflow is missing step: {name}") from exc
    end = next(
        (index for index in range(start + 1, len(lines)) if lines[index].startswith("      - name: ")),
        len(lines),
    )
    return "\n".join(lines[start:end])


for workflow_name, workflow_source in (("CI", ci), ("Android staging", staging)):
    setup_java = step_block(workflow_source, "Setup Java 21")
    setup_lines = {line.strip() for line in setup_java.splitlines()}
    if "cache: gradle" not in setup_lines:
        raise SystemExit(f"{workflow_name} must cache Gradle dependencies with setup-java.")
    if "cache-dependency-path: |" not in setup_lines:
        raise SystemExit(f"{workflow_name} must key the Gradle cache from committed Android build files.")

print("github_actions_job_timeouts=true")
