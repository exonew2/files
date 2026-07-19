packer {
  required_plugins {
    amazon = { version = ">= 1.3", source = "github.com/hashicorp/amazon" }
  }
}

variable "version" { type = string, default = "dev" }
variable "iso_path" { type = string, default = "" }

source "amazon-ebs" "ash-ami" {
  ami_name      = "ash-${var.version}-{{timestamp}}"
  region        = "us-east-1"
  source_ami_filter {
    filters = { name = "arch-linux-*-x86_64" }
    most_recent = true
    owners = ["137112412989"]
  }
  instance_type = "t3.medium"
  ssh_username  = "arch"

  ami_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 50
    volume_type = "gp3"
    delete_on_termination = true
  }

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 50
  }
}

build {
  sources = ["source.amazon-ebs.ash-ami"]

  # Copy ash packages list and airootfs
  provisioner "file" {
    source = "../iso-profile/packages.x86_64"
    destination = "/tmp/packages.x86_64"
  }

  provisioner "file" {
    source = "../iso-profile/airootfs/"
    destination = "/tmp/airootfs"
  }

  # Install full ash environment
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
      "sudo mkdir -p /etc/gdm",
      "printf '[daemon]\\nAutomaticLoginEnable=True\\nAutomaticLogin=aiuser\\n' | sudo tee /etc/gdm/custom.conf",
      "sudo systemctl enable cloud-init cloud-config cloud-final cloud-init-local",
      "sudo pacman -Scc --noconfirm",
      "sudo rm -f /etc/machine-id /var/lib/systemd/random-seed"
    ]
  }

  # Cloud-init datasource
  provisioner "file" {
    source = "cloud-init/"
    destination = "/tmp/cloud-init/"
  }

  provisioner "shell" {
    inline = [
      "sudo cp -r /tmp/cloud-init/* /etc/cloud/cloud.cfg.d/ 2>/dev/null || true",
      "printf '#cloud-config\\ndatasource_list: [Ec2, ConfigDrive, NoCloud]\\ndatasource:\\n  Ec2:\\n    metadata_urls: [\"http://169.254.169.254\"]\\n    timeout: 60\\n    max_wait: 120\\n' | sudo tee /etc/cloud/cloud.cfg.d/10_ash_datasource.cfg",
      "sudo cloud-init clean --logs"
    ]
  }

  post-processor "manifest" {
    output = "ash-${var.version}-ami-manifest.json"
  }
}
