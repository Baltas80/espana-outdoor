# España Outdoor — Production Readiness Matrix

This document separates repository-complete work from dependencies that require external infrastructure, credentials, contracts, or physical devices.

Status vocabulary:
- **HECHO**: backed by repository/CI/artifact/test evidence.
- **PREPARADO**: repository implementation is ready but external evidence is missing.
- **PENDIENTE**: technical work remains in the repository.
- **BLOQUEADO**: requires an external owner action, credential, account, contract, domain, or physical device.

| Area | Repository / CI status | External / physical | Release gate |
|---|---|---|---|
| CI | **HECHO** — CI run 36084587261 succeeded on commit `18aa5080b3f7245c59c22e29b5e460972929dd8a` | — | Keep CI green |
| Android release | **HECHO** — release APK/AAB build and release manifest completed in the successful CI run | **BLOQUEADO** for physical validation until a device is available | Install and execute physical Android QA |
| Android artifacts | **HECHO** — `android-release` artifact exists; manifest contains APK/AAB metadata and SHA-256 values | — | Verify artifact against intended release candidate |
| iOS release | **HECHO** — iOS release build job completed successfully in CI | **BLOQUEADO** for physical/store validation until device + Apple account evidence exists | Physical iOS QA and signing/store validation |
| LAND visual pack | **HECHO** — LAND-01..07 plus flora/fauna visual assets are present in repository history | Physical/device visual QA remains | Verify rendering in release artifact |
| Mapbox offline regions | **PENDIENTE** — SDK integration must be verified on the target Android build | **BLOQUEADO** until device-level download and airplane-mode reopening evidence exists | Download, persistence, cold reopen and airplane-mode rendering |
| Valhalla | **PREPARADO** — routing/elevation integration and CI tests exist | **BLOQUEADO** until a production HTTPS routing host with real tiles exists | Status + routing smoke test + elevation smoke test + E2E |
| Live Data | **PREPARADO** — source gateway integration and CI tests exist | **BLOQUEADO** until provider credentials/API and production gateway exist | Auth, rate limit, cache, observability and live-data smoke test |
| Rescue Link | **PREPARADO** — service integration and CI tests exist | **BLOQUEADO** until production deployment/domain exists | E2E safety test without a real 112 call |
| Security | **HECHO** at CI baseline level; repository security workflow is green for the latest commit | Production secret/configuration evidence still required | Dependency/secret/configuration gates plus release review |
| Contracts | **PREPARADO** — requirements/matrix documented | **BLOQUEADO** until required accounts/contracts are actually obtained | Evidence recorded before production |
| Stores | **PREPARADO** — mobile build pipeline exists | **BLOQUEADO** until Google Play / Apple Developer access, signing and store metadata are available | Final QA, signing and submission |

## Current verified CI evidence

Latest verified push CI:
- Workflow run: `36084587261`
- Commit: `18aa5080b3f7245c59c22e29b5e460972929dd8a`
- Result: `success`
- Android artifact: `android-release`
- Android artifact digest: `sha256:f949c8bcce3924b68fef6d35dbf957b45b5b4ce70da4a7e619787ae340a97815`
- Coverage artifact: `coverage`

A successful CI run is not physical-device validation and is not proof of production infrastructure.

## Rules

1. Never substitute invented production URLs or credentials.
2. Never mark an external service production-ready from a successful unit test alone.
3. Never perform a real 112 emergency call for testing; use controlled mocks/sandboxes.
4. A release candidate must contain only production configuration supplied through the release environment.
5. Physical Android/iOS validation remains a separate gate from CI.
6. Repository assets and APK/AAB inclusion are separate claims and must be verified independently.

## Visual asset rule

The Flutter asset declaration includes `assets/backgrounds/` and `assets/landscapes/`. LAND-01 is the Home hero direction. SVG assets are rendered with `flutter_svg`; controls are not baked into the artwork.
