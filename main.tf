locals {
  common_tags = merge(var.tags, {
    managed-by = "terraform"
    project    = var.cluster_name
  })

  # Subnets carved from the VNet CIDR: system / user / ingress.
  system_subnet_cidr  = cidrsubnet(var.vnet_cidr, 8, 1) # e.g. 10.0.1.0/24
  user_subnet_cidr    = cidrsubnet(var.vnet_cidr, 8, 2) # e.g. 10.0.2.0/24
  ingress_subnet_cidr = cidrsubnet(var.vnet_cidr, 8, 3) # e.g. 10.0.3.0/24
}

# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# ---------------------------------------------------------------------------
# Networking: VNet + subnets
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.cluster_name}"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "system" {
  name                 = "snet-system"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.system_subnet_cidr]
}

resource "azurerm_subnet" "user" {
  name                 = "snet-user"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.user_subnet_cidr]
}

# Dedicated subnet for ingress controllers (e.g. ingress-nginx private
# internal LB, or an Azure Application Gateway in front of AKS).
resource "azurerm_subnet" "ingress" {
  count                = var.enable_ingress_subnet ? 1 : 0
  name                 = "snet-ingress"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.ingress_subnet_cidr]
}

# ---------------------------------------------------------------------------
# NSG: baseline guardrails on the workload subnets.
# AKS manages its own NSG on the node NICs; this one protects the subnets.
# ---------------------------------------------------------------------------
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-${var.cluster_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # Allow Azure Load Balancer health probes (required for LB-backed Services).
  security_rule {
    name                       = "AllowAzureLoadBalancerInBound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Deny everything else inbound by default; outbound stays open because
  # AKS nodes need internet egress (images, Azure APIs) unless a firewall
  # / NAT gateway with UDRs is in place.
  security_rule {
    name                       = "DenyAllInBound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "system" {
  subnet_id                 = azurerm_subnet.system.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_subnet_network_security_group_association" "user" {
  subnet_id                 = azurerm_subnet.user.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# ---------------------------------------------------------------------------
# Route table: placeholder for forced tunneling.
# Point 0.0.0.0/0 at an NVA / Azure Firewall here when egress must be
# inspected; AKS system pods then route through it instead of the internet.
# ---------------------------------------------------------------------------
resource "azurerm_route_table" "aks" {
  name                = "rt-${var.cluster_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # Example (disabled by default): force-tunnel internet egress via an NVA.
  # route {
  #   name                   = "egress-via-firewall"
  #   address_prefix         = "0.0.0.0/0"
  #   next_hop_type          = "VirtualAppliance"
  #   next_hop_in_ip_address = "10.0.100.4"
  # }
}

resource "azurerm_subnet_route_table_association" "system" {
  subnet_id      = azurerm_subnet.system.id
  route_table_id = azurerm_route_table.aks.id
}

resource "azurerm_subnet_route_table_association" "user" {
  subnet_id      = azurerm_subnet.user.id
  route_table_id = azurerm_route_table.aks.id
}

# ---------------------------------------------------------------------------
# Observability: Log Analytics workspace for Container Insights
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_log_analytics ? 1 : 0
  name                = "log-${var.cluster_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# AKS cluster
# ---------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  tags                = local.common_tags

  # Managed identity (no service-principal secret to rotate).
  identity {
    type = "SystemAssigned"
  }

  # Pod-level Azure identity without secrets.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                        = "system"
    node_count                  = var.system_node_count
    vm_size                     = var.system_vm_size
    vnet_subnet_id              = azurerm_subnet.system.id
    only_critical_addons_enabled = true # keep workloads off the system pool
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
      max_surge                     = "10%"
    }
  }

  network_profile {
    network_plugin    = "azure" # Azure CNI: pods get VNet IPs
    dns_service_ip    = "10.2.0.10"
    service_cidr      = "10.2.0.0/24"
    load_balancer_sku = "standard"
  }

  # Container Insights -> Log Analytics.
  dynamic "oms_agent" {
    for_each = var.enable_log_analytics ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
    }
  }

  # Key Vault -> Secrets Store CSI driver, with rotation.
  dynamic "key_vault_secrets_provider" {
    for_each = var.enable_key_vault_provider ? [1] : []
    content {
      secret_rotation_enabled  = true
      secret_rotation_interval = "2m"
    }
  }
}

# ---------------------------------------------------------------------------
# User node pool: autoscaled, workload-only (tainted so system pods stay out)
# ---------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_vm_size
  vnet_subnet_id        = azurerm_subnet.user.id
  mode                  = "User"

  enable_auto_scaling = true
  min_count           = var.user_node_min_count
  max_count           = var.user_node_max_count

  # Keep cluster-critical pods on the system pool.
  node_taints = ["workload=true:NoSchedule"]
  node_labels = {
    "pool" = "user"
  }

  upgrade_settings {
    drain_timeout_in_minutes      = 0
    node_soak_duration_in_minutes = 0
    max_surge                     = "10%"
  }

  tags = local.common_tags
}
