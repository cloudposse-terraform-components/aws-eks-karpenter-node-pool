
###############################################################################
# Direct input variables (used when account_map_enabled = false)
###############################################################################

variable "eks" {
  type = object({
    eks_cluster_id                         = optional(string, null)
    eks_cluster_arn                        = optional(string, null)
    eks_cluster_endpoint                   = optional(string, null)
    eks_cluster_certificate_authority_data = optional(string, null)
    eks_cluster_identity_oidc_issuer       = optional(string, null)
    karpenter_iam_role_arn                 = optional(string, null)
    karpenter_iam_role_name                = optional(string, null)
  })
  description = "EKS cluster outputs. When set, bypasses remote-state lookup of eks/cluster."
  default     = null
  nullable    = true
}


variable "vpc" {
  type = object({
    private_subnet_ids = optional(list(string), [])
    public_subnet_ids  = optional(list(string), [])
  })
  description = <<-EOT
    VPC configuration to use when `account_map_enabled` is `false`.
    Provides subnet IDs for Karpenter to launch instances in.
    EOT
  default = {
    private_subnet_ids = []
    public_subnet_ids  = []
  }
}

module "eks" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "2.0.0"

  component = var.eks_component_name

  bypass = !module.this.enabled || var.eks != null

  # Attempt to allow this component to be deleted from Terraform state even after the EKS cluster has been deleted
  defaults = {
    eks_cluster_id                         = try(var.eks.eks_cluster_id, "deleted")
    eks_cluster_arn                        = try(var.eks.eks_cluster_arn, "deleted")
    eks_cluster_identity_oidc_issuer       = try(var.eks.eks_cluster_identity_oidc_issuer, "deleted")
    karpenter_iam_role_arn                 = try(var.eks.karpenter_iam_role_arn, "deleted")
    karpenter_iam_role_name                = try(var.eks.karpenter_iam_role_name, "deleted")
    eks_cluster_endpoint                   = try(var.eks.eks_cluster_endpoint, null)
    eks_cluster_certificate_authority_data = try(var.eks.eks_cluster_certificate_authority_data, null)
  }

  context = module.this.context
}

module "vpc" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "2.0.0"

  bypass    = !module.this.enabled || length(var.vpc.private_subnet_ids) + length(var.vpc.public_subnet_ids) > 0
  component = var.vpc_component_name

  defaults = {
    private_subnet_ids = var.vpc.private_subnet_ids
    public_subnet_ids  = var.vpc.public_subnet_ids
  }

  context = module.this.context
}
