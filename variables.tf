variable "project_id" {
  description = "GCP project ID hosting the shared VPC (host project)"
  type        = string
}

variable "vpc_name" {
  description = "Name of the shared VPC network"
  type        = string
  default     = "vpc-nonprod-shared"
}

variable "region" {
  description = "Primary region for Cloud Run and Artifact Registry"
  type        = string
  default     = "us-central1"
}

variable "zone_ip_prefix" {
  description = "IP prefix for the reverse DNS zone (e.g. '10.10.' for 10.10.0.0/16)"
  type        = string
  default     = "10.10."
}

variable "common_folder_id" {
  description = "Numeric ID of the Common folder (host project lives here). e.g. '123456789012'"
  type        = string
}

variable "adc_folder_id" {
  description = "Numeric ID of the ADC folder (application projects live here). e.g. '123456789013'"
  type        = string
}
