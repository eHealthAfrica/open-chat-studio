# GCS buckets for Open Chat Studio on clinics-dev (S3-compatible API via HMAC).
#
# Applied by GitHub Actions: .github/workflows/clinics-ocs-storage.yml
# (WIF → clinics-dev-359913). Wire HMAC outputs into Vault — never commit keys.

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "clinics-dev-359913-terraform-state"
    prefix = "open-chat-studio/ocs-storage"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  labels = {
    managed-by  = "terraform"
    environment = "dev"
    application = "open-chat-studio"
    project     = "ehaclinics"
  }

  public_bucket   = "${var.name_prefix}-ocs-public"
  private_bucket  = "${var.name_prefix}-ocs-private"
  whatsapp_bucket = "${var.name_prefix}-ocs-whatsapp-audio"
}

resource "google_storage_bucket" "ocs_public" {
  name          = local.public_bucket
  location      = var.region
  storage_class = "STANDARD"
  project       = var.project_id

  uniform_bucket_level_access = true

  labels = merge(local.labels, { purpose = "ocs-public-media" })
}

resource "google_storage_bucket" "ocs_private" {
  name          = local.private_bucket
  location      = var.region
  storage_class = "STANDARD"
  project       = var.project_id

  uniform_bucket_level_access = true

  labels = merge(local.labels, { purpose = "ocs-private-media" })
}

resource "google_storage_bucket" "ocs_whatsapp_audio" {
  name          = local.whatsapp_bucket
  location      = var.region
  storage_class = "STANDARD"
  project       = var.project_id

  uniform_bucket_level_access = true

  labels = merge(local.labels, { purpose = "ocs-whatsapp-audio" })
}

resource "google_service_account" "ocs_storage" {
  account_id   = var.ocs_storage_service_account_id
  display_name = "Open Chat Studio object storage (clinics-dev)"
  project      = var.project_id
}

resource "google_storage_bucket_iam_member" "ocs_public_admin" {
  bucket = google_storage_bucket.ocs_public.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ocs_storage.email}"
}

resource "google_storage_bucket_iam_member" "ocs_private_admin" {
  bucket = google_storage_bucket.ocs_private.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ocs_storage.email}"
}

resource "google_storage_bucket_iam_member" "ocs_whatsapp_admin" {
  bucket = google_storage_bucket.ocs_whatsapp_audio.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ocs_storage.email}"
}

resource "google_storage_bucket_iam_member" "ocs_public_readers" {
  count  = var.public_bucket_world_readable ? 1 : 0
  bucket = google_storage_bucket.ocs_public.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_hmac_key" "ocs_s3" {
  count                 = var.create_hmac_key ? 1 : 0
  service_account_email = google_service_account.ocs_storage.email
  project               = var.project_id
}
