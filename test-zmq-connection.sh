#!/bin/bash

echo "Testing ZMQ connection to BCH node..."
echo

# Test basic connectivity
echo "1. Testing TCP connectivity to 10.0.1.238:28333..."
nc -zv 10.0.1.238 28333

echo
echo "2. Checking if ckpool is detecting ZMQ endpoints..."
grep -i "zmq" ~/ckpool/logs/ckpool.log | tail -20

echo
echo "3. Checking for block notifications..."
grep -i "block hash changed\|zmq block" ~/ckpool/logs/ckpool.log | tail -10

echo
echo "4. Testing ZMQ subscription with Python (if available)..."
if command -v python3 &> /dev/null; then
    python3 << 'EOF'
import socket
import time

try:
    # Simple TCP connection test
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    result = s.connect_ex(('10.0.1.238', 28333))
    if result == 0:
        print("✓ Port 28333 is open on 10.0.1.238")
    else:
        print("✗ Cannot connect to 10.0.1.238:28333")
    s.close()
except Exception as e:
    print(f"Error: {e}")
EOF
else
    echo "Python3 not installed, skipping Python test"
fi

echo
echo "5. Checking ckpool process for ZMQ thread..."
ps aux | grep -E "ckpool|zmq" | grep -v grep

echo
echo "6. Recent ckpool logs..."
tail -30 ~/ckpool/logs/ckpool.log | grep -E "ZMQ|zmq|block hash changed|Network diff"