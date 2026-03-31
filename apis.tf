resource "google_project_service" "host_apis" {
  for_each = toset([
    "dns.googleapis.com",
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])
  provider           = google-beta
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
