output "ptr_zone_name" {
  description = "Name of the PTR zone"
  value       = google_dns_managed_zone.ptr_zone.name
}

output "ptr_zone_dns_name" {
  description = "DNS name of the PTR zone"
  value       = google_dns_managed_zone.ptr_zone.dns_name
}

# output "test_vm_internal_ip" {
#   value = google_compute_instance.test_rrdns.network_interface[0].network_ip
# }

# output "ssh_command" {
#   value = "gcloud compute ssh test-rrdns --project=${var.project_id} --zone=us-central1-a --tunnel-through-iap"
# }

# output "test_client_internal_ip" {
#   value = google_compute_instance.test_rrdns_client.network_interface[0].network_ip
# }

# output "ssh_command_client" {
#   value = "gcloud compute ssh test-rrdns-client --project=${var.project_id} --zone=us-central1-a --tunnel-through-iap"
# }

output "cloud_run_url" {
  description = "Cloud Run rrdns-updater service URL"
  value       = google_cloud_run_v2_service.rrdns_updater.uri
}

