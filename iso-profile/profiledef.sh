#!/usr/bin/env bash
# profiledef.sh — mkarchiso profile definition
set -euo pipefail

iso_name="ash"
iso_label="ASH_$(date +%Y%m)"
iso_publisher="ash-linux <https://ash.sh>"
iso_application="ash — Arch Snapshot Hypervisor"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito'
           'uefi-ia32.grub.esp' 'uefi-x64.grub.esp'
           'uefi-ia32.grub.eltorito' 'uefi-x64.grub.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '22' '-b' '512K')
