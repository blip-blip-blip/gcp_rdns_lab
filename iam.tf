# ── Cloud Run service account ────────────────────────────────────────────────

resource "google_service_account" "rrdns_cloudrun" {
  provider = google
  project      = var.project_id
  account_id   = "rrdns-cloudrun-sa"
  display_name = "RRDNS Updater Cloud Run SA"
}

# DNS admin on host project — to create/delete PTR records
resource "google_project_iam_member" "rrdns_dns_admin" {
  provider = google
  project  = var.project_id
  role     = "roles/dns.admin"
  member   = "serviceAccount:${google_service_account.rrdns_cloudrun.email}"
}

# Compute viewer on both folders — to call instances.get / forwardingRules.get
# across all current and future projects in each folder
resource "google_folder_iam_member" "rrdns_compute_viewer_common" {
  provider = google
  folder   = "folders/${var.common_folder_id}"
  role     = "roles/compute.viewer"
  member   = "serviceAccount:${google_service_account.rrdns_cloudrun.email}"
}

resource "google_folder_iam_member" "rrdns_compute_viewer_adc" {
  provider = google
  folder   = "folders/${var.adc_folder_id}"
  role     = "roles/compute.viewer"
  member   = "serviceAccount:${google_service_account.rrdns_cloudrun.email}"
}

# ── Pub/Sub push invoker service account ─────────────────────────────────────

resource "google_service_account" "rrdns_pubsub_invoker" {
  provider = google
  project      = var.project_id
  account_id   = "rrdns-pubsub-invoker-sa"
  display_name = "RRDNS Pub/Sub Push Invoker SA"
}

# Allow the invoker SA to call Cloud Run
resource "google_cloud_run_v2_service_iam_member" "rrdns_pubsub_invoker" {
  provider = google
  project  = var.project_id
  location = google_cloud_run_v2_service.rrdns_updater.location
  name     = google_cloud_run_v2_service.rrdns_updater.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.rrdns_pubsub_invoker.email}"
}

# Pub/Sub service agent needs token creator on the invoker SA to sign OIDC tokens
data "google_project" "host" {
  provider = google
  project_id = var.project_id
}

resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = google_service_account.rrdns_pubsub_invoker.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.host.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
