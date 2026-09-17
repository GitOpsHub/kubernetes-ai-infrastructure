variable "project_id" {
  description = "GCP project ID (matches PROJECT_ID in env.sh)."
  type        = string
}

variable "region" {
  description = "GCP region, used by the provider block and for the GCS backend."
  type        = string
  default     = "us-east1"
}

variable "zone" {
  description = "GCP zone for the zonal cluster (matches ZONE in env.sh)."
  type        = string
  default     = "us-east1-b"
}

variable "cluster_name" {
  description = "GKE cluster name (matches GKE_CLUSTER in env.sh)."
  type        = string
  default     = "gke-ai-lab"
}

variable "cpu_machine_type" {
  description = "Machine type for the spot CPU pool."
  type        = string
  default     = "e2-standard-4"
}

variable "cpu_pool_min_nodes" {
  type    = number
  default = 1
}

variable "cpu_pool_max_nodes" {
  type    = number
  default = 3
}

variable "create_gpu_pool" {
  description = "Whether to create the spot GPU pool (kept at 0 nodes either way)."
  type        = bool
  default     = true
}

variable "gpu_type" {
  description = "Accelerator type. nvidia-l4 needs a g2-* machine type; nvidia-tesla-t4 needs n1-standard-4."
  type        = string
  default     = "nvidia-l4"
}

variable "gpu_machine_type" {
  type    = string
  default = "g2-standard-4"
}

variable "gpu_pool_max_nodes" {
  description = "Max nodes for the spot GPU pool. Min is always 0 - this pool costs nothing until a GPU pod is scheduled."
  type        = number
  default     = 1
}
