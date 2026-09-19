# Terraform equivalent of 00-prerequisites-and-cluster-setup's `eksctl create cluster -f
# eks/cluster.yaml` step: a VPC, an EKS cluster, a spot-cpu managed node group
# (diversified instance types, autoscaling 1..4), and a spot-gpu managed node
# group (autoscaling 0..1, tainted).
#
# We use the community terraform-aws-modules/eks/aws module rather than hand-
# rolling aws_eks_cluster - unlike GKE/AKS, raw EKS provisioning also needs
# OIDC provider wiring, the aws-auth/access-entry dance, and node IAM roles
# that the module gets right and keeps current. Version and input names below
# verified 2026-09-17 against the module's own README/variables.tf at tag
# v21.25.0 (latest v21.x): `name` / `kubernetes_version` replaced the older
# `cluster_name` / `cluster_version` inputs as of the v21 major - don't copy
# examples from pre-v21 blog posts without checking.

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = true # one NAT for a lab VPC; use per-AZ NAT for production HA
  enable_dns_hostnames = true

  # Required so the AWS Load Balancer Controller / EKS can auto-discover
  # subnets for internal vs internet-facing load balancers later (chapter 12).
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  eks_managed_node_groups = merge(
    {
      spot-cpu = {
        ami_type       = "AL2023_x86_64_STANDARD"
        instance_types = var.cpu_instance_types
        capacity_type  = "SPOT"

        min_size     = var.cpu_pool_min_size
        max_size     = var.cpu_pool_max_size
        desired_size = var.cpu_pool_desired_size

        disk_size = 50
        labels = {
          workload = "general"
        }
      }
    },
    var.create_gpu_pool ? {
      spot-gpu = {
        # eksctl's amiFamily: AmazonLinux2023 picks the AL2023 NVIDIA-enabled
        # AMI automatically for GPU instance types; the module does the same
        # when ami_type is left unset and instance_types are GPU families, but
        # setting it explicitly keeps this reproducible.
        ami_type       = "AL2023_x86_64_NVIDIA"
        instance_types = var.gpu_instance_types
        capacity_type  = "SPOT"

        min_size     = 0
        max_size     = var.gpu_pool_max_size
        desired_size = 0 # scale-to-zero: no cost until a GPU pod is Pending

        disk_size = 100
        labels = {
          workload = "gpu"
        }
        taints = {
          gpu = {
            key    = "nvidia.com/gpu"
            value  = "present"
            effect = "NO_SCHEDULE"
          }
        }
      }
    } : {}
  )

  tags = {
    project = "k8s-ai-lab"
  }
}

# EKS has no built-in autoscaler: the spot-gpu group's min_size/desired_size of 0 will stay
# at 0 until you scale it manually (`eksctl scale nodegroup`, see 01-gpu-nodes-and-scheduling's
# README) or install Karpenter/Cluster Autoscaler (13-node-autoscaling-and-cost) - this module
# doesn't change that behavior, it's an EKS platform limitation.
