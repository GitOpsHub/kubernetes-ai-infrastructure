variable "aws_region" {
  description = "AWS region (matches AWS_REGION in env.sh)."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name (matches EKS_CLUSTER in env.sh)."
  type        = string
  default     = "eks-ai-lab"
}

variable "kubernetes_version" {
  type    = string
  default = "1.35" # matches eks/cluster.yaml's eksctl version pin
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "azs" {
  description = "Availability zones for the VPC. Spread across at least 2 for spot capacity diversity."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "cpu_instance_types" {
  description = "Diversified instance types for the spot CPU pool - more types means fewer InsufficientInstanceCapacity failures."
  type        = list(string)
  default     = ["m6i.large", "m5.large", "m5a.large", "m7i.large", "t3.large", "t3a.large"]
}

variable "cpu_pool_min_size" {
  type    = number
  default = 1
}

variable "cpu_pool_desired_size" {
  type    = number
  default = 2
}

variable "cpu_pool_max_size" {
  type    = number
  default = 4
}

variable "create_gpu_pool" {
  description = "Whether to create the spot GPU managed node group (kept at 0 desired/min either way)."
  type        = bool
  default     = true
}

variable "gpu_instance_types" {
  description = "L4 (g6) and T4 (g4dn) - both 4 vCPU spot instances, matching eks/cluster.yaml."
  type        = list(string)
  default     = ["g6.xlarge", "g4dn.xlarge"]
}

variable "gpu_pool_max_size" {
  type    = number
  default = 1
}
