terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.3"
    }
  }

  # Remote state (recommended): a GCS bucket with built-in object versioning +
  # native locking (Terraform >= 1.10 locks GCS state automatically, no extra
  # resource needed - unlike AWS, GCS backends never required a separate lock
  # table). Uncomment and fill in, or pass equivalent -backend-config flags.
  #
  # backend "gcs" {
  #   bucket = "k8s-ai-lab-tfstate"     # pre-create this bucket with versioning enabled
  #   prefix = "18-infrastructure-as-code/gke"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
