##################
#
# Helm and Kubernetes provider configuration.
# Variables and locals are declared in kubeconfig-variables.tf.
# This file can be safely replaced by an Atmos generate block to switch
# authentication methods (e.g., kubeconfig file vs exec auth).
#
provider "helm" {
  kubernetes {
    host                   = local.eks_cluster_endpoint
    cluster_ca_certificate = local.cluster_ca_certificate
    token                  = local.kube_data_auth_enabled ? one(data.aws_eks_cluster_auth.eks[*].token) : null
    # It is too confusing to allow the Kubernetes provider to use environment variables to set authentication
    # in this module because we have so many options, so we override environment variables like `KUBE_CONFIG_PATH`
    # in all cases. People can still use environment variables by setting TF_VAR_kubeconfig_file.
    config_path    = local.kubeconfig_file
    config_context = local.kubeconfig_context

    dynamic "exec" {
      for_each = local.kube_exec_auth_enabled && local.certificate_authority_data != null ? ["exec"] : []
      content {
        api_version = local.kubeconfig_exec_auth_api_version
        command     = "aws"
        args = concat(local.exec_profile, [
          "eks", "get-token", "--cluster-name", local.eks_cluster_id
        ], local.exec_role)
      }
    }
  }
  experiments {
    manifest = var.helm_manifest_experiment_enabled && module.this.enabled
  }
}

provider "kubernetes" {
  host                   = local.eks_cluster_endpoint
  cluster_ca_certificate = local.cluster_ca_certificate
  token                  = local.kube_data_auth_enabled ? one(data.aws_eks_cluster_auth.eks[*].token) : null
  # It is too confusing to allow the Kubernetes provider to use environment variables to set authentication
  # in this module because we have so many options, so we override environment variables like `KUBE_CONFIG_PATH`
  # in all cases. People can still use environment variables by setting TF_VAR_kubeconfig_file.
  config_path    = local.kubeconfig_file
  config_context = local.kubeconfig_context

  dynamic "exec" {
    for_each = local.kube_exec_auth_enabled && local.certificate_authority_data != null ? ["exec"] : []
    content {
      api_version = local.kubeconfig_exec_auth_api_version
      command     = "aws"
      args = concat(local.exec_profile, [
        "eks", "get-token", "--cluster-name", local.eks_cluster_id
      ], local.exec_role)
    }
  }
}
