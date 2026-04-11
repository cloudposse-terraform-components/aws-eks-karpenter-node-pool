# Create Provisioning Configuration
# https://karpenter.sh/docs/concepts/

locals {
  enabled = module.this.enabled

  private_subnet_ids = module.vpc.outputs.private_subnet_ids
  public_subnet_ids  = module.vpc.outputs.public_subnet_ids

  # Auto Mode uses a different NodeClass API
  node_class_api_version = module.eks.outputs.auto_mode_enabled ? "eks.amazonaws.com/v1" : "karpenter.k8s.aws/v1"
  node_class_kind        = module.eks.outputs.auto_mode_enabled ? "NodeClass" : "EC2NodeClass"
  node_class_group       = module.eks.outputs.auto_mode_enabled ? "eks.amazonaws.com" : "karpenter.k8s.aws"

  node_pools = { for k, v in var.node_pools : k => v if local.enabled }
  kubelets_specs_filtered = { for k, v in local.node_pools : k => {
    for kk, vv in v.kubelet : kk => vv if vv != null
    }
  }
  kubelet_specs = { for k, v in local.kubelets_specs_filtered : k => v if length(v) > 0 }
}

# https://karpenter.sh/docs/concepts/nodepools/

resource "kubernetes_manifest" "node_pool" {
  for_each = local.node_pools

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = coalesce(each.value.name, each.key)
    }
    spec = {
      limits = merge({
        cpu    = each.value.total_cpu_limit,
        memory = each.value.total_memory_limit
      }, try(each.value.gpu_total_limits, {}))
      weight = each.value.weight
      disruption = merge({
        consolidationPolicy = each.value.disruption.consolidation_policy
        consolidateAfter    = each.value.disruption.consolidate_after == null ? 0 : each.value.disruption.consolidate_after
        },
        length(each.value.disruption.budgets) == 0 ? {} : {
          budgets = each.value.disruption.budgets
        }
      )
      template = {
        metadata = merge(
          {},
          try(length(each.value.labels), 0) > 0 ? { labels = each.value.labels } : {},
          try(length(each.value.annotations), 0) > 0 ? { annotations = each.value.annotations } : {}
        )
        spec = merge({
          nodeClassRef = {
            group = local.node_class_group
            kind  = local.node_class_kind
            name  = coalesce(each.value.name, each.key)
          },
          expireAfter = each.value.disruption.max_instance_lifetime
          },
          try(length(each.value.requirements), 0) == 0 ? {} : {
            requirements = [for r in each.value.requirements : merge({
              # Auto Mode uses eks.amazonaws.com/* labels instead of karpenter.k8s.aws/*
              key      = module.eks.outputs.auto_mode_enabled ? replace(r.key, "karpenter.k8s.aws/", "eks.amazonaws.com/") : r.key
              operator = r.operator
              },
              try(length(r.values), 0) == 0 ? {} : {
                values = r.values
            })]
          },
          try(length(each.value.taints), 0) == 0 ? {} : {
            taints = each.value.taints
          },
          try(length(each.value.startup_taints), 0) == 0 ? {} : {
            startupTaints = each.value.startup_taints
          },
          try(local.kubelet_specs[each.key], null) == null ? {} : {
            kubelet = local.kubelet_specs[each.key]
          }
        )
      }
    }
  }

  depends_on = [kubernetes_manifest.ec2_node_class, kubernetes_manifest.auto_mode_node_class]

  # Marks the field as managed by Kubernetes to avoid continually detecting drift
  # https://github.com/hashicorp/terraform-provider-kubernetes/issues/1378
  computed_fields = [
    "spec.template.spec.taints",
    "spec.disruption.budgets"
  ]
}

check "auto_mode_node_pool_name_conflict" {
  assert {
    condition = !local.enabled || !module.eks.outputs.auto_mode_enabled || length(setintersection(
      toset([for k, v in var.node_pools : coalesce(v.name, k)]),
      toset(["general-purpose", "system"])
    )) == 0
    error_message = "Custom NodePool names cannot conflict with Auto Mode built-in pools: 'general-purpose' and 'system'."
  }
}
