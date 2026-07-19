variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
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

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to access the cluster"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "head_node_count" {
  description = "Number of head/API gateway nodes"
  type        = number
  default     = 1
}

variable "worker_node_count" {
  description = "Number of Ollama worker nodes"
  type        = number
  default     = 3
}

variable "vectordb_node_count" {
  description = "Number of Qdrant vector DB nodes"
  type        = number
  default     = 1
}

variable "head_instance_type" {
  description = "Head node instance type"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "Worker node instance type"
  type        = string
  default     = "g4dn.xlarge"
}

variable "vectordb_instance_type" {
  description = "Vector DB instance type"
  type        = string
  default     = "t3.large"
}

variable "head_volume_size" {
  description = "Head node root volume size (GB)"
  type        = number
  default     = 30
}

variable "worker_volume_size" {
  description = "Worker node root volume size (GB)"
  type        = number
  default     = 100
}

variable "vectordb_volume_size" {
  description = "Vector DB root volume size (GB)"
  type        = number
  default     = 200
}

variable "worker_spot_max_price" {
  description = "Maximum spot price for worker instances"
  type        = string
  default     = "0.50"
}
