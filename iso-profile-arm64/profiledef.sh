#!/usr/bin/env bash
set -euo pipefail

iso_name="ash"
iso_label="ASH_$(date +%Y%m)"
iso_publisher="ash-linux <https://ash.sh>"
iso_application="ash — Arch Snapshot Hypervisor (ARM64)"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito'
           'uefi-ia32.grub.esp' 'uefi-x64.grub.esp'
           'uefi-ia32.grub.eltorito' 'uefi-x64.grub.eltorito'
           'uefi-aa64.grub.esp' 'uefi-aa64.grub.eltorito')
arch="aarch64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
