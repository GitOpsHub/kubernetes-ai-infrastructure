variable "resource_group_name" {
  description = "Resource group name (matches AZ_RESOURCE_GROUP in env.sh)."
  type        = string
  default     = "rg-aks-ai-lab"
}

variable "location" {
  description = "Azure region (matches AZ_LOCATION in env.sh)."
  type        = string
  default     = "eastus"
}

variable "cluster_name" {
  description = "AKS cluster name (matches AKS_CLUSTER in env.sh)."
  type        = string
  default     = "aks-ai-lab"
}

variable "dns_prefix" {
  type    = string
  default = "aks-ai-lab"
}

variable "system_vm_size" {
  description = "AKS does not allow the default/system pool to be Spot - keep it small and Regular."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "cpu_vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "cpu_pool_min_count" {
  type    = number
  default = 0
}

variable "cpu_pool_max_count" {
  type    = number
  default = 3
}

variable "create_gpu_pool" {
  description = "Whether to create the spot GPU node pool (kept at 0 nodes either way)."
  type        = bool
  default     = true
}

variable "gpu_vm_size" {
  type    = string
  default = "Standard_NC4as_T4_v3"
}

variable "gpu_pool_max_count" {
  type    = number
  default = 1
}
