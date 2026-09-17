terraform {
  required_version = ">= 1.5.7" # matches terraform-aws-modules/eks/aws v21's own floor

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.59" # floor required by terraform-aws-modules/eks/aws ~> 21.0
    }
  }

  # Remote state (recommended): S3 bucket + S3-native locking.
  # DynamoDB-based locking is deprecated as of Terraform 1.11 (the
  # dynamodb_table backend argument is slated for removal in a future minor
  # version) - use_lockfile replaces it with a lockfile object in the same
  # bucket, no separate table to provision or pay for. Verified 2026-09-17.
  #
  # backend "s3" {
  #   bucket       = "k8s-ai-lab-tfstate"   # pre-create with versioning + encryption enabled
  #   key          = "18-infrastructure-as-code/eks/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true                    # Terraform >= 1.10; replaces dynamodb_table
  #   encrypt      = true
  # }
}

provider "aws" {
  region = var.aws_region
}
