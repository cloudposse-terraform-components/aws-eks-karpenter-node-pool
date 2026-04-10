variable "account_map_enabled" {
  type        = bool
  description = <<-EOT
    Enable account map and remote state lookups.
    When `true`, fetch EKS cluster and VPC information from Terraform remote state.
    When `false`, use the `eks` and `vpc` variables to provide values directly.
    EOT
  default     = true
  nullable    = false
}
