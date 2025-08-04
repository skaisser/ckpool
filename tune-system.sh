#!/bin/bash

# System tuning for CKPool with remote nodes

echo "Tuning system for CKPool with remote BCH nodes..."

# Increase network buffer sizes
echo "Setting network buffer sizes..."
sudo sysctl -w net.core.rmem_max=26214400
sudo sysctl -w net.core.wmem_max=26214400
sudo sysctl -w net.core.rmem_default=262144
sudo sysctl -w net.core.wmem_default=262144

# Make changes persistent
echo "Making changes persistent..."
sudo tee /etc/sysctl.d/90-ckpool.conf << EOF
# CKPool network optimizations
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# Additional optimizations for mining pool
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
EOF

# Apply sysctl settings
sudo sysctl -p /etc/sysctl.d/90-ckpool.conf

echo "System tuning complete!"
echo "The rcvbufsiz warning should now be resolved."