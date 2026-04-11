# Updating

## Migrating to EKS Auto Mode

This component now supports provisioning Karpenter `NodePool` and `NodeClass` resources against either:

- **Self-managed Karpenter** (the original behavior) — `karpenter.k8s.aws/v1` API
- **EKS Auto Mode** — `eks.amazonaws.com/v1` API

The mode is selected automatically from the upstream `eks/cluster` component output `auto_mode_enabled`. No
variable on this component needs to be flipped to switch modes — but several upstream and stack changes are
required.

### 1. Upgrade the upstream `eks/cluster` component

Starting from (`v1.541.0`)[https://github.com/cloudposse-terraform-components/aws-eks-cluster/releases/tag/v1.541.0] the `eks/cluster` component
must expose two new remote-state outputs consumed here:

- `auto_mode_enabled` (`bool`)
- `auto_mode_node_role_name` (`string`) — the IAM role attached to Auto Mode managed nodes

If you are using `account_map_enabled: false` and passing `var.eks` directly, add the new fields:

```yaml
components:
  terraform:
    eks/karpenter-node-pool:
      vars:
        eks:
          # ... existing fields
          auto_mode_enabled: true
          auto_mode_node_role_name: "my-cluster-auto-mode-node"
```

### 2. Remote-state version bump

`cloudposse/stack-config/yaml//modules/remote-state` is pinned to `2.0.0`. Run `terraform init -upgrade` after
pulling this change.

### 3. New `utils` provider requirement

`cloudposse/utils >= 2.0.0, < 3.0.0` has been added to `versions.tf`. `terraform init -upgrade` will fetch it.

### 4. Reserved NodePool names

EKS Auto Mode ships built-in NodePools named `general-purpose` and `system`. When `auto_mode_enabled` is true,
this component will fail a `check` block if any entry in `var.node_pools` resolves to one of those names
(either via the map key or via `name`). Rename any conflicting pools before upgrading.

### 5. NodePool requirement keys are auto-rewritten

Under Auto Mode, requirement keys with the prefix `karpenter.k8s.aws/` are automatically rewritten to
`eks.amazonaws.com/` (e.g. `karpenter.k8s.aws/instance-category` → `eks.amazonaws.com/instance-category`).
Existing `var.node_pools[*].requirements` entries do **not** need to be edited — but be aware that the rendered
manifest will differ.

### 6. Fields ignored under Auto Mode

Auto Mode `NodeClass` does not accept the EC2-specific fields below. They remain in `var.node_pools` for
backwards compatibility with self-managed Karpenter and are silently ignored when `auto_mode_enabled` is true:

- `ami_selector_terms`
- `ami_family`
- `block_device_mappings`
- `metadata_options`
- `detailed_monitoring`
- `user_data`
- `tags` (the `AmazonEKSComputePolicy` restricts launch-template tag keys to `eks:*` and
  `kubernetes.io/cluster/*`, so custom tags from `module.this.tags` are not propagated)

`ami_selector_terms` and `block_device_mappings` are now `optional()` in the variable schema, so node pools
intended only for Auto Mode can omit them entirely.

### 7. New optional Auto Mode fields

The following optional fields have been added to each entry of `var.node_pools` and apply only when
`auto_mode_enabled` is true:

| Field                                 | Purpose                                                                    |
| ------------------------------------- | -------------------------------------------------------------------------- |
| `ephemeral_storage`                   | `{ size, iops, throughput, kmsKeyID }` for the node root volume            |
| `snat_policy`                         | `"Random"` or `"Disabled"`                                                 |
| `network_policy`                      | `"DefaultAllow"` or `"DefaultDeny"`                                        |
| `network_policy_event_logs`           | `"Enabled"` or `"Disabled"`                                                |
| `advanced_networking`                 | Proxy / public IP / IPv4 prefix configuration                              |
| `advanced_security`                   | `{ fips }` (US regions only)                                               |
| `certificate_bundles`                 | Custom CA bundles to trust on the node                                     |
| `capacity_reservation_selector_terms` | Target on-demand capacity reservations                                     |
| `pod_subnet_selector_terms`           | Pod-level subnet selection (set together with `pod_security_group_*`)      |
| `pod_security_group_selector_terms`   | Pod-level SG selection (set together with `pod_subnet_selector_terms`)     |

See `variables.tf` for the full type definitions and the
[AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html) for value semantics.

### 8. Plan carefully — resources are replaced, not updated

Switching a cluster from self-managed Karpenter to Auto Mode causes the `kubernetes_manifest.ec2_node_class`
resources to be destroyed and `kubernetes_manifest.auto_mode_node_class` resources to be created in their
place. Drain workloads off Karpenter-managed nodes before applying, and review the plan output to confirm the
expected NodeClass kind (`EC2NodeClass` vs. `NodeClass`) and API group.
