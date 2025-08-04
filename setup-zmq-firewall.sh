#!/bin/bash

# Setup firewall rules for ZMQ block notifications

echo "Setting up firewall rules for CKPool ZMQ..."

# Check current UFW status
echo "Current firewall status:"
sudo ufw status numbered

echo
echo "Adding ZMQ rules..."

# On the BCH nodes (where ZMQ publishes from)
echo "On BCH nodes, allow incoming ZMQ connections:"
echo "sudo ufw allow 28333/tcp comment 'ZMQ block notifications'"

# If you want to restrict to specific IPs (more secure)
echo
echo "For more security, limit to specific pool servers:"
echo "sudo ufw allow from 10.0.1.0/24 to any port 28333 comment 'ZMQ from pool servers'"

# On the pool server (where CKPool runs)
echo
echo "On the pool server, ensure outgoing connections are allowed:"
echo "sudo ufw allow out 28333/tcp comment 'ZMQ to BCH nodes'"

# Also ensure RPC ports are open
echo
echo "Also ensure RPC ports are open between servers:"
echo "sudo ufw allow from 10.0.1.0/24 to any port 8332 comment 'BCH RPC'"

# Test connectivity
echo
echo "To test ZMQ connectivity from pool server to BCH nodes:"
echo "nc -zv 10.0.1.238 28333"
echo "nc -zv 10.0.1.237 28333"  # Adjust IP for your second node

echo
echo "To apply rules on BCH nodes:"
echo "1. SSH to each BCH node"
echo "2. Run: sudo ufw allow 28333/tcp"
echo "3. Or for specific IPs: sudo ufw allow from POOL_SERVER_IP to any port 28333"
echo
echo "To check if ZMQ is listening on BCH nodes:"
echo "netstat -tlnp | grep 28333"
echo "or"
echo "ss -tlnp | grep 28333"