packer {
  required_plugins {
    vagrant = { version = ">= 1.1", source = "github.com/hashicorp/vagrant" }
    qemu = { version = ">= 1.0", source = "github.com/hashicorp/qemu" }
  }
}

variable "version" { type = string, default = "dev" }
variable "iso_path" { type = string }

source "qemu" "ash-vagrant" {
  iso_url             = "file://${var.iso_path}"
  iso_checksum        = "file:${var.iso_path}.sha256"
  output_dir          = "output-vagrant"
  vm_name             = "ash-${var.version}"
  format              = "qcow2"
  disk_size           = "50G"
  accelerator         = "kvm"
  boot_wait           = "15s"
  shutdown_command    = "echo 'aiuser' | sudo -S systemctl poweroff"

  ssh_username        = "aiuser"
  ssh_password        = "aiuser"
  ssh_timeout         = "45m"
  ssh_handshake_attempts = 100
  ssh_clear_authorized_keys = true

  qemuargs = [
    ["-m", "4G"],
    ["-smp", "4"],
    ["-cpu", "host"],
    ["-device", "virtio-net-pci,netdev=net0"],
    ["-netdev", "user,id=net0,hostfwd=tcp::2222-:22"],
    ["-device", "virtio-gpu-pci"],
    ["-display", "none"]
  ]
}

build {
  sources = ["source.qemu.ash-vagrant"]

  # Wait for system to be ready
  provisioner "shell" {
    inline = [
      "while ! systemctl is-active --quiet graphical.target; do sleep 5; done",
      "echo 'System ready for provisioning'"
    ]
  }

  # Remove Packer SSH key and disable password auth
  provisioner "shell" {
    inline = [
      "sudo touch /etc/iso-packer-done",
      "sudo systemctl start iso-packer-auth.service",
      "sudo rm -f /home/aiuser/.ssh/authorized_keys",
      "sudo rm -f /root/.ssh/authorized_keys",
      "echo 'Packer provisioning complete, SSH locked down'"
    ]
  }

  # Clean up for Vagrant packaging
  provisioner "shell" {
    inline = [
      "sudo pacman -Scc --noconfirm 2>/dev/null || true",
      "sudo rm -rf /var/cache/pacman/pkg/*",
      "sudo rm -rf /tmp/*",
      "sudo rm -f /etc/machine-id",
      "sudo rm -f /var/lib/systemd/random-seed",
      "sudo journalctl --vacuum-time=1d 2>/dev/null || true",
      "sudo cloud-init clean --logs 2>/dev/null || true",
      "history -c 2>/dev/null || true"
    ]
  }

  # Configure for Vagrant user
  provisioner "shell" {
    inline = [
      "sudo useradd -m -G wheel,docker,kvm,libvirt -s /bin/bash vagrant 2>/dev/null || true",
      "echo 'vagrant:vagrant' | sudo chpasswd",
      "echo 'vagrant ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/vagrant",
      "sudo mkdir -p /home/vagrant/.ssh",
      "sudo curl -fsSL https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub -o /home/vagrant/.ssh/authorized_keys 2>/dev/null || echo 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8oxlvZ0cGwF6JSTTTOMaHFGpUcSe7R8Jx3QX1WGRsVK1PI/8Gp8CJ3K8T4pQu2vSqGJkJ5o+pvLpWz0pRQy6gF3GHL2vJK+6J6oQs5vVJaFhV+5gQjLJWJqOrJhYoCkF6xRfJ0K93gYNnVJywrYUGqQeF6EVxY= vagrant insecure public key' > /home/vagrant/.ssh/authorized_keys",
      "sudo chmod 700 /home/vagrant/.ssh",
      "sudo chmod 600 /home/vagrant/.ssh/authorized_keys",
      "sudo chown -R vagrant:vagrant /home/vagrant/.ssh"
    ]
  }

  post-processor "vagrant" {
    compression_level = 9
    output = "ash-${var.version}-{{.Provider}}.box"
    vagrantfile_template = <<-VAGRANTFILE
      Vagrant.configure("2") do |config|
        config.vm.box_check_update = true
        config.vm.synced_folder ".", "/vagrant", disabled: false

        config.vm.provider "libvirt" do |lv|
          lv.memory = 4096
          lv.cpus = 4
          lv.video_type = "virtio"
          lv.graphics_type = "none"
        end

        config.vm.provider "virtualbox" do |vb|
          vb.memory = 4096
          vb.cpus = 4
          vb.gui = false
          vb.customize ["modifyvm", :id, "--vram", "128"]
          vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]
        end
      end
    VAGRANTFILE
  }

  post-processor "shell-local" {
    inline = [
      "echo 'Vagrant box built: ash-${var.version}-libvirt.box / ash-${var.version}-virtualbox.box'"
    ]
  }
}
