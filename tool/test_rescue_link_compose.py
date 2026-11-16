#!/usr/bin/env python3
"""Guard Rescue Link's production database and OIDC Compose wiring."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
compose = (ROOT / "infra" / "docker-compose.yml").read_text(encoding="utf-8")
example = (ROOT / "infra" / ".env.example").read_text(encoding="utf-8")
runbook = (ROOT / "infra" / "PRODUCTION_RUNBOOK.md").read_text(encoding="utf-8")
production_endpoints = (ROOT / "infra" / "PRODUCTION_ENDPOINTS.template.env").read_text(encoding="utf-8")


def service_block(name: str, next_service: str) -> str:
    start_marker = f"  {name}:\n"
    end_marker = f"  {next_service}:\n"
    if start_marker not in compose or end_marker not in compose:
        raise SystemExit(f"Compose is missing the {name} service boundary.")
    return compose.split(start_marker, 1)[1].split(end_marker, 1)[0]


keycloak = service_block("keycloak", "source-gateway")
source_gateway = service_block("source-gateway", "rescue-link")
rescue_link = service_block("rescue-link", "martin")

for fragment in (
    "KC_HOSTNAME: ${KEYCLOAK_HOSTNAME:?set in .env}",
    'KC_HOSTNAME_STRICT: "true"',
    "KC_PROXY_HEADERS: ${KEYCLOAK_PROXY_HEADERS:-xforwarded}",
):
    if fragment not in keycloak:
        raise SystemExit(f"Keycloak must pin its issuer and trust the configured reverse-proxy headers: {fragment}")
if "KEYCLOAK_HOSTNAME=http://keycloak:8080" not in example:
    raise SystemExit("Local Compose Keycloak hostname must match the local OIDC issuer.")
if "KEYCLOAK_HOSTNAME=https://auth.espanaoutdoor.es" not in production_endpoints:
    raise SystemExit("Production endpoint template must pin the public Keycloak hostname.")
if "KEYCLOAK_PROXY_HEADERS=xforwarded" not in production_endpoints:
    raise SystemExit("Production endpoint template must declare the reverse-proxy header mode.")
if "X-Forwarded-Host" not in runbook or "overwrite" not in runbook or "KC_HOSTNAME_STRICT=true" not in runbook:
    raise SystemExit("Production runbook must require trusted overwritten proxy headers and strict Keycloak hostname.")

for name, block in (("Source Gateway", source_gateway), ("Rescue Link", rescue_link)):
    if "DATABASE_URL: ${DATABASE_URL:?set in .env}" not in block:
        raise SystemExit(f"{name} must use the required configurable DATABASE_URL.")
    if "sslmode=disable" in block:
        raise SystemExit(f"{name} must not hardcode a non-TLS database URL.")

if "RESCUE_LINK_OIDC_AUDIENCE: ${RESCUE_LINK_OIDC_AUDIENCE:?set in .env}" not in rescue_link:
    raise SystemExit("Rescue Link must require its dedicated resource-server audience.")
if "ALLOW_HTTP_DEV: ${ALLOW_HTTP_DEV:-false}" not in rescue_link:
    raise SystemExit("Rescue Link must default to HTTPS-only operation.")
if "RESCUE_LINK_OIDC_AUDIENCE=espana-outdoors-rescue-api" not in example:
    raise SystemExit("The local environment example must document the dedicated Rescue Link audience.")
if "ALLOW_HTTP_DEV=true" not in example or "sslmode=disable" not in example:
    raise SystemExit("The local example must explicitly scope its non-TLS DSN to development.")
if "PostgreSQL" not in runbook or "TLS" not in runbook:
    raise SystemExit("The production runbook must document PostgreSQL TLS.")

print("source_gateway_database_dsn=required_config")
print("rescue_link_database_dsn=shared_tls_aware_config")
print("rescue_link_audience=required_dedicated")
print("http_development=explicit_opt_in")
print("production_database_tls=runbook_documented")
