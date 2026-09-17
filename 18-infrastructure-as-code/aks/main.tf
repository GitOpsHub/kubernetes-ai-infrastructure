# Terraform equivalent of 00-prerequisites-and-cluster-setup/aks/create-cluster.sh:
# a resource group, an AKS cluster whose default_node_pool is a small Regular
# "system" pool (AKS does not allow the default pool to be Spot), plus a
# spot-cpu user pool (autoscaling 0..3) and a spot-gpu user pool (autoscaling
# 0..1, tainted). Field names verified 2026-09-17 against azurerm provider
# v5.5.0 docs - note `auto_scaling_enabled` (the field was named
# `enable_auto_scaling` before the azurerm v4 major; don't copy pre-v4
# examples).

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project = "k8s-ai-lab"
  }
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.dns_prefix

  sku_tier = "Free"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "system"
    vm_size    = var.system_vm_size
    node_count = 1

    auto_scaling_enabled = true
    min_count            = 1
    max_count            = 2
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
  }

  # Required by azurerm provider >= 5.5 (verified 2026-09-17). Manual mode
  # keeps AKS Node Auto Provisioning off - we manage node pools ourselves via
  # azurerm_kubernetes_cluster_node_pool below, matching the CLI lab.
  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    project = "k8s-ai-lab"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "spot_cpu" {
  name                  = "spotcpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.cpu_vm_size
  mode                  = "User"

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = -1 # pay up to the on-demand price rather than ever evict on price

  auto_scaling_enabled = true
  node_count           = 1
  min_count            = var.cpu_pool_min_count
  max_count            = var.cpu_pool_max_count

  # AKS auto-taints Spot pools with kubernetes.azure.com/scalesetpriority=spot:NoSchedule -
  # matching the CLI path, we don't add a redundant explicit taint here.
  node_labels = {
    workload = "general"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "spot_gpu" {
  count = var.create_gpu_pool ? 1 : 0

  name                  = "gpuspot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.gpu_vm_size
  mode                  = "User"

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = -1

  auto_scaling_enabled = true
  node_count           = 0 # scale-to-zero: no cost until a GPU pod is Pending
  min_count            = 0
  max_count            = var.gpu_pool_max_count

  node_labels = {
    "nvidia.com/gpu.present" = "true"
    workload                 = "gpu"
  }
  node_taints = [
    "nvidia.com/gpu=present:NoSchedule",
  ]
}
