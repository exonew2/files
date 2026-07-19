variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone"
  type        = string
  default     = "a"
}

variable "cluster_name_suffix" {
  description = "Suffix for cluster naming"
  type        = string
  default     = "dev"
}

variable "environment" {
  description = "Environment label"
  type        = string
  default     = "dev"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
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

variable "head_machine_type" {
  description = "Head node machine type"
  type        = string
  default     = "e2-medium"
}

variable "worker_machine_type" {
  description = "Worker node machine type"
  type        = string
  default     = "g2-standard-4"
}

variable "vectordb_machine_type" {
  description = "Vector DB machine type"
  type        = string
  default     = "e2-standard-2"
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
