variable "region" {
  type        = string
  description = "AWS Region"
}

variable "eks_component_name" {
  type        = string
  description = <<-EOT
    The name of the EKS component. Used to fetch EKS cluster information from remote state
    when `account_map_enabled` is `true`.

    DEPRECATED: This variable (along with account_map_enabled=true) is deprecated and
    will be removed in a future version. Set `account_map_enabled = false` and use
    the direct EKS cluster input variables instead.
    EOT
  default     = "eks/cluster"
}

variable "vpc_component_name" {
  type        = string
  description = <<-EOT
    The name of the VPC component. Used to fetch VPC information from remote state
    when `account_map_enabled` is `true`.

    DEPRECATED: This variable (along with account_map_enabled=true) is deprecated and
    will be removed in a future version. Set `account_map_enabled = false` and use
    the direct subnet ID input variables instead.
    EOT
  default     = "vpc"
}

###############################################################################
# Direct input variables (used when account_map_enabled = false)
###############################################################################

variable "eks" {
  type = object({
    eks_cluster_id                         = optional(string, "")
    eks_cluster_arn                        = optional(string, "")
    eks_cluster_endpoint                   = optional(string, "")
    eks_cluster_certificate_authority_data = optional(string, "")
    eks_cluster_identity_oidc_issuer       = optional(string, "")
    karpenter_iam_role_name                = optional(string, "")
    karpenter_node_role_arn                = optional(string, "")
    auto_mode_node_role_name               = optional(string, "")
    auto_mode_enabled                      = optional(bool, false)
  })
  description = <<-EOT
    EKS cluster configuration to use when `account_map_enabled` is `false`.
    Provides cluster details for Karpenter node pool configuration.
    EOT
  default = {
    eks_cluster_id                         = ""
    eks_cluster_arn                        = ""
    eks_cluster_endpoint                   = ""
    eks_cluster_certificate_authority_data = ""
    eks_cluster_identity_oidc_issuer       = ""
    karpenter_iam_role_name                = ""
    karpenter_node_role_arn                = ""
    auto_mode_node_role_name               = ""
    auto_mode_enabled                      = false
  }
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

variable "node_pools" {
  type = map(object({
    # The name of the Karpenter provisioner. The map key is used if this is not set.
    name = optional(string)
    # Whether to place EC2 instances launched by Karpenter into VPC private subnets. Set it to `false` to use public subnets.
    private_subnets_enabled = bool
    # The Disruption spec controls how Karpenter scales down the node group.
    # See the example (sadly not the specific `spec.disruption` documentation) at https://karpenter.sh/docs/concepts/nodepools/ for details
    disruption = optional(object({
      # Describes which types of Nodes Karpenter should consider for consolidation.
      # If using 'WhenUnderutilized', Karpenter will consider all nodes for consolidation and attempt to remove or
      # replace Nodes when it discovers that the Node is underutilized and could be changed to reduce cost.
      # If using `WhenEmpty`, Karpenter will only consider nodes for consolidation that contain no workload pods.
      consolidation_policy = optional(string, "WhenUnderutilized")

      # The amount of time Karpenter should wait after discovering a consolidation decision (`go` duration string, s, m, or h).
      # This value can currently (v0.36.0) only be set when the consolidationPolicy is 'WhenEmpty'.
      # You can choose to disable consolidation entirely by setting the string value 'Never' here.
      # Earlier versions of Karpenter called this field `ttl_seconds_after_empty`.
      consolidate_after = optional(string)

      # The amount of time a Node can live on the cluster before being removed (`go` duration string, s, m, or h).
      # You can choose to disable expiration entirely by setting the string value 'Never' here.
      # This module sets a default of 336 hours (14 days), while the Karpenter default is 720 hours (30 days).
      # Note that Karpenter calls this field "expiresAfter", and earlier versions called it `ttl_seconds_until_expired`,
      # but we call it "max_instance_lifetime" to match the corresponding field in EC2 Auto Scaling Groups.
      max_instance_lifetime = optional(string, "336h")

      # Budgets control the the maximum number of NodeClaims owned by this NodePool that can be terminating at once.
      # See https://karpenter.sh/docs/concepts/disruption/#disruption-budgets for details.
      # A percentage is the percentage of the total number of active, ready nodes not being deleted, rounded up.
      # If there are multiple active budgets, Karpenter uses the most restrictive value.
      # If left undefined, this will default to one budget with a value of nodes: 10%.
      # Note that budgets do not prevent or limit involuntary terminations.
      # Example:
      #   On Weekdays during business hours, don't do any deprovisioning.
      #     budgets = {
      #       schedule = "0 9 * * mon-fri"
      #       duration = 8h
      #       nodes    = "0"
      #     }
      budgets = optional(list(object({
        # The schedule specifies when a budget begins being active, using extended cronjob syntax.
        # See https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/#schedule-syntax for syntax details.
        # Timezones are not supported. This field is required if Duration is set.
        schedule = optional(string)
        # Duration determines how long a Budget is active after each Scheduled start.
        # If omitted, the budget is always active. This is required if Schedule is set.
        # Must be a whole number of minutes and hours, as cron does not work in seconds,
        # but since Go's `duration.String()` always adds a "0s" at the end, that is allowed.
        duration = optional(string)
        # The percentage or number of nodes that Karpenter can scale down during the budget.
        nodes = string
        # Reasons can be one of Drifted, Underutilized, or Empty
        # If omitted, it’s assumed that the budget applies to all reasons.
        # See https://karpenter.sh/v1.1/concepts/disruption/#reasons
        reasons = optional(list(string))
      })), [])
    }), {})
    # Karpenter provisioner total CPU limit for all pods running on the EC2 instances launched by Karpenter
    total_cpu_limit = string
    # Karpenter provisioner total memory limit for all pods running on the EC2 instances launched by Karpenter
    total_memory_limit = string
    # Additional resource limits (e.g., GPU, custom resources) to merge into spec.limits. Example: {"nvidia.com/gpu" = "1"}
    gpu_total_limits = optional(map(string), {})
    # Set a weight for this node pool.
    # See https://karpenter.sh/docs/concepts/scheduling/#weighted-nodepools
    weight      = optional(number, 50)
    labels      = optional(map(string))
    annotations = optional(map(string))
    # Karpenter provisioner taints configuration. See https://aws.github.io/aws-eks-best-practices/karpenter/#create-provisioners-that-are-mutually-exclusive for more details
    taints = optional(list(object({
      key    = string
      effect = string
      value  = optional(string)
    })))
    startup_taints = optional(list(object({
      key    = string
      effect = string
      value  = optional(string)
    })))
    # Karpenter node metadata options. See https://karpenter.sh/docs/concepts/nodeclasses/#specmetadataoptions for more details
    metadata_options = optional(object({
      httpEndpoint            = optional(string, "enabled")
      httpProtocolIPv6        = optional(string, "disabled")
      httpPutResponseHopLimit = optional(number, 2)
      # httpTokens can be either "required" or "optional"
      httpTokens = optional(string, "required")
    }), {})
    # Enable detailed monitoring for EC2 instances. See https://karpenter.sh/docs/concepts/nodeclasses/#specdetailedmonitoring
    detailed_monitoring = optional(bool, false)
    # User data script to pass to EC2 instances. See https://karpenter.sh/docs/concepts/nodeclasses/#specuserdata
    user_data = optional(string, null)
    # ami_family dictates the default bootstrapping logic.
    # It is only required if you do not specify amiSelectorTerms.alias
    ami_family = optional(string, null)
    # Selectors for the AMI used by Karpenter provisioner when provisioning nodes.
    # Usually use { alias = "<family>@latest" } but version can be pinned instead of "latest".
    # Based on the ami_selector_terms, Karpenter will automatically query for the appropriate EKS optimized AMI via AWS Systems Manager (SSM)
    ami_selector_terms = optional(list(any))
    # Karpenter nodes block device mappings. Controls the Elastic Block Storage volumes that Karpenter attaches to provisioned nodes.
    # Karpenter uses default block device mappings for the AMI Family specified.
    # For example, the Bottlerocket AMI Family defaults with two block device mappings,
    # and normally you only want to scale `/dev/xvdb` where Containers and there storage are stored.
    # Most other AMIs only have one device mapping at `/dev/xvda`.
    # See https://karpenter.sh/docs/concepts/nodeclasses/#specblockdevicemappings for more details
    block_device_mappings = optional(list(object({
      deviceName = string
      ebs = optional(object({
        volumeSize          = string
        volumeType          = string
        deleteOnTermination = optional(bool, true)
        encrypted           = optional(bool, true)
        iops                = optional(number)
        kmsKeyID            = optional(string, "alias/aws/ebs")
        snapshotID          = optional(string)
        throughput          = optional(number)
      }))
    })))
    # Set acceptable (In) and unacceptable (Out) Kubernetes and Karpenter values for node provisioning based on Well-Known Labels and cloud-specific settings. These can include instance types, zones, computer architecture, and capacity type (such as AWS spot or on-demand). See https://karpenter.sh/v0.18.0/provisioner/#specrequirements for more details
    requirements = list(object({
      key      = string
      operator = string
      # Operators like "Exists" and "DoesNotExist" do not require a value
      values = optional(list(string))
    }))
    # Any values for spec.template.spec.kubelet allowed by Karpenter.
    # Not fully specified, because they are subject to change.
    # See:
    #   https://karpenter.sh/docs/concepts/nodepools/#spectemplatespeckubelet
    #   https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/
    kubelet = optional(any, {})

    ###########################################################################
    # Auto Mode NodeClass fields (eks.amazonaws.com/v1)
    # https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html
    # These fields are only used when eks_auto_mode_enabled = true.
    # They are ignored for self-managed Karpenter (karpenter.k8s.aws/v1).
    ###########################################################################

    # Ephemeral storage configuration for Auto Mode nodes
    ephemeral_storage = optional(object({
      size       = optional(string) # Range: 1-59000Gi
      iops       = optional(number) # Range: 3000-16000
      throughput = optional(number) # Range: 125-1000
      kmsKeyID   = optional(string) # KMS key ID, ARN, alias name, or alias ARN
    }))
    # SNAT policy: "Random" or "Disabled"
    snat_policy = optional(string)
    # Network policy: "DefaultAllow" or "DefaultDeny"
    network_policy = optional(string)
    # Network policy event logs: "Disabled" or "Enabled"
    network_policy_event_logs = optional(string)
    # Advanced networking configuration
    advanced_networking = optional(object({
      associatePublicIPAddress = optional(bool)
      httpsProxy               = optional(string)
      noProxy                  = optional(list(string))
      ipv4PrefixSize           = optional(string) # "Auto" or "32"
      enableV4Egress           = optional(bool)
    }))
    # Advanced security configuration
    advanced_security = optional(object({
      fips = optional(bool) # US regions only
    }))
    # Custom certificate bundles (e.g. for proxy)
    certificate_bundles = optional(list(object({
      name = string
      data = string
    })))
    # Capacity reservation selector terms
    capacity_reservation_selector_terms = optional(list(any))
    # Pod subnet selector terms (must be set together with pod_security_group_selector_terms)
    pod_subnet_selector_terms = optional(list(any))
    # Pod security group selector terms (must be set together with pod_subnet_selector_terms)
    pod_security_group_selector_terms = optional(list(any))
  }))
  description = "Configuration for node pools. See code for details."
  nullable    = false
}
