variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "azure_tenant_id" {
  description = "Azure tenant ID"
  type        = string
  sensitive   = true
}

variable "azure_location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "cluster_name_suffix" {
  description = "Suffix for cluster naming"
  type        = string
  default     = "dev"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "dev"
}

variable "allowed_ips" {
  description = "IPs allowed to access the cluster"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "head_node_count" {
  description = "Number of head nodes"
  type        = number
  default     = 1
}

variable "worker_node_count" {
  description = "Number of Ollama workers"
  type        = number
  default     = 3
}

variable "vectordb_node_count" {
  description = "Number of Qdrant nodes"
  type        = number
  default     = 1
}

variable "head_vm_size" {
  description = "Head node VM size"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "worker_vm_size" {
  description = "Worker node VM size"
  type        = string
  default     = "Standard_NC6s_v3"
}

variable "vectordb_vm_size" {
  description = "Vector DB VM size"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "head_disk_size" {
  description = "Head node disk size (GB)"
  type        = number
  default     = 30
}

variable "worker_disk_size" {
  description = "Worker node disk size (GB)"
  type        = number
  default     = 100
}

variable "vectordb_disk_size" {
  description = "Vector DB disk size (GB)"
  type        = number
  default     = 200
}
