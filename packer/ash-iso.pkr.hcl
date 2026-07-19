packer {
  required_plugins {
    vmware = { version = ">= 1.0", source = "github.com/hashicorp/vmware" }
    virtualbox = { version = ">= 1.0", source = "github.com/hashicorp/virtualbox" }
    parallels = { version = ">= 1.0", source = "github.com/hashicorp/parallels" }
    qemu = { version = ">= 1.0", source = "github.com/hashicorp/qemu" }
  }
}

variable "version" { type = string, default = "dev" }
variable "iso_path" { type = string }

source "qemu" "ash-iso" {
  iso_url        = "file://${var.iso_path}"
  iso_checksum   = "file:${var.iso_path}.sha256"
  output_dir     = "output-qemu"
  vm_name        = "ash-${var.version}"
  format         = "qcow2"
  disk_size      = "50G"
  accelerator    = "kvm"
  boot_wait      = "10s"
  shutdown_command = "echo 'aiuser' | sudo -S systemctl poweroff"
  
  ssh_username = "aiuser"
  ssh_password = "aiuser"
  ssh_timeout  = "30m"
  
  qemuargs = [
    ["-m", "4G"], ["-smp", "4"], ["-cpu", "host"],
    ["-device", "virtio-net-pci,netdev=net0"],
    ["-netdev", "user,id=net0,hostfwd=tcp::2222-:22"],
    ["-device", "virtio-gpu-pci"],
    ["-display", "gtk"]
  ]
}

build {
  sources = ["source.qemu.ash-iso"]
  
  post-processor "shell-local" {
    inline = [
      "qemu-img convert -f qcow2 -O qcow2 output-qemu/ash-${var.version}.qcow2 ash-${var.version}.qcow2",
      "qemu-img convert -f qcow2 -O vmdk output-qemu/ash-${var.version}.qcow2 ash-${var.version}.vmdk",
      "qemu-img convert -f qcow2 -O vhdx output-qemu/ash-${var.version}.qcow2 ash-${var.version}.vhdx",
      "qemu-img convert -f qcow2 -O raw output-qemu/ash-${var.version}.qcow2 ash-${var.version}.img",
      "gzip -c ash-${var.version}.img > ash-${var.version}.img.gz"
    ]
  }
  
  post-processor "vmware" {
    version = "14"
    keep_input_artifact = false
    output = "ash-${var.version}.ova"
  }
  
  post-processor "virtualbox" {
    output = "ash-${var.version}-virtualbox.ova"
    keep_input_artifact = false
  }
  
  post-processor "parallels" {
    output = "ash-${var.version}.pvm"
    keep_input_artifact = false
  }
  
  post-processor "manifest" {
    output = "ash-${var.version}-manifest.json"
    strip_path = true
  }
}