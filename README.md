# terraform-azure-aks

Production-ready Terraform for deploying an Azure Kubernetes Service (AKS) cluster **from scratch**: resource group, virtual network with dedicated subnets, NSG and route-table guardrails, Log Analytics, and an AKS cluster with a system node pool plus an autoscaled user node pool — all with raw `azurerm_*` resources, no registry modules.

## What it provisions

- **Resource group** for the platform
- **Virtual network** (`10.0.0.0/16` by default) with three subnets:
  - `snet-system` — system node pool (core AKS addons only)
  - `snet-user` — autoscaled workload node pool
  - `snet-ingress` — dedicated subnet for ingress controllers / App Gateway (toggleable)
- **Network security group** on the workload subnets (allows Azure Load Balancer probes, denies other inbound)
- **Route table** associated to the workload subnets (ready for forced tunneling through a firewall/NVA)
- **Log Analytics workspace** feeding **Container Insights** (toggleable)
- **AKS cluster** with:
  - System-assigned managed identity (no service-principal secrets)
  - OIDC issuer + **workload identity** enabled (pod-level Azure access without secrets)
  - Azure CNI networking
  - Fixed system node pool (`onlyCriticalAddons`) + autoscaling user node pool (tainted `workload=true:NoSchedule`)
  - Optional Key Vault secrets-provider addon with secret rotation

## Architecture

```
                        ┌─────────────────────────────────────────────────┐
                        │            Resource Group (rg-aks-platform)       │
                        │                                                 │
  Internet ──► ┌────────┴────────┐   ┌──────────────────────────────┐     │
               │  Azure LB (std) │   │  VNet 10.0.0.0/16             │     │
               └────────┬────────┘   │                              │     │
                        │            │  ┌─────────┐  ┌──────────┐    │     │
                        │            │  │snet-    │  │snet-user │    │     │
                        └───────────►│  │system   │  │(autoscale│    │     │
                                     │  │(system  │  │ user pool│    │     │
                                     │  │pool)    │  │ 1-5)     │    │     │
                                     │  └─────────┘  └──────────┘    │     │
                                     │  ┌──────────────────────┐    │     │
                                     │  │ snet-ingress         │    │     │
                                     │  │ (ingress / AppGW)    │    │     │
                                     │  └──────────────────────┘    │     │
                                     │  NSG + route table on       │     │
                                     │  workload subnets           │     │
                                     └──────────────────────────────┘     │
                        ┌─────────────────────────────────────────────────┐
                        │ Log Analytics ──► Container Insights dashboards │
                        └─────────────────────────────────────────────────┘
```

## Prerequisites

- An Azure subscription with permissions to create resource groups, VNets, and AKS clusters
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5

## Quickstart

```bash
# 1. Authenticate (Terraform uses the Azure CLI session)
az login
az account set --subscription "<your-subscription-name>"

# 2. Initialise, review the plan, apply
terraform init
terraform plan -out aks.plan
terraform apply aks.plan

# 3. Connect kubectl
eval "$(terraform output -raw kubeconfig_command)"
kubectl get nodes
```

> **Cost note:** an AKS control plane is free, but nodes, load balancer, and Log Analytics ingestion bill hourly. Run `terraform destroy` when you're done experimenting.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `location` | Azure region | `string` | `"eastus"` |
| `resource_group_name` | Resource group name | `string` | `"rg-aks-platform"` |
| `cluster_name` | AKS cluster name (validated) | `string` | `"aks-platform"` |
| `dns_prefix` | DNS prefix for the cluster FQDN | `string` | `"aksplatform"` |
| `kubernetes_version` | K8s version (`null` = AKS default) | `string` | `null` |
| `vnet_cidr` | VNet CIDR (subnets carved via `cidrsubnet`) | `string` | `"10.0.0.0/16"` |
| `system_node_count` | Fixed system-pool node count | `number` | `2` |
| `system_vm_size` | System-pool VM SKU | `string` | `"Standard_D4s_v5"` |
| `user_vm_size` | User-pool VM SKU | `string` | `"Standard_D4s_v5"` |
| `user_node_min_count` | User-pool autoscale min | `number` | `1` |
| `user_node_max_count` | User-pool autoscale max | `number` | `5` |
| `enable_log_analytics` | Create Log Analytics + Container Insights | `bool` | `true` |
| `log_analytics_retention_days` | Log retention (days) | `number` | `30` |
| `enable_key_vault_provider` | Key Vault secrets-provider addon | `bool` | `false` |
| `enable_ingress_subnet` | Dedicated ingress subnet | `bool` | `true` |
| `tags` | Extra tags merged into all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `resource_group_name` | Resource group name |
| `cluster_name` / `cluster_id` / `cluster_fqdn` | Cluster identity |
| `oidc_issuer_url` | For workload-identity federated credentials |
| `node_resource_group` | AKS-managed `MC_*` resource group |
| `kubeconfig_command` | Ready-to-run `az aks get-credentials` command |
| `log_analytics_workspace_id` | Workspace ID (`null` when disabled) |

## Cleanup

```bash
terraform destroy
```

The AKS-managed node resource group (`MC_...`) is deleted automatically with the cluster — the provider is configured with `prevent_deletion_if_contains_resources = false` so destroy doesn't get stuck on it.

## Design decisions

- **Managed identity over service principal** — no client secrets to create, store, or rotate.
- **Azure CNI** — pods get real VNet IPs, which simplifies network policy and on-prem/VPN connectivity versus kubenet.
- **Separate user pool for workloads** — the system pool runs with `onlyCriticalAddons` and the user pool carries a `NoSchedule` taint, so a noisy workload can never starve `coredns` or the metrics server.
- **Workload identity (OIDC)** — pods get Azure AD identities via federation; no `aad-pod-identity` daemonset, no secrets in etcd.
- **Route table placeholder** — `rt-aks` ships empty but associated, so forcing egress through a firewall later is a one-block change instead of a subnet migration.
- **No registry modules** — every resource is explicit, so the whole platform is auditable in one `main.tf`.

## Upgrading

- **azurerm 3.x to 4.x.** The provider constraint is now `~> 4.0`. Three breaking changes in 4.x touched this repo:
  - The `oms_agent` block was removed from `azurerm_kubernetes_cluster`. Control-plane logs now flow through an `azurerm_monitor_diagnostic_setting` resource (kube-apiserver, kube-audit, kube-controller-manager, kube-scheduler, plus AllMetrics) instead of the in-cluster agent addon.
  - `enable_auto_scaling` on the user node pool is now `auto_scaling_enabled`.
  - `dns_service_ip` was removed from `network_profile`; the DNS service IP is inferred from `service_cidr` (10.2.0.0/24 here, so the DNS IP stays 10.2.0.10).
- Run `terraform init -upgrade` to pull the new major version, and review the plan before applying. On an existing cluster, the provider upgrade itself should not force recreation, but confirm that in the plan.
