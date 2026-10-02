# Tasks

## 1. Platform prerequisites (document + configure)

- [ ] 1.1 Document WIF binding for `eHealthAfrica/open-chat-studio` on clinics-dev and verify Environment `dev` can list `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT`
- [ ] 1.2 Confirm pinned eha-workflow ref includes `eha-clinics-dev-gke` and verify resolve names that cluster
- [x] 1.3 Create `develop` for Clinics continuous deploy (branch exists on `eHealthAfrica/open-chat-studio`; OpenSpec PR targets `develop`) — still verify pipeline `git_branch` matches at apply
- [ ] 1.4 Document in `docs/hosting/clinics-gke.md` (or equivalent) and verify the doc exists:
  - Cloud SQL `eha-clinics-dev` (`POSTGRES_14`, `clinics-dev-359913:europe-west1:eha-clinics-dev`)
  - Dedicated OCS DB/user + `CREATE EXTENSION vector` **when ready**
  - Vault at `https://vault-dev.eha.ng` with the **full required key list** (`DJANGO_SETTINGS_MODULE`, `SECRET_KEY`, `DATABASE_URL`, `REDIS_URL`, `DJANGO_ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`, `CRYPTOGRAPHY_KEY`, `CRYPTOGRAPHY_SALT`, email keys or explicit `ACCOUNT_EMAIL_VERIFICATION=none`, optional `HEALTH_CHECK_TOKENS`)
  - DNS `ocs-dev.eha.ng`, Traefik TLS / proxy notes for Django
  - Object storage: in-repo `terraform/clinics-dev-ocs-storage/` + `.github/workflows/clinics-ocs-storage.yml` (WIF → `clinics-dev-359913`); `USE_S3_STORAGE` optional until media/WhatsApp
- [ ] 1.5 Document cutover order and verify it is written down: Redis+apps → create DB on `eha-clinics-dev` → fill Vault → migrate → **bootstrap** (createsuperuser, Team, Site=`ocs-dev.eha.ng`) → smoke admin + `/status/` → optional AdhereBot `OCS_BASE_URL`
- [ ] 1.6 Ensure Terraform state bucket `clinics-dev-359913-terraform-state` exists and WIF deploy SA has storage/IAM roles for OCS buckets + HMAC; document required roles in Clinics hosting doc
- [ ] 1.7 Add `terraform/clinics-dev-ocs-storage/` (public/private/WhatsApp buckets + SA + HMAC) and `.github/workflows/clinics-ocs-storage.yml` (plan on PR / apply on dispatch) and verify workflow parses; document Vault mapping of outputs

## 2. Pipeline and caller in this repo

- [ ] 2.1 Add `deployments/dev.pipeline.yaml` with generic3 app components (web/worker/beat), **Bitnami Redis only** under `helm_charts` (no Postgres chart), `cluster: eha-clinics-dev-gke`, `namespace: ocs-dev`, `chart_version: "0.5.7"` and verify YAML is valid
- [ ] 2.2 Add Clinics eha-workflow caller (e.g. `.github/workflows/deploy-clinics.yaml` or equivalent) calling pinned `build-deploy.yaml` with `secrets: inherit` — do **not** replace Dimagi ECS `deploy.yml` — and verify workflow parses
- [ ] 2.3 Wire image build to pass Docker build-arg `OCS_VERSION` (`git describe --tags --match 'v*' --always` or equivalent) and verify the built image is not stuck at `unknown`
- [ ] 2.4 Verify `develop` / `workflow_dispatch` mapping matches `git_branch`

## 3. generic3 values, Redis, Vault, migrate, probes

- [ ] 3.1 Add `deployments/dev/web.yaml` with Cloud SQL instance `clinics-dev-359913:europe-west1:eha-clinics-dev`, Ingress `ocs-dev.eha.ng`, Vault/`env_secrets` stubs for the required key list (no plaintext secrets), Traefik-safe TLS/proxy settings, and verify `helm template` against generic3 `0.5.7` succeeds
- [ ] 3.2 Add `celery-worker.yaml` (single worker, no `-Q` / all queues) and `celery-beat.yaml` (replicas=1) sharing Vault/Secret contract and verify `helm template` succeeds
- [ ] 3.3 Add `deployments/dev/redis.yaml` (Bitnami) and verify worker/web values can form or reference `REDIS_URL`
- [ ] 3.4 Add migrate Job wired to the pipeline and verify dry-run or pipeline reference exists (runs once DB Secret is present)
- [ ] 3.5 Configure web health probes for `/status/` (with token query param when `HEALTH_CHECK_TOKENS` is set) and verify probe paths are documented in values or hosting doc

## 4. Companion repos, bootstrap checklist, smoke

- [ ] 4.1 Note that `dimagi-ocs` custom chart / in-cluster Postgres is not used on this path and verify the note is present
- [ ] 4.2 Document manual bootstrap commands (createsuperuser, Team, Site domain) and AdhereBot → **OCS** URL options (`OCS_BASE_URL=https://ocs-dev.eha.ng` default; optional in-cluster Service to OCS) and verify they appear in the Clinics deploy doc
- [ ] 4.3 Document object-storage path: run **Clinics OCS storage (Terraform)** workflow `apply`, map outputs to Vault (`USE_S3_STORAGE`, bucket names, HMAC, `AWS_S3_ENDPOINT_URL`), and verify when media/WhatsApp is required this checklist is followed
- [ ] 4.4 Smoke-test checklist: HTTPS admin login, Redis, Cloud SQL after Vault fill, migrate, `/status/`, CSRF login behind Traefik — verify linked from Clinics deploy doc

## 5. Validation

- [ ] 5.1 Run `openspec validate ocs-clinics-gke-deploy --strict` and verify it passes
- [ ] 5.2 After apply, verify deploy logs show generic3 for apps, a Redis chart component, cluster `eha-clinics-dev-gke`, `OCS_VERSION` set on the image, and no Postgres Helm chart install
