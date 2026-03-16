
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

provider "aws" {
  region = var.region

  profile = module.iam_roles.profiles_enabled ? coalesce(var.import_profile_name, module.iam_roles.terraform_profile_name) : null

  dynamic "assume_role" {
    for_each = compact([module.iam_roles.terraform_role_arn])
    content {
      role_arn = coalesce(var.import_role_arn, module.iam_roles.terraform_role_arn)
    }
  }
}

module "iam_roles" {
  source  = "../../account-map/modules/iam-roles"
  context = module.this.context
}

variable "import_profile_name" {
  type        = string
  default     = null
  description = "AWS Profile name to use when importing a resource"
}

variable "import_role_arn" {
  type        = string
  default     = null
  description = "IAM Role ARN to use when importing a resource"
}
