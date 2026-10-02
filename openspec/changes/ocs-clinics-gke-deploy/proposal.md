# Proposal

## Why

Open Chat Studio must run on EHA Clinics GKE (`clinics-dev-359913` / `eha-clinics-dev`) beside AdhereBot. Deploy must start **from this application repository** so the image is built from the same Git SHA operators ship. Clinics already standardizes on the reusable workflow `EHA-Clinics/eha-workflow` (and/or `eHealthAfrica/eha-workflow` once the clinics cluster is registered upstream) plus published **`eha-chart/generic3` 0.5.7**. A separate wrong-place OpenSpec on `dimagi-ocs` was closed; planning belongs here.

## What Changes

- Add OpenSpec planning (this change) and, on apply, an eha-workflow **caller** + `deployments/dev.pipeline.yaml` in **this repo**.
- Deploy OCS **app** workloads with **`eha-chart/generic3` version `0.5.7`** (multi-release: web, celery-worker, celery-beat).
- Deploy **Redis only** as an additional Helm chart (Bitnami Redis via eha-workflow `helm_charts`) — **no in-cluster Postgres chart**.
- Use the **existing shared Cloud SQL** Postgres for OCS (verified suitable; dedicated DB/user still to create):
  - Console: [`eha-clinics-dev`](https://console.cloud.google.com/sql/instances/eha-clinics-dev/overview?project=clinics-dev-359913)
  - Project / region: `clinics-dev-359913` / `europe-west1`
  - Engine: **POSTGRES_14** (meets OCS PostgreSQL 14+ / Cloud SQL pgvector support)
  - Connection name (Auth Proxy): `clinics-dev-359913:europe-west1:eha-clinics-dev`
  - App database: create dedicated DB + role (e.g. `open_chat_studio`) on that instance — do **not** reuse AdhereBot or other app DBs; enable `CREATE EXTENSION vector`
  - **DB credentials are supplied later** via Vault (`vault-dev.eha.ng` / `kv/ehaclinics/dev/...`) → Kubernetes Secrets (not committed to git)
- Wire runtime secrets through **generic3 Vault Static Secrets / `env_secrets`** (same Clinics pattern as AdhereBot), including the **full required env contract**: `DJANGO_SETTINGS_MODULE`, `SECRET_KEY`, `DATABASE_URL`, `REDIS_URL`, `DJANGO_ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`, `CRYPTOGRAPHY_KEY`/`SALT`, email (or explicit temporary `ACCOUNT_EMAIL_VERIFICATION=none`), optional `HEALTH_CHECK_TOKENS`.
- Target cluster **`eha-clinics-dev-gke`**, namespace **`ocs-dev`**, registry **`eu.gcr.io/clinics-dev-359913`**, OCS Ingress hostname **`ocs-dev.eha.ng`** (OCS admin UI + future OCS webhooks — not AdhereBot’s hostname).
- Document cutover **bootstrap** (manual): `createsuperuser`, create Team, set Django `Site` to `ocs-dev.eha.ng`; probes on `/status/`; image build-arg `OCS_VERSION`; single Celery worker (all queues).
- Scope **object storage in this repo**: `terraform/clinics-dev-ocs-storage/` + dedicated GHA workflow `.github/workflows/clinics-ocs-storage.yml` (WIF → `clinics-dev-359913`, plan on PR / apply on `workflow_dispatch`). Enabling `USE_S3_STORAGE` in Vault can wait until media/WhatsApp is needed.
- Use **`develop`** for Clinics continuous deploy + `workflow_dispatch` (`develop` already exists on this remote); keep Dimagi ECS `deploy.yml` untouched (add a separate Clinics caller).
- Treat `EHA-Clinics/dimagi-ocs` as Clinics **ops/companion**; not the primary install chart. **BREAKING (ops):** supersedes `dimagi-ocs` `deploy-ocs-helm.yml` as the default Clinics path.
- Document WIF for **`eHealthAfrica/open-chat-studio`** (clinics-dev pool today was bootstrapped for `EHA-Clinics` owner-only).

## Capabilities

### New Capabilities

- `ocs-eha-workflow-deploy`: Caller workflow + pipeline in `open-chat-studio` that builds the OCS image and deploys via eha-workflow to `eha-clinics-dev-gke`; plus in-repo Terraform + dedicated GHA workflow for OCS GCS buckets on `clinics-dev-359913`.
- `ocs-generic3-clinics-workloads`: generic3 app releases + Bitnami Redis only; Cloud SQL `eha-clinics-dev`; Vault-backed secrets; Ingress for Clinics `ocs-dev`.

### Modified Capabilities

- (none — no existing `openspec/specs/` inventory in this repo)

## Impact

- **This repo:** `openspec/`, later Clinics deploy caller + `deployments/`, `terraform/clinics-dev-ocs-storage/`, `.github/workflows/clinics-ocs-storage.yml`; non-Clinics hosts unchanged.
- **`EHA-Clinics/dimagi-ocs`:** companion only; custom in-cluster Postgres templates are out of scope for this path.
- **`eha-workflow`:** needs `eha-clinics-dev-gke` on the pinned workflow repo.
- **GCP:** reuse Cloud SQL `eha-clinics-dev` (`POSTGRES_14`, connection `clinics-dev-359913:europe-west1:eha-clinics-dev`); add dedicated OCS DB/user + pgvector when ready; chart-deploy Redis; DNS; Traefik TLS; WIF; Vault (`vault-dev.eha.ng`) paths for credentials; GCS buckets via in-repo Terraform CI.
- **AdhereBot (client of OCS):** later set AdhereBot’s `OCS_BASE_URL` to the **OCS** URL `https://ocs-dev.eha.ng` (default); optional same-cluster Service DNS to OCS. AdhereBot keeps its own separate hostname.
