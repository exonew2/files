# gcp-ash-cluster — Terraform for GCP AI Cluster
# Deploys: head node + N workers (Ollama) + vector DB (Qdrant)
# Uses preemptible instances for cost savings

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

locals {
  cluster_name = "ash-cluster-${var.cluster_name_suffix}"
  common_labels = {
    project     = "ash-cluster"
    managed-by  = "terraform"
    environment = var.environment
  }
}

# VPC
resource "google_compute_network" "cluster" {
  name                    = "${local.cluster_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "cluster" {
  name          = "${local.cluster_name}-subnet"
  network       = google_compute_network.cluster.id
  region        = var.gcp_region
  ip_cidr_range = "10.0.0.0/16"

  private_ip_google_access = true
}

# Firewall rules
resource "google_compute_firewall" "cluster" {
  name    = "${local.cluster_name}-fw"
  network = google_compute_network.cluster.name

  allow {
    protocol = "tcp"
    ports    = ["22", "11434", "6333", "6334", "80", "8300-8600"]
  }

  source_ranges = var.allowed_ips
  target_tags   = ["ash-cluster"]
}

# Head node
resource "google_compute_instance" "head" {
  count        = var.head_node_count
  name         = "${local.cluster_name}-head-${count.index + 1}"
  machine_type = var.head_machine_type
  zone         = "${var.gcp_region}-${var.gcp_zone}"

  tags = ["ash-cluster", "ash-head"]

  boot_disk {
    initialize_params {
      image = "projects/arch-linux/global/images/family/arch"
      size  = var.head_disk_size
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = google_compute_network.cluster.name
    subnetwork = google_compute_subnetwork.cluster.name
    access_config {}
  }

  metadata = {
    ssh-keys           = "arch:${file(var.ssh_public_key_path)}"
    startup-script     = file("${path.module}/startup-head.sh")
    ash-cluster-name   = local.cluster_name
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible       = false
    automatic_restart = true
  }

  labels = local.common_labels
}

# Worker nodes (Ollama) — preemptible
resource "google_compute_instance" "worker" {
  count        = var.worker_node_count
  name         = "${local.cluster_name}-worker-${count.index + 1}"
  machine_type = var.worker_machine_type
  zone         = "${var.gcp_region}-${var.gcp_zone}"

  tags = ["ash-cluster", "ash-worker"]

  boot_disk {
    initialize_params {
      image = "projects/arch-linux/global/images/family/arch"
      size  = var.worker_disk_size
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.cluster.name
    subnetwork = google_compute_subnetwork.cluster.name
  }

  metadata = {
    ssh-keys           = "arch:${file(var.ssh_public_key_path)}"
    startup-script     = templatefile("${path.module}/startup-worker.sh", { node_type = "ollama" })
    ash-cluster-name   = local.cluster_name
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible       = true
    automatic_restart = false
  }

  labels = local.common_labels
}

# Vector DB node (Qdrant)
resource "google_compute_instance" "vectordb" {
  count        = var.vectordb_node_count
  name         = "${local.cluster_name}-vectordb-${count.index + 1}"
  machine_type = var.vectordb_machine_type
  zone         = "${var.gcp_region}-${var.gcp_zone}"

  tags = ["ash-cluster", "ash-vectordb"]

  boot_disk {
    initialize_params {
      image = "projects/arch-linux/global/images/family/arch"
      size  = var.vectordb_disk_size
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = google_compute_network.cluster.name
    subnetwork = google_compute_subnetwork.cluster.name
  }

  metadata = {
    ssh-keys           = "arch:${file(var.ssh_public_key_path)}"
    startup-script     = templatefile("${path.module}/startup-worker.sh", { node_type = "qdrant" })
    ash-cluster-name   = local.cluster_name
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible       = true
    automatic_restart = false
  }

  labels = local.common_labels
}

# Outputs
output "head_node_external_ips" {
  value = google_compute_instance.head[*].network_interface[*].access_config[*].nat_ip
}

output "ollama_endpoint" {
  value = "http://${google_compute_instance.head[0].network_interface[0].access_config[0].nat_ip}:11434"
}

output "cluster_name" {
  value = local.cluster_name
}
