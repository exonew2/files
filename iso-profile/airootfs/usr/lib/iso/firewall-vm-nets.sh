#!/usr/bin/env bash
# /usr/lib/iso/firewall-vm-nets.sh — Update nftables VM network set

set -euo pipefail

nft add set inet filter vm_networks { type ipv4_addr\; flags interval\; } 2>/dev/null || true

# Common VM subnets
nft add element inet filter vm_networks { 10.0.2.0/24, 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8 } 2>/dev/null || true

# Detect libvirt/virtualbox interfaces
for iface in $(ip -br link show | awk '/^(virbr|vboxnet|vmnet|veth)/ {print $1}'); do
    for cidr in $(ip -4 addr show dev "$iface" | awk '/inet / {print $2}'); do
        nft add element inet filter vm_networks { $cidr } 2>/dev/null || true
    done
done