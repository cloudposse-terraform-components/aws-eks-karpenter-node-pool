##################
#
# Variables and locals for Kubernetes/Helm provider configuration.
# Separated from provider-helm.tf so the provider file can be safely replaced
# by an Atmos generate block without losing variable declarations.
#
# It depends on module.eks to provide the EKS cluster information.
#
# All the following variables are just about configuring the Kubernetes provider
# to be able to modify EKS cluster. The reason there are so many options is
# because at various times, each one of them has had problems, so we give you a choice.
#
# The reason there are so many "enabled" inputs rather than automatically
# detecting whether or not they are enabled based on the value of the input
# is that any logic based on input values requires the values to be known during
# the "plan" phase of Terraform, and often they are not, which causes problems.
#
variable "kubeconfig_file_enabled" {
  type        = bool
  default     = false
  description = "If `true`, configure the Kubernetes provider with `kubeconfig_file` and use that kubeconfig file for authenticating to the EKS cluster"
  nullable    = false
}

variable "kubeconfig_file" {
  type        = string
  default     = ""
  description = "The Kubernetes provider `config_path` setting to use when `kubeconfig_file_enabled` is `true`"
  nullable    = false
}

variable "kubeconfig_context" {
  type        = string
  default     = ""
  description = <<-EOT
    Context to choose from the Kubernetes config file.
    If supplied, `kubeconfig_context_format` will be ignored.
    EOT
  nullable    = false
}

variable "kubeconfig_context_format" {
  type        = string
  default     = ""
  description = <<-EOT
    A format string to use for creating the `kubectl` context name when
    `kubeconfig_file_enabled` is `true` and `kubeconfig_context` is not supplied.
    Must include a single `%s` which will be replaced with the cluster name.
    EOT
  nullable    = false
}

variable "kube_data_auth_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    If `true`, use an `aws_eks_cluster_auth` data source to authenticate to the EKS cluster.
    Disabled by `kubeconfig_file_enabled` or `kube_exec_auth_enabled`.
    EOT
  nullable    = false
}

variable "kube_exec_auth_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    If `true`, use the Kubernetes provider `exec` feature to execute `aws eks get-token` to authenticate to the EKS cluster.
    Disabled by `kubeconfig_file_enabled`, overrides `kube_data_auth_enabled`.
    EOT
  nullable    = false
}

variable "kube_exec_auth_role_arn" {
  type        = string
  default     = ""
  description = "The role ARN for `aws eks get-token` to use"
  nullable    = false
}

variable "kube_exec_auth_role_arn_enabled" {
  type        = bool
  default     = true
  description = "If `true`, pass `kube_exec_auth_role_arn` as the role ARN to `aws eks get-token`"
  nullable    = false
}

variable "kube_exec_auth_aws_profile" {
  type        = string
  default     = ""
  description = "The AWS config profile for `aws eks get-token` to use"
  nullable    = false
}

variable "kube_exec_auth_aws_profile_enabled" {
  type        = bool
  default     = false
  description = "If `true`, pass `kube_exec_auth_aws_profile` as the `profile` to `aws eks get-token`"
  nullable    = false
}

variable "kubeconfig_exec_auth_api_version" {
  type        = string
  default     = "client.authentication.k8s.io/v1beta1"
  description = "The Kubernetes API version of the credentials returned by the `exec` auth plugin"
  nullable    = false
}

variable "helm_manifest_experiment_enabled" {
  type        = bool
  default     = false
  description = "Enable storing of the rendered manifest for helm_release so the full diff of what is changing can been seen in the plan"
  nullable    = false
}

locals {
  kubeconfig_file_enabled = var.kubeconfig_file_enabled
  kubeconfig_file         = local.kubeconfig_file_enabled ? var.kubeconfig_file : ""
  kubeconfig_context = !local.kubeconfig_file_enabled ? "" : (
    length(var.kubeconfig_context) != 0 ? var.kubeconfig_context : (
      length(var.kubeconfig_context_format) != 0 ? format(var.kubeconfig_context_format, local.eks_cluster_id) : ""
    )
  )

  kube_exec_auth_enabled = local.kubeconfig_file_enabled ? false : var.kube_exec_auth_enabled
  kube_data_auth_enabled = local.kube_exec_auth_enabled ? false : var.kube_data_auth_enabled

  # Eventually we might try to get this from an environment variable
  kubeconfig_exec_auth_api_version = var.kubeconfig_exec_auth_api_version

  exec_profile = local.kube_exec_auth_enabled && var.kube_exec_auth_aws_profile_enabled ? [
    "--profile", var.kube_exec_auth_aws_profile
  ] : []

  kube_exec_auth_role_arn = var.kube_exec_auth_role_arn
  exec_role = local.kube_exec_auth_enabled && var.kube_exec_auth_role_arn_enabled ? [
    "--role-arn", local.kube_exec_auth_role_arn
  ] : []

  # Provide dummy configuration for the case where the EKS cluster is not available.
  certificate_authority_data = local.kubeconfig_file_enabled ? null : try(module.eks.outputs.eks_cluster_certificate_authority_data, null)
  cluster_ca_certificate     = local.kubeconfig_file_enabled ? null : try(base64decode(local.certificate_authority_data), null)
  # Use coalesce+try to handle both the case where the output is missing and the case where it is empty.
  eks_cluster_id       = coalesce(try(module.eks.outputs.eks_cluster_id, ""), "missing")
  eks_cluster_endpoint = local.kubeconfig_file_enabled ? null : try(module.eks.outputs.eks_cluster_endpoint, "")
}

data "aws_eks_cluster_auth" "eks" {
  count = local.kube_data_auth_enabled ? 1 : 0
  name  = local.eks_cluster_id
}
