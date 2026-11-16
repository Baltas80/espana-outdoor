#!/usr/bin/env bash
# Exercise the exact Postgres initdb hook against a disposable PostgreSQL instance.
# No production data, credentials, ports, or persistent volumes are used.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${POSTGRES_TEST_IMAGE:-postgis/postgis:18-3.6}"
CONTAINER="espana-keycloak-db-test-${GITHUB_RUN_ID:-local}-$$"
INITIAL_PASSWORD="initial-keycloak-test-password"
ROTATED_PASSWORD="rotated-keycloak-test-password"

cleanup() {
  docker rm --force "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --detach \
  --name "$CONTAINER" \
  --env POSTGRES_USER=espana \
  --env POSTGRES_DB=espana_outdoor \
  --env POSTGRES_PASSWORD=postgres-test-password \
  --env KEYCLOAK_DB_PASSWORD="$INITIAL_PASSWORD" \
  --volume "$ROOT/infra/postgres/init:/docker-entrypoint-initdb.d:ro" \
  "$IMAGE" >/dev/null

# Require TCP readiness: the initdb temporary server accepts only Unix sockets
# and must not be mistaken for the final server after all init scripts complete.
ready=false
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" pg_isready --host 127.0.0.1 --username espana --dbname espana_outdoor >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done
if [[ "$ready" != true ]]; then
  docker inspect --format 'container_status={{.State.Status}} exit_code={{.State.ExitCode}} error={{.State.Error}}' "$CONTAINER" || true
  docker logs "$CONTAINER" || true
  echo "PostgreSQL did not become ready." >&2
  exit 1
fi

verify_keycloak_login() {
  local password="$1"
  local expected="$2"
  local actual
  actual="$(docker exec --env PGPASSWORD="$password" "$CONTAINER" \
    psql --host 127.0.0.1 --username keycloak --dbname keycloak \
      --set ON_ERROR_STOP=1 --tuples-only --no-align \
      --command "SELECT current_user || '/' || current_database() || '/' || pg_get_userbyid((SELECT datdba FROM pg_database WHERE datname = current_database()))")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Unexpected Keycloak database identity: %s\n' "$actual" >&2
    return 1
  fi
}

verify_keycloak_login "$INITIAL_PASSWORD" "keycloak/keycloak/keycloak"

# Re-run the hook against existing objects with a rotated password. This proves
# idempotence and verifies that ALTER ROLE applies the configured secret.
docker exec --env KEYCLOAK_DB_PASSWORD="$ROTATED_PASSWORD" "$CONTAINER" \
  bash /docker-entrypoint-initdb.d/99-ensure-keycloak-db.sh

verify_keycloak_login "$ROTATED_PASSWORD" "keycloak/keycloak/keycloak"

echo "postgres_keycloak_bootstrap=created_role_and_database"
echo "postgres_keycloak_bootstrap=idempotent_password_rotation"
