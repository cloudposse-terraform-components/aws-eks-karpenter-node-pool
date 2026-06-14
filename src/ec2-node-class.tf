# This provisions the NodeClass for the NodePool.
# https://karpenter.sh/docs/concepts/nodeclasses/
#
# We keep it separate from the NodePool creation,
# even though there is a 1-to-1 mapping between the two,
# to make it a little easier to compare the implementation here
# with the Karpenter documentation, and to track changes as
# Karpenter evolves.
#
# When auto_mode_enabled is true, we create a simplified NodeClass
# using the eks.amazonaws.com/v1 API instead of karpenter.k8s.aws/v1.
# Auto Mode NodeClass does not support EC2-specific fields like
# amiSelectorTerms, metadataOptions, blockDeviceMappings, amiFamily,
# detailedMonitoring, or userData.

locals {
  # If you include a field but set it to null, the field will be omitted from the Kubernetes resource,
  # but the Kubernetes provider will still try to include it with a null value,
  # which will cause perpetual diff in the Terraform plan.
  # We strip out the null values from block_device_mappings here, because it is too complicated to do inline.
  node_block_device_mappings = { for pk, pv in local.node_pools : pk => [
    for i, map in coalesce(pv.block_device_mappings, []) : merge({
      for dk, dv in map : dk => dv if dk != "ebs" && dv != null
    }, try(length(map.ebs), 0) == 0 ? {} : { ebs = { for ek, ev in map.ebs : ek => ev if ev != null } })
    ]
  }

  # Split node pools by mode for the appropriate NodeClass resource
  self_managed_node_pools = module.eks.outputs.auto_mode_enabled ? {} : local.node_pools
  auto_mode_node_pools    = module.eks.outputs.auto_mode_enabled ? local.node_pools : {}
}

# Self-managed Karpenter EC2NodeClass (karpenter.k8s.aws/v1)
# https://karpenter.sh/docs/concepts/nodeclasses/
resource "kubernetes_manifest" "ec2_node_class" {
  for_each = local.self_managed_node_pools

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = coalesce(each.value.name, each.key)
    }
    spec = merge({
      role = module.eks.outputs.karpenter_iam_role_name
      subnetSelectorTerms = [for id in(each.value.private_subnets_enabled ? local.private_subnet_ids : local.public_subnet_ids) : {
        id = id
      }]
      securityGroupSelectorTerms = [{
        tags = {
          "aws:eks:cluster-name" = local.eks_cluster_id
        }
      }]
      # https://karpenter.sh/v1.0/concepts/nodeclasses/#specamiselectorterms
      amiSelectorTerms   = each.value.ami_selector_terms
      metadataOptions    = each.value.metadata_options
      tags               = module.this.tags
      detailedMonitoring = each.value.detailed_monitoring
      userData           = each.value.user_data != null ? each.value.user_data : null
      }, try(length(local.node_block_device_mappings[each.key]), 0) == 0 ? {} : {
      blockDeviceMappings = local.node_block_device_mappings[each.key]
      },
      each.value.ami_family == null ? {} : {
        amiFamily = each.value.ami_family
      },
      each.value.instance_store_policy == null ? {} : {
        instanceStorePolicy = each.value.instance_store_policy
    })
  }
}

# Auto Mode NodeClass (eks.amazonaws.com/v1)
# https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html
# Auto Mode NodeClass does not support EC2-specific fields like
# amiSelectorTerms, metadataOptions, blockDeviceMappings, amiFamily,
# detailedMonitoring, or userData.
#
# Note: custom tags are NOT supported in Auto Mode NodeClass.
# The AmazonEKSComputePolicy restricts launch template tag keys to
# eks:* and kubernetes.io/cluster/* patterns only.
resource "kubernetes_manifest" "auto_mode_node_class" {
  for_each = local.auto_mode_node_pools

  lifecycle {
    precondition {
      condition     = module.eks.outputs.auto_mode_node_role_name != null && module.eks.outputs.auto_mode_node_role_name != "deleted"
      error_message = "EKS Auto Mode requires eks.auto_mode_node_role_name to be set to a valid IAM role name. Ensure the eks/cluster component outputs auto_mode_node_role_name."
    }
  }

  manifest = {
    apiVersion = local.node_class_api_version
    kind       = local.node_class_kind
    metadata = {
      name = coalesce(each.value.name, each.key)
    }
    spec = merge(
      {
        # Required fields
        role = module.eks.outputs.auto_mode_node_role_name
        subnetSelectorTerms = [for id in(each.value.private_subnets_enabled ? local.private_subnet_ids : local.public_subnet_ids) : {
          id = id
        }]
        securityGroupSelectorTerms = [{
          tags = {
            "aws:eks:cluster-name" = local.eks_cluster_id
          }
        }]
      },
      # Optional fields - only included when set
      each.value.ephemeral_storage != null ? { ephemeralStorage = { for k, v in each.value.ephemeral_storage : k => v if v != null } } : {},
      each.value.snat_policy != null ? { snatPolicy = each.value.snat_policy } : {},
      each.value.network_policy != null ? { networkPolicy = each.value.network_policy } : {},
      each.value.network_policy_event_logs != null ? { networkPolicyEventLogs = each.value.network_policy_event_logs } : {},
      each.value.advanced_networking != null ? { advancedNetworking = { for k, v in each.value.advanced_networking : k => v if v != null } } : {},
      each.value.advanced_security != null ? { advancedSecurity = { for k, v in each.value.advanced_security : k => v if v != null } } : {},
      each.value.certificate_bundles != null ? { certificateBundles = each.value.certificate_bundles } : {},
      each.value.capacity_reservation_selector_terms != null ? { capacityReservationSelectorTerms = each.value.capacity_reservation_selector_terms } : {},
      each.value.pod_subnet_selector_terms != null ? { podSubnetSelectorTerms = each.value.pod_subnet_selector_terms } : {},
      each.value.pod_security_group_selector_terms != null ? { podSecurityGroupSelectorTerms = each.value.pod_security_group_selector_terms } : {},
    )
  }
}
