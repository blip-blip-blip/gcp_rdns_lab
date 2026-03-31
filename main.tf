data "google_compute_network" "vpc_nonprod_shared" {
  provider = google
  name     = var.vpc_name
  project  = var.project_id
}

data "google_compute_subnetwork" "us_central1" {
  provider = google
  name     = "us-central1"
  region   = var.region
  project  = var.project_id
}

resource "google_dns_managed_zone" "ptr_zone" {
  provider = google
  project     = var.project_id
  name        = "nonprod-ptr-zone"
  dns_name    = "10.10.in-addr.arpa."
  description = "PTR records for vpc-nonprod-shared (10.10.0.0/16) — managed by rrdns-updater"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = data.google_compute_network.vpc_nonprod_shared.id
    }
  }
}

# Test VMs commented out — spin up manually for demos (see README.md)

# locals {
#   test_vms = {
#     "test-rrdns"        = { ip = google_compute_instance.test_rrdns.network_interface[0].network_ip,        zone = "us-central1-a" }
#     "test-rrdns-client" = { ip = google_compute_instance.test_rrdns_client.network_interface[0].network_ip, zone = "us-central1-a" }
#   }
# }

# resource "google_dns_record_set" "test_vm_ptr" {
#   for_each     = local.test_vms
#   provider = google
#   project      = var.project_id
#   managed_zone = google_dns_managed_zone.ptr_zone.name
#   type         = "PTR"
#   ttl          = 300
#   name         = "${join(".", reverse(split(".", each.value.ip)))}.in-addr.arpa."
#   rrdatas      = ["${each.key}.${each.value.zone}.c.${var.project_id}.internal."]
# }

# resource "google_compute_firewall" "allow_iap_ssh" {
#   provider = google
#   project  = var.project_id
#   name     = "allow-iap-ssh-test-rrdns"
#   network  = data.google_compute_network.vpc_nonprod_shared.id
#   allow {
#     protocol = "tcp"
#     ports    = ["22"]
#   }
#   source_ranges = ["35.235.240.0/20"]
#   target_tags   = ["test-rrdns"]
# }

# resource "google_compute_instance" "test_rrdns_client" {
#   provider = google
#   project      = var.project_id
#   name         = "test-rrdns-client"
#   machine_type = "e2-micro"
#   zone         = "us-central1-a"
#   tags         = ["test-rrdns"]
#   boot_disk {
#     initialize_params { image = "debian-cloud/debian-12"; size = 10 }
#   }
#   network_interface { subnetwork = data.google_compute_subnetwork.us_central1.id }
#   metadata = { enable-oslogin = "TRUE" }
#   shielded_instance_config {
#     enable_secure_boot = true; enable_vtpm = true; enable_integrity_monitoring = true
#   }
#   scheduling { preemptible = true; automatic_restart = false }
# }

# resource "google_compute_instance" "test_rrdns" {
#   provider = google
#   project      = var.project_id
#   name         = "test-rrdns"
#   machine_type = "e2-micro"
#   zone         = "us-central1-a"
#   tags         = ["test-rrdns"]
#   boot_disk {
#     initialize_params { image = "debian-cloud/debian-12"; size = 10 }
#   }
#   network_interface { subnetwork = data.google_compute_subnetwork.us_central1.id }
#   metadata = { enable-oslogin = "TRUE" }
#   shielded_instance_config {
#     enable_secure_boot = true; enable_vtpm = true; enable_integrity_monitoring = true
#   }
#   scheduling { preemptible = true; automatic_restart = false }
# }
