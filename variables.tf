variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group that will hold the AKS cluster and networking."
  type        = string
  default     = "rg-aks-platform"
}

variable "cluster_name" {
  description = "Name of the AKS cluster. Must be lowercase alphanumeric/hyphens."
  type        = string
  default     = "aks-platform"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be a valid DNS-1123 label (lowercase alphanumeric and hyphens)."
  }
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster's public FQDN."
  type        = string
  default     = "aksplatform"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster. Set to null to use the latest default offered by AKS."
  type        = string
  default     = null
}

variable "vnet_cidr" {
  description = "CIDR block for the hub virtual network. Subnets are carved out of this range."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0))
    error_message = "vnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "system_node_count" {
  description = "Fixed node count for the system node pool (hosts core AKS addons)."
  type        = number
  default     = 2
}

variable "system_vm_size" {
  description = "VM SKU for system pool nodes."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "user_vm_size" {
  description = "VM SKU for user (workload) pool nodes."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "user_node_min_count" {
  description = "Minimum nodes for the autoscaled user node pool."
  type        = number
  default     = 1
}

variable "user_node_max_count" {
  description = "Maximum nodes for the autoscaled user node pool."
  type        = number
  default     = 5
}

variable "enable_log_analytics" {
  description = "Create a Log Analytics workspace and send the cluster control-plane logs to it via a diagnostic setting."
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Data retention in days for the Log Analytics workspace."
  type        = number
  default     = 30
}

variable "enable_key_vault_provider" {
  description = "Enable the Azure Key Vault secrets provider addon (with secret rotation)."
  type        = bool
  default     = false
}

variable "enable_ingress_subnet" {
  description = "Create a dedicated subnet for ingress controllers / Application Gateway."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags merged into every resource."
  type        = map(string)
  default     = {}
}
