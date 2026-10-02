variable "project_id" {
  description = "Clinics dev GCP project"
  type        = string
  default     = "clinics-dev-359913"
}

variable "region" {
  description = "Bucket location (match GKE / Cloud SQL region)"
  type        = string
  default     = "europe-west1"
}

variable "name_prefix" {
  description = "Globally unique prefix for bucket names (project id is a safe default)"
  type        = string
  default     = "clinics-dev-359913"
}

variable "public_bucket_world_readable" {
  description = "Grant allUsers objectViewer on the public media bucket (required for OCS PublicMediaStorage over GCS S3 interop)"
  type        = bool
  default     = true
}

variable "create_hmac_key" {
  description = "Create an S3-interoperability HMAC key for the OCS storage service account (secrets go to Vault, not git)"
  type        = bool
  default     = true
}

variable "ocs_storage_service_account_id" {
  description = "Service account id (not email) used by OCS pods via HMAC or future Workload Identity"
  type        = string
  default     = "ocs-storage"
}
