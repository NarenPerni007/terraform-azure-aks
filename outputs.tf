output "resource_group_name" {
  description = "Name of the resource group holding the cluster."
  value       = azurerm_resource_group.main.name
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_id" {
  description = "Full Azure resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_fqdn" {
  description = "Public FQDN of the cluster API server."
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL - use it to set up federated credentials for workload identity."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "node_resource_group" {
  description = "AKS-managed node resource group (MC_...). Deleted automatically with the cluster."
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "kubeconfig_command" {
  description = "Azure CLI command to fetch kubeconfig for this cluster."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name} --overwrite-existing"
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID (empty when disabled)."
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].id : null
}
