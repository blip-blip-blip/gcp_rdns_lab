resource "google_artifact_registry_repository" "rrdns_updater" {
  provider      = google-beta
  project       = var.project_id
  location      = "us-central1"
  repository_id = "rrdns-updater"
  format        = "DOCKER"

  depends_on = [google_project_service.host_apis]
}

locals {
  image_url = "us-central1-docker.pkg.dev/${var.project_id}/rrdns-updater/rrdns-updater:latest"
}

resource "null_resource" "build_push_image" {
  triggers = {
    main_py      = filesha256("${path.module}/app/main.py")
    requirements = filesha256("${path.module}/app/requirements.txt")
    dockerfile   = filesha256("${path.module}/app/Dockerfile")
  }

  provisioner "local-exec" {
    command = "gcloud builds submit ${path.module}/app --tag ${local.image_url} --project ${var.project_id}"
  }

  depends_on = [
    google_artifact_registry_repository.rrdns_updater,
    google_project_service.host_apis,
  ]
}
