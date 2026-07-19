packer {
  required_plugins {
    azure = { version = ">= 2.0", source = "github.com/hashicorp/azure" }
  }
}

variable "version" { type = string, default = "dev" }
variable "azure_client_id" { type = string, default = "" }
variable "azure_client_secret" { type = string, default = "" }
variable "azure_tenant_id" { type = string, default = "" }
variable "azure_subscription_id" { type = string, default = "" }

source "azure-arm" "ash-image" {
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
  subscription_id = var.azure_subscription_id

  location        = "East US"
  vm_size         = "Standard_D4s_v3"
  os_type         = "Linux"
  image_publisher = "ArchLinux"
  image_offer     = "ArchLinux"
  image_sku       = "latest"

  managed_image_name              = "ash-${var.version}"
  managed_image_resource_group_name = "ash-images"
  storage_account                = "ashimages${var.version}"

  ssh_username = "arch"
}

build {
  sources = ["source.azure-arm.ash-image"]

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
      "printf '#cloud-config\\ndatasource_list: [Azure, ConfigDrive, NoCloud]\\ndatasource:\\n  Azure:\\n    timeout: 60\\n    max_wait: 120\\n' | sudo tee /etc/cloud/cloud.cfg.d/10_ash_datasource.cfg",
      "sudo cloud-init clean --logs"
    ]
  }

  post-processor "manifest" {
    output = "ash-${var.version}-azure-manifest.json"
  }
}
