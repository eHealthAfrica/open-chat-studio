output "public_bucket_name" {
  description = "AWS_PUBLIC_STORAGE_BUCKET_NAME"
  value       = google_storage_bucket.ocs_public.name
}

output "private_bucket_name" {
  description = "AWS_PRIVATE_STORAGE_BUCKET_NAME"
  value       = google_storage_bucket.ocs_private.name
}

output "whatsapp_audio_bucket_name" {
  description = "WHATSAPP_S3_AUDIO_BUCKET"
  value       = google_storage_bucket.ocs_whatsapp_audio.name
}

output "ocs_storage_service_account_email" {
  description = "GCP SA backing the HMAC key (optional Workload Identity target later)"
  value       = google_service_account.ocs_storage.email
}

output "s3_interop_access_id" {
  description = "AWS_ACCESS_KEY_ID for GCS S3 interoperability"
  value       = var.create_hmac_key ? google_storage_hmac_key.ocs_s3[0].access_id : null
}

output "s3_interop_secret" {
  description = "AWS_SECRET_ACCESS_KEY for GCS S3 interoperability — store in Vault only"
  value       = var.create_hmac_key ? google_storage_hmac_key.ocs_s3[0].secret : null
  sensitive   = true
}

output "vault_env_snippet" {
  description = "Non-secret OCS env keys to merge with HMAC credentials in Vault"
  value = {
    USE_S3_STORAGE                  = "True"
    AWS_S3_ENDPOINT_URL             = "https://storage.googleapis.com"
    AWS_S3_REGION                   = "us-east-1"
    AWS_S3_ADDRESSING_STYLE         = "path"
    AWS_PUBLIC_STORAGE_BUCKET_NAME  = google_storage_bucket.ocs_public.name
    AWS_PRIVATE_STORAGE_BUCKET_NAME = google_storage_bucket.ocs_private.name
    WHATSAPP_S3_AUDIO_BUCKET        = google_storage_bucket.ocs_whatsapp_audio.name
    AWS_S3_CUSTOM_DOMAIN            = "storage.googleapis.com/${google_storage_bucket.ocs_public.name}"
  }
}
