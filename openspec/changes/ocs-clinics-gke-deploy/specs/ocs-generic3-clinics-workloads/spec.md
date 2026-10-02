# Spec Delta

## Purpose

Defines Clinics GKE workload packaging for Open Chat Studio: **generic3** for app processes, **Bitnami Redis only** as an extra chart, **existing Cloud SQL `eha-clinics-dev` (`POSTGRES_14`, `clinics-dev-359913:europe-west1:eha-clinics-dev`)** for Postgres, **Vault-backed** runtime credentials (full required env), HTTPS admin Ingress, health probes, and documented post-migrate bootstrap.

## ADDED Requirements

### Requirement: generic3 chart identity for app workloads
The system SHALL deploy application components (web, celery worker, celery beat) with Helm chart `eha-chart/generic3` version `0.5.7` (or a later platform-approved pin in `helm_charts.defaults.chart_version`) from `https://ehealthafrica.github.io/helm-charts/`.

#### Scenario: Deploy step uses generic3 for apps
- **WHEN** an application component Helm deploy runs
- **THEN** the chart identity is `eha-chart/generic3` at the pinned version from the eHA charts repository

### Requirement: Redis is the only datastore Helm chart
The system SHALL provide Redis for Celery/cache by deploying a **Bitnami Redis** (or equivalent) chart via the eha-workflow pipeline, and MUST NOT deploy an in-cluster PostgreSQL/pgvector Helm release for Clinics.

#### Scenario: Pipeline includes Redis chart not Postgres chart
- **WHEN** the `dev` pipeline’s chart components are listed
- **THEN** Redis is present as a chart-backed component and no Postgres/pgvector chart component is required for install

#### Scenario: Worker reaches broker
- **WHEN** celery worker pods become Ready with secrets configured
- **THEN** they can connect to the configured Redis URL

### Requirement: Existing Cloud SQL instance for Postgres
The system SHALL use the existing Cloud SQL instance **`eha-clinics-dev`** in GCP project **`clinics-dev-359913`**, region **`europe-west1`**, engine **`POSTGRES_14`**, connection name **`clinics-dev-359913:europe-west1:eha-clinics-dev`**, as the PostgreSQL server for Open Chat Studio. The application SHALL use a **dedicated** database and role on that shared instance (recommended names `open_chat_studio` / matching role), separate from AdhereBot and other tenants. App components SHALL connect via Cloud SQL Auth Proxy when `database.instance` is set on generic3. The system MUST NOT provision a second Cloud SQL instance or an in-cluster Postgres chart for this Clinics path.

#### Scenario: Values point at eha-clinics-dev
- **WHEN** generic3 database settings for web/worker/beat are rendered
- **THEN** they reference instance `clinics-dev-359913:europe-west1:eha-clinics-dev` (or the documented equivalent connection path to that instance)

#### Scenario: Dedicated OCS database on the shared instance
- **WHEN** operators prepare Postgres for the first successful migrate
- **THEN** a dedicated database and role exist on `eha-clinics-dev` for OCS only, and `CREATE EXTENSION vector` has been applied in that database

#### Scenario: Credentials may be supplied after first deploy scaffolding
- **WHEN** Helm releases are installed before Vault/DB credentials are populated
- **THEN** the system still allows operators to add `DATABASE_URL` (and related keys) later via Vault (`vault-dev.eha.ng`) / Secret update without changing the chart identity or Cloud SQL instance

### Requirement: Vault-backed runtime secrets with required env contract
The system SHALL load runtime configuration through Kubernetes Secrets populated from **Vault** using generic3-supported Vault Static Secrets / env-from-Secret wiring (`vaultextrasecrets` / `env_secrets` or equivalent documented Clinics mechanism). Values files in git MUST NOT contain plaintext credentials.

The Clinics Vault path for OCS MUST be able to supply at least: `DJANGO_SETTINGS_MODULE` (`config.settings_production`), `SECRET_KEY`, `DATABASE_URL`, `REDIS_URL`, `DJANGO_ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`, `CRYPTOGRAPHY_KEY`, and `CRYPTOGRAPHY_SALT`. Email SHALL be configured via a real backend in Vault, **or** an explicitly documented temporary `ACCOUNT_EMAIL_VERIFICATION=none` for a closed clinics-dev pilot. Optional but recommended: `HEALTH_CHECK_TOKENS`.

#### Scenario: Values reference Vault or Secret names only
- **WHEN** generic3 values under `deployments/` are reviewed in git
- **THEN** they declare Vault paths and/or Secret names, not secret values

#### Scenario: Required production keys are documented
- **WHEN** an operator reads the Clinics hosting / cutover doc for OCS
- **THEN** the required Vault key list above is present (including CSRF trusted origins and cryptography keys)

#### Scenario: Credential rotation without chart change
- **WHEN** an operator updates a credential in Vault for the configured path
- **THEN** the synced Kubernetes Secret can be updated and pods can pick up new values on rollout/restart without modifying Helm chart source in this repository

### Requirement: Process mapping to separate releases
The system SHALL map production processes to separate Helm releases for at least web (gunicorn), **one** celery worker, and celery beat, all using the same image tag from a given successful pipeline run. The celery worker for clinics-dev SHALL consume all application queues (no requirement to deploy separate background/evaluations workers).

#### Scenario: Celery beat singleton
- **WHEN** celery beat is deployed
- **THEN** its replica count is exactly one

#### Scenario: Shared image tag across processes
- **WHEN** web and celery worker deploy from the same successful run
- **THEN** both releases use that run’s published image tag

#### Scenario: Single worker covers queues
- **WHEN** the clinics-dev celery worker is configured
- **THEN** it is a single worker release that consumes the app’s declared Celery queues (not a multi-worker ECS-style split)

### Requirement: Migrations gate
The system SHALL apply Django database migrations (`migrate --noinput` or equivalent) before treating the web rollout for that train as successful, once database credentials are available.

#### Scenario: Failed migrate fails the run
- **WHEN** the migration Job or hook exits non-zero
- **THEN** the workflow run fails and MUST NOT report a successful web deploy for that train

### Requirement: HTTPS Ingress for admin UI and channels
The system SHALL expose web on a stable HTTPS hostname (default `ocs-dev.eha.ng`) via the clinics-dev Ingress controller so operators can reach the **admin UI** and so messaging platform webhooks can reach OCS when channels are configured. Django MUST be configured for that hostname behind Traefik (`DJANGO_ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`, and documented TLS/proxy behaviour).

#### Scenario: TLS hostname serves web
- **WHEN** DNS for the configured hostname points at cluster Ingress and certificates are issued and required env is present
- **THEN** HTTPS requests to the OCS web service succeed

#### Scenario: Admin login CSRF works behind Ingress
- **WHEN** an operator opens the admin UI at `https://ocs-dev.eha.ng` with Vault secrets populated
- **THEN** login forms succeed without CSRF origin failures attributable to missing `CSRF_TRUSTED_ORIGINS` / hosts settings

### Requirement: Health status endpoint for probes
The system SHALL document and wire web health checks to OCS `/status/` (and token query parameter when `HEALTH_CHECK_TOKENS` is set).

#### Scenario: Status endpoint is the probe target
- **WHEN** web probe configuration for clinics-dev is reviewed
- **THEN** it targets `/status/` (with token when configured), not an undefined path

### Requirement: Post-migrate bootstrap checklist
The system SHALL document a post-migrate bootstrap checklist that operators execute manually (or via one-shot Job): create a Django superuser, create a Team, and set the Django `Site` domain to the public hostname (`ocs-dev.eha.ng`). Object storage (`USE_S3_STORAGE`) is NOT required for this bootstrap / admin smoke.

#### Scenario: Bootstrap steps are written down
- **WHEN** an operator follows the Clinics cutover doc after migrate
- **THEN** superuser, Team, and Site domain steps are listed before declaring the environment usable

#### Scenario: Site domain matches Ingress host
- **WHEN** bootstrap is complete
- **THEN** the Django `Site` domain equals `ocs-dev.eha.ng` (or the configured public hostname)

### Requirement: Object storage Terraform and CI in this repository
The system SHALL provision OCS object storage from `terraform/clinics-dev-ocs-storage/` in this repository (GCS buckets for public media, private media, and WhatsApp audio; service account; S3-interop HMAC), applied by the dedicated Clinics OCS storage GitHub Actions workflow using WIF on `clinics-dev-359913`. Enabling `USE_S3_STORAGE` in OCS Vault MAY be deferred until media or WhatsApp voice is required; the provision path and Vault key mapping SHALL still be documented as part of this Clinics deploy plan.

#### Scenario: Hosting doc names the in-repo Terraform and workflow
- **WHEN** an operator reads Clinics hosting / cutover docs for OCS object storage
- **THEN** they are directed to `terraform/clinics-dev-ocs-storage/` and `.github/workflows/clinics-ocs-storage.yml` with the three bucket → OCS env mappings

#### Scenario: Admin smoke without S3
- **WHEN** OCS is first brought up for admin smoke only
- **THEN** `USE_S3_STORAGE` is not required to be true, even if the storage Terraform stack already exists or has been applied

### Requirement: AdhereBot URL documented
The system SHALL document AdhereBot → OCS base URL as `https://ocs-dev.eha.ng` by default, with an optional later in-cluster Service DNS alternative for same-cluster traffic.

#### Scenario: Default URL is public Ingress
- **WHEN** cutover docs describe AdhereBot wiring
- **THEN** they give `OCS_BASE_URL=https://ocs-dev.eha.ng` as the default and may note ClusterIP Service DNS as optional

### Requirement: dimagi-ocs companion role
The system SHALL document `EHA-Clinics/dimagi-ocs` as a Clinics packaging/ops companion whose custom Helm chart is **not** the primary install chart for this Clinics path.

#### Scenario: Deploy guide names this repo’s workflow
- **WHEN** an operator reads Clinics deploy documentation produced by this change’s apply phase
- **THEN** the default instructions use this repo’s eha-workflow caller, generic3 app values, Bitnami Redis, and Cloud SQL `eha-clinics-dev` — not `dimagi-ocs` `deploy-ocs-helm.yml` as primary
