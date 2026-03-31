resource "google_cloud_run_v2_service" "rrdns_updater" {
  provider = google
  project  = var.project_id
  name     = "rrdns-updater"
  location = "us-central1"
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = google_service_account.rrdns_cloudrun.email

    containers {
      image = local.image_url

      env {
        name  = "DNS_PROJECT"
        value = var.project_id
      }
      env {
        name  = "DNS_ZONE_NAME"
        value = google_dns_managed_zone.ptr_zone.name
      }
      env {
        name  = "ZONE_IP_PREFIX"
        value = "10.10."
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }

  depends_on = [
    null_resource.build_push_image,
    google_project_service.host_apis,
    google_project_iam_member.rrdns_dns_admin,
  ]
}
