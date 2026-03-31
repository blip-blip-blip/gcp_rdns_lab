resource "google_pubsub_topic" "rrdns_events" {
  provider = google-beta
  project  = var.project_id
  name     = "rrdns-events"
}

# Aggregated folder sink — Common folder (host project lives here)
resource "google_logging_folder_sink" "rrdns_common" {
  provider         = google-beta
  name             = "rrdns-events-sink"
  folder           = "folders/${var.common_folder_id}"
  include_children = true
  destination      = "pubsub.googleapis.com/${google_pubsub_topic.rrdns_events.id}"

  filter = <<-EOT
    protoPayload.serviceName="compute.googleapis.com"
    AND protoPayload.methodName=~"v1.compute.(instances|forwardingRules|globalForwardingRules).(insert|delete)"
  EOT
}

# Aggregated folder sink — ADC folder (application projects live here)
resource "google_logging_folder_sink" "rrdns_adc" {
  provider         = google-beta
  name             = "rrdns-events-sink"
  folder           = "folders/${var.adc_folder_id}"
  include_children = true
  destination      = "pubsub.googleapis.com/${google_pubsub_topic.rrdns_events.id}"

  filter = <<-EOT
    protoPayload.serviceName="compute.googleapis.com"
    AND protoPayload.methodName=~"v1.compute.(instances|forwardingRules|globalForwardingRules).(insert|delete)"
  EOT
}

# Grant each sink's writer identity publish access to the topic
resource "google_pubsub_topic_iam_member" "rrdns_common_sink_publisher" {
  provider = google-beta
  project  = var.project_id
  topic    = google_pubsub_topic.rrdns_events.name
  role     = "roles/pubsub.publisher"
  member   = google_logging_folder_sink.rrdns_common.writer_identity
}

resource "google_pubsub_topic_iam_member" "rrdns_adc_sink_publisher" {
  provider = google-beta
  project  = var.project_id
  topic    = google_pubsub_topic.rrdns_events.name
  role     = "roles/pubsub.publisher"
  member   = google_logging_folder_sink.rrdns_adc.writer_identity
}

# Push subscription → Cloud Run
resource "google_pubsub_subscription" "rrdns_push" {
  provider = google-beta
  project  = var.project_id
  name     = "rrdns-events-push"
  topic    = google_pubsub_topic.rrdns_events.name

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.rrdns_updater.uri}/"
    oidc_token {
      service_account_email = google_service_account.rrdns_pubsub_invoker.email
    }
  }

  ack_deadline_seconds       = 60
  message_retention_duration = "600s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
}
