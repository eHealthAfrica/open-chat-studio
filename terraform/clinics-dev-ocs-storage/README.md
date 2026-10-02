# Clinics-dev OCS object storage (Terraform)

Provisions GCS buckets for Open Chat Studio media / WhatsApp audio in project **`clinics-dev-359913`**.

## Apply via CI (preferred)

Workflow: [`.github/workflows/clinics-ocs-storage.yml`](../../.github/workflows/clinics-ocs-storage.yml)

1. Ensure GitHub Environment **`dev`** has `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT`.
2. Grant that SA (project `clinics-dev-359913`) at least:
   - `roles/storage.admin` (buckets + state bucket objects)
   - `roles/iam.serviceAccountAdmin`
   - `roles/iam.serviceAccountKeyAdmin` (HMAC keys)
3. Ensure GCS state bucket `clinics-dev-359913-terraform-state` exists (one-time).
4. Actions → **Clinics OCS storage (Terraform)** → `workflow_dispatch` → choose `plan` or `apply`.

## Local (optional)

```bash
cd terraform/clinics-dev-ocs-storage
terraform init
terraform plan
terraform apply
```

## Vault

After apply, put outputs into Vault (`vault-dev.eha.ng`), including sensitive HMAC:

```bash
terraform output -json vault_env_snippet
terraform output -raw s3_interop_access_id
terraform output -raw s3_interop_secret
```

Never commit HMAC secrets.
