packer {
  required_plugins {
    googlecompute = { version = ">= 1.1", source = "github.com/hashicorp/googlecompute" }
  }
}

variable "version" { type = string, default = "dev" }
variable "gcp_project" { type = string, default = "" }

source "googlecompute" "ash-image" {
  project_id    = var.gcp_project
  source_image_family = "arch-linux"
  zone          = "us-central1-a"
  instance_name = "ash-${var.version}-builder"
  machine_type  = "n1-standard-4"
  disk_size     = "50"
  disk_type     = "pd-ssd"
  image_name    = "ash-${var.version}-{{timestamp}}"
  image_family  = "ash-linux"
  ssh_username  = "arch"
}

build {
  sources = ["source.googlecompute.ash-image"]

  provisioner "file" {
    source = "../iso-profile/packages.x86_64"
    destination = "/tmp/packages.x86_64"
  }

  provisioner "file" {
    source = "../iso-profile/airootfs/"
    destination = "/tmp/airootfs"
  }

  provisioner "shell" {
    inline = [
      "sudo pacman -Sy --noconfirm archlinux-keyring",
      "sudo pacman -S --noconfirm $(grep -v '^#' /tmp/packages.x86_64 | tr '\\n' ' ')",
      "sudo rsync -a /tmp/airootfs/ /",
      "sudo chown -R root:root /etc /usr",
      "sudo systemctl enable systemd-networkd systemd-resolved",
      "sudo systemctl enable sshd.socket firewalld",
      "sudo systemctl enable iso-firstboot.service iso-btrfs-maintenance.timer",
      "sudo systemctl enable iso-detect-gpu.service iso-gen-ssh-keys.service",
      "sudo systemctl enable iso-detect-timezone.service iso-detect-keyboard.service",
      "sudo systemctl enable iso-gen-hyprland-config.service",
      "sudo systemd-sysusers /usr/lib/sysusers.d/iso-aiuser.conf",
      "echo 'aiuser ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/iso-aiuser",
      "sudo systemctl enable cloud-init cloud-config cloud-final cloud-init-local",
      "sudo pacman -Scc --noconfirm",
      "sudo rm -f /etc/machine-id /var/lib/systemd/random-seed"
    ]
  }

  provisioner "file" {
    source = "cloud-init/"
    destination = "/tmp/cloud-init/"
  }

  provisioner "shell" {
    inline = [
      "sudo cp -r /tmp/cloud-init/* /etc/cloud/cloud.cfg.d/ 2>/dev/null || true",
      "printf '#cloud-config\\ndatasource_list: [GCE, ConfigDrive, NoCloud]\\ndatasource:\\n  GCE:\\n    timeout: 60\\n    max_wait: 120\\n' | sudo tee /etc/cloud/cloud.cfg.d/10_ash_datasource.cfg",
      "sudo cloud-init clean --logs"
    ]
  }

  post-processor "manifest" {
    output = "ash-${var.version}-gcp-manifest.json"
  }
}
