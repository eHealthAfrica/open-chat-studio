# Design

## Context

See `proposal.md`. Clinics AdhereBot already uses `EHA-Clinics/eha-workflow` + `eha-chart/generic3@0.5.7` with Cloud SQL and Vault-synced secrets (`vaultextrasecrets` / `env_secrets`).

**Postgres target (verified live on clinics-dev):** Cloud SQL instance **`eha-clinics-dev`** — `POSTGRES_14`, `europe-west1`, connection name `clinics-dev-359913:europe-west1:eha-clinics-dev`, tier `db-custom-2-3840`, shared multi-app instance (many existing DBs; no OCS DB yet). Cluster Vault UI is **`https://vault-dev.eha.ng`**. Operators create the OCS DB/user + Vault `DATABASE_URL` after deploy scaffolding is live.

## Goals / Non-Goals

**Goals:**
- Clinics install path owned by `open-chat-studio` CI (build SHA = deploy SHA).
- App processes on **generic3**; **only Redis** as an extra Helm chart dependency.
- **Postgres = existing Cloud SQL `eha-clinics-dev`** (not chart-owned Postgres).
- Secrets via **Vault → K8s Secret**, referenced from generic3 values (credentials can land later).
- **OCS** admin UI reachable at HTTPS `ocs-dev.eha.ng` (OCS hostname only) with CSRF/hosts/email/bootstrap documented so the app is usable after cutover.
- Clarify dimagi-ocs as companion, not primary chart.

**Non-Goals:**
- Deploying in-cluster Postgres/pgvector StatefulSet or CNPG from Helm.
- Memorystore Redis for v1 (Bitnami Redis chart is enough unless platform prefers Memorystore later).
- Enabling `USE_S3_STORAGE` / media uploads for v1 admin smoke — optional until WhatsApp media / voice / user uploads are required (bucket **provisioning** is in scope in this repo via Terraform + GHA).
- Putting object-storage Terraform in `eha-cloud-devops` — it belongs in **this** repository.
- Splitting Celery into multiple queue-specific workers (Dimagi ECS style) for clinics-dev.
- Replacing Heroku/ECS for non-Clinics.
- Meta WABA bootstrap in CI.
- Automating AdhereBot `OCS_BASE_URL` cutover in this change (document only).

## Decisions

### 1. App chart = generic3; datastore chart = Redis only
- **Choice:** `eha-chart/generic3` `0.5.7` for web / celery-worker / celery-beat. **Bitnami Redis** under eha-workflow `helm_charts` for broker/cache.
- **Why:** OCS needs Redis for Celery; Postgres is already provided by Cloud SQL. No second Postgres in the cluster.
- **Celery topology:** One worker release **without** `-Q` (consumes all declared queues). OCS documents that single-worker setups are supported; Dimagi’s multi-worker ECS split is not required for clinics-dev.
- **Not used from charts:** any Postgres/pgvector StatefulSet (including dimagi-ocs chart data plane).

### 2. Postgres = Cloud SQL `eha-clinics-dev` (POSTGRES_14)
- **Choice:** Reuse the existing instance — not a new Cloud SQL server and not an in-cluster Postgres chart.
  | Field | Value |
  |---|---|
  | Instance | [`eha-clinics-dev`](https://console.cloud.google.com/sql/instances/eha-clinics-dev/overview?project=clinics-dev-359913) |
  | Project | `clinics-dev-359913` |
  | Region | `europe-west1` |
  | `databaseVersion` | `POSTGRES_14` |
  | Connection name | `clinics-dev-359913:europe-west1:eha-clinics-dev` |
  | generic3 wiring | `database.instance` → Auth Proxy sidecar on web/worker/beat |
  | App DB/role | Dedicated (recommended name `open_chat_studio`); separate from AdhereBot and other tenants on this instance |
- **Credentials timing:** First deploys MAY ship with Secret placeholders or omit Ready until Vault is filled; operator creates DB/user + writes Vault keys **later** (Vault UI `https://vault-dev.eha.ng`, path under `kv/ehaclinics/dev/...`), then VSO/rollout picks them up — no requirement to commit secrets in the apply PR.
- **pgvector:** On the OCS database run `CREATE EXTENSION IF NOT EXISTS vector;` (Cloud SQL PG14 supports pgvector; confirm extension ≥ 0.7 if halfvec is used). Out-of-band SQL/ops step before migrate.
- **`DATABASE_URL`:** Include Cloud SQL–compatible TLS (`sslmode=require` or as required by proxy/sidecar docs).

### 3. Vault credentials + required runtime env
- **Choice:** Use generic3 **`vaultextrasecrets`** (+ **`env_secrets`**) exactly as Clinics apps do (e.g. AdhereBot): values name Vault paths and Secret names; pods consume env from synced Secrets.
- **Required keys (must be listed in Clinics hosting doc + Vault path; values never in git):**
  | Key | Purpose |
  |---|---|
  | `DJANGO_SETTINGS_MODULE` | `config.settings_production` |
  | `SECRET_KEY` | Django secret |
  | `DATABASE_URL` | Cloud SQL OCS DB via Auth Proxy |
  | `REDIS_URL` | Bitnami Redis (or composed from Redis auth Secret) |
  | `DJANGO_ALLOWED_HOSTS` | `ocs-dev.eha.ng` (plus any internal probe hosts if needed) |
  | `CSRF_TRUSTED_ORIGINS` | `https://ocs-dev.eha.ng` (required behind Traefik) |
  | `CRYPTOGRAPHY_KEY` | Field encryption (set explicitly; do not rely on `SECRET_KEY` alone) |
  | `CRYPTOGRAPHY_SALT` | Field encryption salt |
  | `HEALTH_CHECK_TOKENS` | Token(s) for `/status/` probes (optional but recommended) |
- **Email (required decision for usable admin):** Prefer a real backend (Mailgun or SES) in Vault. For a closed clinics-dev pilot only, `ACCOUNT_EMAIL_VERIFICATION=none` MAY be set explicitly and documented as temporary — default upstream is `mandatory`, which blocks invite/signup without email.
- **TLS / proxy:** Traefik terminates TLS. Values/docs MUST set Django appropriately so login/CSRF work behind the Ingress (e.g. disable app-level forced redirect if TLS is only at the edge, or keep redirect consistent with Clinics apps). Document the chosen pattern next to AdhereBot.
- **Why:** Updating Vault updates the Secret and can trigger rollout; Helm values stay non-secret.

### 4. Workflow pin + WIF + image version
- Prefer pin with `eha-clinics-dev-gke` (e.g. `EHA-Clinics/eha-workflow@v15.0.5-clinics` or upstream after cluster merge).
- Extend WIF so `eHealthAfrica/open-chat-studio` can impersonate the clinics deploy SA.
- **Image build:** Pass Docker build-arg **`OCS_VERSION`** (e.g. `git describe --tags --match 'v*' --always`) so the running app reports a real version (Dockerfile defaults to `unknown`).

### 5. Namespace / hostname / migrate / branch
- Namespace `ocs-dev`, host **`ocs-dev.eha.ng`** (admin UI + future channel webhooks).
- Migrate Job with same image tag; gate web success on migrate.
- **Git branch:** Use **`develop`** for Clinics continuous deploy (`git_branch: develop`), matching AdhereBot; keep `workflow_dispatch` for `dev`. **`develop` exists** on `eHealthAfrica/open-chat-studio` (created from `main`); this OpenSpec change merges into `develop`.
- **Health probes:** Web readiness/liveness (or Clinics equivalent) SHOULD hit `/status/?token=...` when `HEALTH_CHECK_TOKENS` is set.

### 6. Post-migrate bootstrap (manual cutover — still planned here)
After DB credentials exist and migrate succeeds, operators MUST (checklist in hosting doc):
1. `createsuperuser` (exec into web pod or one-shot Job).
2. Create a **Team** in Django admin (app is not usable without a team).
3. Set Django **`Site`** domain to `ocs-dev.eha.ng` (public links / host-bound features otherwise 403).
4. Configure LLM providers / channels in admin as needed for the pilot.

These steps are **manual** (or one-shot Jobs), not CI — but they are required for “runs properly” and belong in the cutover checklist.

### 7. AdhereBot → OCS URL
- **Default for docs:** `OCS_BASE_URL=https://ocs-dev.eha.ng` (same Ingress humans use).
- **Optional later:** in-cluster Service DNS (`http://<ocs-web-svc>.ocs-dev.svc.cluster.local`) for AdhereBot-only traffic; not required for v1 cutover.

### 8. Object storage — Terraform + GHA in this repository
- **Choice:** Provision OCS GCS buckets from **`terraform/clinics-dev-ocs-storage/`** in this repo, applied by **`.github/workflows/clinics-ocs-storage.yml`** using WIF against project **`clinics-dev-359913`** (Environment `dev`). OCS talks S3-compat via HMAC against `https://storage.googleapis.com`.
- **Buckets (OCS env 1:1):**
  | Bucket (default name) | OCS env |
  |---|---|
  | `clinics-dev-359913-ocs-public` | `AWS_PUBLIC_STORAGE_BUCKET_NAME` |
  | `clinics-dev-359913-ocs-private` | `AWS_PRIVATE_STORAGE_BUCKET_NAME` |
  | `clinics-dev-359913-ocs-whatsapp-audio` | `WHATSAPP_S3_AUDIO_BUCKET` |
- **Also creates:** `ocs-storage` SA, objectAdmin on those buckets, optional `allUsers` objectViewer on public, HMAC key → Vault as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.
- **CI:** `plan` on PRs that touch the Terraform path; `apply` only via `workflow_dispatch`. Impersonated SA needs storage/IAM permissions + access to state bucket `clinics-dev-359913-terraform-state` (prefix `open-chat-studio/ocs-storage`).
- **Apply timing:** Run the storage workflow anytime. Wiring `USE_S3_STORAGE=True` + bucket/HMAC keys into OCS Vault is **optional for admin smoke**; required before durable media / WhatsApp voice.
- **Docs:** Clinics hosting doc MUST point at the in-repo Terraform path and the storage workflow.

## Risks / Trade-offs

- **[Risk] Pods CrashLoop until Vault/DB creds exist** → Mitigation: document ordered cutover (deploy Redis + apps → create DB/user → fill Vault → restart/rollout); optional initial dry-run / scaled-to-zero until secrets present.
- **[Risk] WIF denies eHealthAfrica owner** → Mitigation: update pool binding before first deploy.
- **[Risk] pgvector missing on Cloud SQL** → Mitigation: ops checklist before migrate.
- **[Risk] Admin unusable after green pods** → Mitigation: bootstrap checklist (superuser, Team, Site, email/CSRF).
- **[Risk] CSRF/login failures behind Traefik** → Mitigation: require `CSRF_TRUSTED_ORIGINS` + hosts + proxy/TLS settings in Vault/values.
- **[Trade-off] Bitnami Redis vs Memorystore** → Start Bitnami in `ocs-dev`; swap `REDIS_URL` via Vault later if Memorystore is provisioned.
- **[Trade-off] Email none vs real backend** → Prefer real email; `none` only for closed pilot with explicit doc note.

## Migration Plan

1. Merge this OpenSpec into **`develop`**; apply pipeline/values (Vault paths declared, secrets empty or stub).
2. Deploy Redis + app releases (may be unhealthy until DB URL exists).
3. On Cloud SQL `eha-clinics-dev` (`POSTGRES_14`): create dedicated OCS database/user; `CREATE EXTENSION vector`; write full required Vault keys at `https://vault-dev.eha.ng` under `kv/ehaclinics/dev/...`.
4. Confirm Secret sync + migrate Job; run bootstrap checklist (superuser, Team, Site); smoke HTTPS admin + `/status/`.
5. When media/WhatsApp is needed: run **Clinics OCS storage (Terraform)** workflow `apply` in this repo, write HMAC + bucket env to Vault, set `USE_S3_STORAGE=True`, rollout OCS.
6. Point AdhereBot at `https://ocs-dev.eha.ng` (or in-cluster URL later); deprecate dimagi-ocs deploy as default.

## Open Questions

- Exact eha-workflow pin (Clinics fork vs upstream) — resolve at apply if both register `eha-clinics-dev-gke`.
- Vault mount/path naming for OCS (`ehaclinics/dev/open-chat-studio` vs similar) — choose at apply to match Clinics Vault layout.
- Email provider for clinics-dev (Mailgun vs SES vs temporary `ACCOUNT_EMAIL_VERIFICATION=none`).
