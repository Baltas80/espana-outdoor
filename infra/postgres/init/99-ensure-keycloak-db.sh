#!/usr/bin/env bash
# Runs from the official Postgres image's docker-entrypoint-initdb.d hook.
# The entrypoint sources non-executable .sh files, so this script works with
# the repository's read-only bind mount without requiring chmod in Git.
set -Eeuo pipefail

: "${POSTGRES_USER:?POSTGRES_USER must be set by the Postgres image}"
: "${POSTGRES_DB:?POSTGRES_DB must be set by the Postgres image}"
: "${KEYCLOAK_DB_PASSWORD:?KEYCLOAK_DB_PASSWORD is required for Keycloak}"

psql \
  --username "${POSTGRES_USER}" \
  --dbname "${POSTGRES_DB}" \
  --set ON_ERROR_STOP=1 \
  --set keycloak_password="${KEYCLOAK_DB_PASSWORD}" <<'SQL'
SELECT format('CREATE ROLE keycloak LOGIN PASSWORD %L', :'keycloak_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'keycloak')
\gexec

ALTER ROLE keycloak WITH LOGIN PASSWORD :'keycloak_password';

SELECT 'CREATE DATABASE keycloak OWNER keycloak'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'keycloak')
\gexec

ALTER DATABASE keycloak OWNER TO keycloak;
SQL
