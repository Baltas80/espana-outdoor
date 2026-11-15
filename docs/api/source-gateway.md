# Source Gateway contract

The mobile/web client does not call AEMET, MITECO, IGN/CNIG or emergency providers with provider credentials. The first-party Source Gateway performs provider authentication, normalization, attribution and freshness checks.

## Health

`GET /v1/sources/{sourceId}/health`

```json
{
  "kind": "official",
  "status": "healthy",
  "observedAt": "2026-09-23T12:00:00Z",
  "expiresAt": "2026-09-23T13:00:00Z",
  "licenseUrl": "https://example.invalid/license",
  "attribution": "Source attribution"
}
```

Allowed `kind`: `official`, `community`, `derived`.

Allowed `status`: `healthy`, `degraded`, `unavailable`, `stale`.

The health envelope is closed: unknown fields are invalid. `licenseUrl` must use HTTPS and timestamps must be valid date-time strings.

## Data

`GET /v1/sources/{sourceId}`

Query parameters are source-specific but must never contain provider secrets.

The response is a single JSON envelope. A top-level JSON array is invalid and must be rejected by clients.

```json
{
  "data": [],
  "provenance": {
    "source": "AEMET OpenData",
    "licenseUrl": "https://example.invalid/license",
    "observedAt": "2026-09-23T12:00:00Z"
  },
  "freshness": {
    "status": "current",
    "fetchedAt": "2026-09-23T12:00:00Z"
  }
}
```

The data envelope has exactly three top-level fields: `data`, `provenance` and `freshness`. The provenance and freshness objects are also closed and reject unknown fields.

The generic gateway contract requires each data item to be a JSON object. Item fields remain source-specific and are validated by the corresponding source adapter.

The client preserves the envelope metadata as part of the source data snapshot. `freshness.fetchedAt` is the retrieval timestamp and `provenance.observedAt` is the provider/source observation timestamp; consumers must not replace these with a later health-check timestamp.

## Alerts normalized record

`GET /v1/sources/alerts`

```json
{
  "data": [
    {
      "id": "stable-provider-id",
      "title": "Example alert",
      "level": "yellow",
      "kind": "ALERTA_OFICIAL",
      "source": "AEMET",
      "description": "Provider-supplied explanation",
      "updatedAt": "2026-09-23T12:00:00Z",
      "expiresAt": "2026-09-23T18:00:00Z",
      "certainty": "high"
    }
  ],
  "provenance": {
    "source": "AEMET OpenData",
    "licenseUrl": "https://example.invalid/license",
    "observedAt": "2026-09-23T12:00:00Z"
  },
  "freshness": {
    "status": "current",
    "fetchedAt": "2026-09-23T12:00:00Z"
  }
}
```

The gateway must reject or quarantine malformed upstream records instead of passing them through as trusted information.

## Schema enforcement

The public contract is intentionally closed for its transport envelope: unknown fields, legacy top-level array responses, missing provenance/freshness metadata and invalid freshness states are rejected by the Flutter gateway client.

The machine-readable generic contract is `docs/api/source-gateway.schema.json`.

Source-specific item schemas must be versioned independently from the transport envelope so the generic gateway client does not become coupled to one provider.

## Shared identity and canonical profile

`GET /v1/me` provisions or returns the canonical profile for the authenticated subject. `PATCH /v1/me` updates only `displayName`; clients cannot choose a subject, profile UUID or email.

Both endpoints require a cryptographically verified Keycloak **access token**:
- `iss` must match `OIDC_ISSUER`.
- `aud` must contain the dedicated resource-server audience configured by `OIDC_AUDIENCE` (for example, `espana-outdoors-api`). This is not the public client ID used by the web/Android authorization flow.
- The JWT payload must contain `typ=Bearer`. ID tokens (`typ=ID`), refresh tokens and tokens without a type are rejected.
- The subject is derived from the verified token. Email is persisted/returned only when `email_verified=true`.

Configure a Keycloak audience mapper to add the API audience to the **access token**. Do not rely on the frontend client's own audience alone. The service verifies the resource audience independently of `azp`, which remains the client that obtained the access token.

Example response:

```json
{
  "id": "server-generated-uuid",
  "displayName": "Outdoor User",
  "email": "verified@example.test",
  "createdAt": "2026-11-15T00:00:00Z"
}
```

PostgreSQL generates the canonical UUID. The subject remains internal and is never returned to clients.

## Security requirements

- Provider API keys stay server-side.
- No emergency exact location is sent to upstream providers unless explicitly required and authorized.
- Source responses are cached with source-specific TTLs and stale-state semantics.
- Every transformation preserves provenance.
- The gateway must fail closed for missing critical metadata.
- Rate limiting, request authentication, audit logging and abuse controls belong at the gateway/backend layer.
