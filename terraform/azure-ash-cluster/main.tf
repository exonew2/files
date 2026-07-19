# azure-ash-cluster — Terraform for Azure AI Cluster
# Deploys: head node + N workers (Ollama) + vector DB (Qdrant)
# Uses low-priority VMSS for cost savings

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
}

locals {
  cluster_name  = "ash-cluster-${var.cluster_name_suffix}"
  location      = var.azure_location
  common_tags = {
    Project     = "ash-cluster"
    ManagedBy   = "terraform"
    Environment = var.environment
  }
}

# Resource group
resource "azurerm_resource_group" "cluster" {
  name     = "${local.cluster_name}-rg"
  location = local.location
  tags     = local.common_tags
}

# Virtual network
resource "azurerm_virtual_network" "cluster" {
  name                = "${local.cluster_name}-vnet"
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  address_space       = ["10.0.0.0/16"]
  tags                = local.common_tags
}

resource "azurerm_subnet" "cluster" {
  name                 = "${local.cluster_name}-subnet"
  resource_group_name  = azurerm_resource_group.cluster.name
  virtual_network_name = azurerm_virtual_network.cluster.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Public IP for head node
resource "azurerm_public_ip" "head" {
  count               = var.head_node_count
  name                = "${local.cluster_name}-head-pip-${count.index + 1}"
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Network security group
resource "azurerm_network_security_group" "cluster" {
  name                = "${local.cluster_name}-nsg"
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  tags                = local.common_tags

  security_rule {
    name                       = "Ollama"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "11434"
    source_address_prefixes    = var.allowed_ips
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Qdrant"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6333-6334"
    source_address_prefixes    = var.allowed_ips
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_ips
    destination_address_prefix = "*"
  }
}

# SSH key
resource "tls_private_key" "cluster" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_ssh_public_key" "cluster" {
  name                = "${local.cluster_name}-ssh-key"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = azurerm_resource_group.cluster.location
  public_key          = tls_private_key.cluster.public_key_openssh
  tags                = local.common_tags
}

# Head node NIC
resource "azurerm_network_interface" "head" {
  count               = var.head_node_count
  name                = "${local.cluster_name}-head-nic-${count.index + 1}"
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.cluster.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.head[count.index].id
  }
}

resource "azurerm_network_interface_security_group_association" "head" {
  count                     = var.head_node_count
  network_interface_id      = azurerm_network_interface.head[count.index].id
  network_security_group_id = azurerm_network_security_group.cluster.id
}

# Head node VM
resource "azurerm_linux_virtual_machine" "head" {
  count                           = var.head_node_count
  name                            = "${local.cluster_name}-head-${count.index + 1}"
  location                        = azurerm_resource_group.cluster.location
  resource_group_name             = azurerm_resource_group.cluster.name
  size                            = var.head_vm_size
  admin_username                  = "arch"
  disable_password_authentication = true
  tags                            = local.common_tags

  network_interface_ids = [azurerm_network_interface.head[count.index].id]

  admin_ssh_key {
    username   = "arch"
    public_key = azurerm_ssh_public_key.cluster.public_key
  }

  os_disk {
    name              = "${local.cluster_name}-head-osdisk-${count.index + 1}"
    caching           = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb      = var.head_disk_size
  }

  source_image_reference {
    publisher = "archlinux"
    offer     = "archlinux"
    sku       = "latest"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/user-data-head.sh", {
    cluster_name = local.cluster_name
  }))
}

# Worker nodes — low-priority VMSS
resource "azurerm_linux_virtual_machine_scale_set" "worker" {
  name                 = "${local.cluster_name}-worker-vmss"
  location             = azurerm_resource_group.cluster.location
  resource_group_name  = azurerm_resource_group.cluster.name
  sku                  = var.worker_vm_size
  instances            = var.worker_node_count
  admin_username       = "arch"
  tags                 = local.common_tags
  priority             = "Spot"
  eviction_policy      = "Deallocate"
  single_placement_group = false
  overprovision        = false
  upgrade_mode         = "Manual"

  admin_ssh_key {
    username   = "arch"
    public_key = azurerm_ssh_public_key.cluster.public_key
  }

  source_image_reference {
    publisher = "archlinux"
    offer     = "archlinux"
    sku       = "latest"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.worker_disk_size
  }

  network_interface {
    name    = "${local.cluster_name}-worker-nic"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.cluster.id
    }
  }

  custom_data = base64encode(templatefile("${path.module}/user-data-worker.sh", {
    node_type    = "ollama"
    cluster_name = local.cluster_name
  }))

  lifecycle {
    ignore_changes = [instances]
  }
}

# Vector DB node
resource "azurerm_network_interface" "vectordb" {
  count               = var.vectordb_node_count
  name                = "${local.cluster_name}-vectordb-nic-${count.index + 1}"
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.cluster.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vectordb" {
  count                           = var.vectordb_node_count
  name                            = "${local.cluster_name}-vectordb-${count.index + 1}"
  location                        = azurerm_resource_group.cluster.location
  resource_group_name             = azurerm_resource_group.cluster.name
  size                            = var.vectordb_vm_size
  admin_username                  = "arch"
  disable_password_authentication = true
  priority                        = "Spot"
  eviction_policy                 = "Deallocate"
  tags                            = local.common_tags

  network_interface_ids = [azurerm_network_interface.vectordb[count.index].id]

  admin_ssh_key {
    username   = "arch"
    public_key = azurerm_ssh_public_key.cluster.public_key
  }

  os_disk {
    name                 = "${local.cluster_name}-vectordb-osdisk-${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.vectordb_disk_size
  }

  source_image_reference {
    publisher = "archlinux"
    offer     = "archlinux"
    sku       = "latest"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/user-data-worker.sh", {
    node_type    = "qdrant"
    cluster_name = local.cluster_name
  }))
}

# Load balancer for Ollama
resource "azurerm_lb" "ollama" {
  name                = "${local.cluster_name}-lb"
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_lb_backend_address_pool" "ollama" {
  name            = "${local.cluster_name}-bepool"
  loadbalancer_id = azurerm_lb.ollama.id
}

resource "azurerm_lb_probe" "ollama" {
  name            = "ollama-health"
  loadbalancer_id = azurerm_lb.ollama.id
  port            = 11434
  protocol        = "Tcp"
}

resource "azurerm_lb_rule" "ollama" {
  name                           = "ollama-rule"
  loadbalancer_id                = azurerm_lb.ollama.id
  protocol                       = "Tcp"
  frontend_port                  = 11434
  backend_port                   = 11434
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ollama.id]
  probe_id                       = azurerm_lb_probe.ollama.id
}

# Outputs
output "head_node_public_ips" {
  value = azurerm_public_ip.head[*].ip_address
}

output "ollama_lb_endpoint" {
  value = "http://${azurerm_lb.ollama.private_ip_address}:11434"
}

output "ssh_private_key" {
  value     = tls_private_key.cluster.private_key_pem
  sensitive = true
}
