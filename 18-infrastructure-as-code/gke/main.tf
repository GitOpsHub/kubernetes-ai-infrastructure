# Terraform equivalent of 00-prerequisites-and-cluster-setup/gke/create-cluster.sh:
# a zonal Standard cluster with its default node pool removed, a spot-cpu pool
# (autoscaling 1..N), and a spot-gpu pool (autoscaling 0..1, one L4).
#
# This is the "raw resources" path. For a production platform team, the
# recommended alternative is the community module
# terraform-google-modules/kubernetes-engine/google (current major: v45.x,
# verified 2026-09-17 via its GitHub releases) which wraps these same
# resources with sane defaults (private cluster, node pool taints/labels
# helpers, release channel handling, Workload Identity wiring). See the
# commented block at the bottom of this file for the equivalent call.

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone

  release_channel {
    channel = "REGULAR"
  }

  # GKE requires a node pool at create time; we remove it immediately and
  # manage spot-cpu / spot-gpu as separate google_container_node_pool
  # resources below (same "separately managed node pool" pattern the
  # provider docs recommend).
  remove_default_node_pool = true
  initial_node_count       = 1

  # google_container_cluster deletes are blocked unless this is explicitly
  # false (provider >= 5.0 behavior) - deliberate, so a stray `terraform
  # destroy` doesn't silently take out a shared lab cluster.
  deletion_protection = false

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {} # enables VPC-native / alias IPs, equivalent to --enable-ip-alias

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  node_config {
    machine_type = "e2-standard-2"
  }
}

resource "google_container_node_pool" "spot_cpu" {
  name     = "spot-cpu"
  cluster  = google_container_cluster.primary.name
  location = var.zone

  node_count = 1 # initial size; autoscaler takes over after that

  autoscaling {
    min_node_count = var.cpu_pool_min_nodes
    max_node_count = var.cpu_pool_max_nodes
  }

  node_config {
    machine_type = var.cpu_machine_type
    spot         = true
    disk_type    = "pd-balanced"
    disk_size_gb = 50

    labels = {
      workload = "general"
    }
  }
}

resource "google_container_node_pool" "spot_gpu" {
  count = var.create_gpu_pool ? 1 : 0

  name     = "spot-gpu"
  cluster  = google_container_cluster.primary.name
  location = var.zone

  node_count = 0 # scale-to-zero: this pool costs nothing until a GPU pod is Pending

  autoscaling {
    min_node_count = 0
    max_node_count = var.gpu_pool_max_nodes
  }

  node_config {
    machine_type = var.gpu_machine_type
    spot         = true
    disk_type    = "pd-balanced"
    disk_size_gb = 100

    guest_accelerator {
      type  = var.gpu_type
      count = 1

      gpu_driver_installation_config {
        gpu_driver_version = "LATEST"
      }
    }

    # GKE auto-taints nodes that carry an accelerator with
    # nvidia.com/gpu=present:NoSchedule - no explicit taint block needed here,
    # matching the CLI path in 00-prerequisites-and-cluster-setup/gke/create-cluster.sh.
    labels = {
      workload = "gpu"
    }
  }
}

# --- Alternative: terraform-google-modules/kubernetes-engine/google ---
# Recommended once you outgrow hand-rolled resources (private cluster
# plumbing, node pool taints/labels/tags helpers, Workload Identity,
# release-channel-aware upgrades). Verify the current major version before
# pinning - v45.x was latest as of 2026-09-17:
#
# module "gke" {
#   source                     = "terraform-google-modules/kubernetes-engine/google"
#   version                    = "~> 45.0"
#   project_id                 = var.project_id
#   name                       = var.cluster_name
#   region                     = var.region
#   zones                      = [var.zone]
#   network                    = "default"
#   subnetwork                 = "default"
#   ip_range_pods              = "" # module can auto-create secondary ranges
#   ip_range_services          = ""
#   remove_default_node_pool   = true
#   node_pools = [
#     {
#       name         = "spot-cpu"
#       machine_type = "e2-standard-4"
#       spot         = true
#       min_count    = 1
#       max_count    = 3
#       disk_size_gb = 50
#     },
#     {
#       name               = "spot-gpu"
#       machine_type       = "g2-standard-4"
#       spot               = true
#       min_count          = 0
#       max_count          = 1
#       disk_size_gb       = 100
#       accelerator_count  = 1
#       accelerator_type   = "nvidia-l4"
#       gpu_driver_version = "LATEST"
#     },
#   ]
# }
