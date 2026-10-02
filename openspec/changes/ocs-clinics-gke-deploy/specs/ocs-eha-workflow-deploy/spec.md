# Spec Delta

## Purpose

Defines how Open Chat Studio (this repository) invokes the shared eha-workflow reusable GitHub Actions to build and deploy onto Clinics GKE `eha-clinics-dev`, and how Clinics object-storage Terraform is applied from this repository via a dedicated WIF-backed workflow.

## ADDED Requirements

### Requirement: Deploy originates from this repository
The system SHALL build the production OCS container image from this repository’s Docker context (root `Dockerfile`) as part of the Clinics deploy pipeline so the deployed image tag corresponds to a commit in `eHealthAfrica/open-chat-studio`. The build SHALL pass Docker build-arg `OCS_VERSION` (from `git describe --tags --match 'v*' --always` or equivalent) so the running app does not report `unknown`.

#### Scenario: Pipeline builds local Dockerfile
- **WHEN** the `dev` pipeline’s build component runs
- **THEN** it builds using this repo’s `Dockerfile` (or a documented path in-repo) and pushes to the Clinics registry

#### Scenario: OCS_VERSION is set on the image
- **WHEN** the Clinics image build completes
- **THEN** the image was built with a non-default `OCS_VERSION` build-arg derived from git describe (or documented equivalent)

### Requirement: eha-workflow caller
The system SHALL provide a GitHub Actions workflow that calls an eha-workflow `build-deploy.yaml` reusable workflow at a pinned tag, with `secrets: inherit`. This Clinics caller MUST NOT replace or remove the existing Dimagi Amazon ECS `deploy.yml` workflow.

#### Scenario: develop push triggers deploy
- **WHEN** commits are pushed to the branch mapped by `deployments/dev.pipeline.yaml` (`git_branch`, default `develop`)
- **THEN** the reusable build-deploy workflow runs

#### Scenario: Manual environment dispatch
- **WHEN** an operator runs `workflow_dispatch` with environment `dev`
- **THEN** the resolver selects the `dev` pipeline and deploys that environment

#### Scenario: ECS workflow remains available
- **WHEN** Clinics deploy wiring is added to this repository
- **THEN** `.github/workflows/deploy.yml` (Amazon ECS) remains present and is not required for Clinics GKE deploys

### Requirement: Clinics cluster and registry
The system SHALL set `deployment.cluster` to `eha-clinics-dev-gke` and `image_registry` to `clinics-dev-359913` for the `dev` environment, deploying into Kubernetes namespace `ocs-dev`.

#### Scenario: Resolve targets clinics-dev
- **WHEN** resolve runs for `dev`
- **THEN** the resolved target includes GKE cluster `eha-clinics-dev` in GCP project `clinics-dev-359913`

### Requirement: Short-lived GCP authentication
The system SHALL authenticate to GCP using Workload Identity Federation via Environment secrets named `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT` as required by eha-workflow, and MUST NOT require a long-lived GCP service-account JSON key for routine Clinics deploys.

#### Scenario: Federated auth without SA JSON
- **WHEN** Environment `dev` is configured with valid WIF secrets for this repository
- **THEN** build/push and Helm deploy can obtain GCP credentials without a JSON key secret

### Requirement: Workflow pin documents Clinics compatibility
The system SHALL pin a workflow ref that includes the `eha-clinics-dev-gke` cluster registry entry (for example `EHA-Clinics/eha-workflow@v15.0.5-clinics`, or `eHealthAfrica/eha-workflow` at a tag/commit that contains that cluster file).

#### Scenario: Unknown cluster does not occur for clinics-dev
- **WHEN** resolve runs against the pinned workflow ref
- **THEN** cluster `eha-clinics-dev-gke` is a registered cluster name

### Requirement: Object storage Terraform lives in this repository
The system SHALL keep Clinics OCS object-storage Terraform under `terraform/clinics-dev-ocs-storage/` in **this** repository (`eHealthAfrica/open-chat-studio`), targeting GCP project **`clinics-dev-359913`**. The stack SHALL create the public, private, and WhatsApp-audio GCS buckets, an `ocs-storage` service account with `roles/storage.objectAdmin` on those buckets, optional public-bucket objectViewer for `allUsers`, and an S3-interop HMAC key for OCS. Object-storage Terraform MUST NOT live in `eha-cloud-devops`.

#### Scenario: Terraform path is in-repo
- **WHEN** an operator looks up OCS bucket provisioning for clinics-dev
- **THEN** the source of truth is `terraform/clinics-dev-ocs-storage/` in this repository

### Requirement: Dedicated GitHub Actions workflow applies OCS storage Terraform
The system SHALL provide a dedicated GitHub Actions workflow (e.g. `.github/workflows/clinics-ocs-storage.yml`) that plans/applies `terraform/clinics-dev-ocs-storage/` against project `clinics-dev-359913` using Workload Identity Federation (`GCP_WORKLOAD_IDENTITY_PROVIDER` / `GCP_SERVICE_ACCOUNT` on Environment `dev`). Apply SHALL be gated (e.g. `workflow_dispatch` with an explicit `apply` action); pull requests that touch the Terraform path SHALL run `plan` only. The workflow MUST NOT require a long-lived GCP JSON key. The impersonated SA MUST have permissions sufficient to manage those buckets, the storage service account, HMAC keys, and the Terraform state bucket objects (documented in-repo).

#### Scenario: Manual apply via workflow_dispatch
- **WHEN** an operator runs the Clinics OCS storage workflow with action `apply` and Environment `dev` WIF secrets are valid
- **THEN** Terraform apply runs against `clinics-dev-359913` and creates or updates the OCS storage resources

#### Scenario: PR plans storage changes
- **WHEN** a pull request changes files under `terraform/clinics-dev-ocs-storage/`
- **THEN** the storage workflow runs `terraform plan` without applying

#### Scenario: No JSON key for storage CI
- **WHEN** the storage Terraform workflow authenticates to GCP
- **THEN** it uses WIF Environment secrets only
