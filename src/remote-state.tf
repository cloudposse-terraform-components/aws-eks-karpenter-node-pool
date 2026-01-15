locals {
  # Remote state is enabled when var.remote_state_enabled is true and the module is enabled
  eks_remote_state_enabled = local.enabled && var.remote_state_enabled
  vpc_remote_state_enabled = local.enabled && var.remote_state_enabled

  # Validation: when remote_state_enabled is false, all direct variables must be provided
  _validate_direct_vars = !var.remote_state_enabled ? (
    var.eks_cluster_id != null &&
    var.eks_cluster_endpoint != null &&
    var.eks_cluster_certificate_authority_data != null &&
    var.karpenter_iam_role_name != null &&
    (var.private_subnet_ids != null || var.public_subnet_ids != null)
  ) : true
}

# Validation resource to ensure proper configuration
resource "terraform_data" "validate_config" {
  count = local.enabled ? 1 : 0

  lifecycle {
    precondition {
      condition     = local._validate_direct_vars
      error_message = <<-EOT
        When remote_state_enabled is false, all direct input variables must be provided:
          - eks_cluster_id
          - eks_cluster_endpoint
          - eks_cluster_certificate_authority_data
          - karpenter_iam_role_name
          - private_subnet_ids and/or public_subnet_ids
      EOT
    }
  }
}

module "eks" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.0"

  bypass    = !local.eks_remote_state_enabled
  component = var.eks_component_name

  defaults = {
    eks_cluster_id                         = "deleted"
    eks_cluster_arn                        = "deleted"
    eks_cluster_identity_oidc_issuer       = "deleted"
    karpenter_node_role_arn                = "deleted"
    eks_cluster_endpoint                   = ""
    eks_cluster_certificate_authority_data = ""
    karpenter_iam_role_name                = ""
  }

  context = module.this.context
}

module "vpc" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.0"

  bypass    = !local.vpc_remote_state_enabled
  component = var.vpc_component_name

  defaults = {
    private_subnet_ids = []
    public_subnet_ids  = []
  }

  context = module.this.context
}
