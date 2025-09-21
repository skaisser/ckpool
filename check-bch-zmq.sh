#!/bin/bash

# Try to find ckpool.conf in common locations
CONF_FILE=""
if [ -f ~/ckpool/ckpool.conf ]; then
    CONF_FILE=~/ckpool/ckpool.conf
elif [ -f ./ckpool.conf ]; then
    CONF_FILE=./ckpool.conf
elif [ -f /etc/ckpool.conf ]; then
    CONF_FILE=/etc/ckpool.conf
fi

if [ -z "$CONF_FILE" ]; then
    echo "Error: Could not find ckpool.conf"
    echo "Please specify the path to ckpool.conf as an argument:"
    echo "  $0 /path/to/ckpool.conf"
    exit 1
fi

if [ ! -z "$1" ]; then
    CONF_FILE="$1"
fi

echo "Reading configuration from: $CONF_FILE"
echo "======================================="
echo

# Extract BCH node IPs and ZMQ ports from config
# Using jq if available, otherwise fall back to sed/awk
if command -v jq &> /dev/null; then
    NODES=$(jq -r '.btcd[]? | "\(.url | split(":")[0]):\(.zmqnotify | split(":")[2] | split("/")[2])"' "$CONF_FILE" 2>/dev/null)
else
    # Fallback to sed/awk parsing
    NODES=$(sed -n '/btcd.*\[/,/\]/p' "$CONF_FILE" | grep -E '"url"|"zmqnotify"' | paste -d' ' - - | sed 's/.*"url"[^"]*"//;s/".*"zmqnotify"[^/]*\/\///;s/".*//' | awk -F: '{print $1":"$4}')
fi

if [ -z "$NODES" ]; then
    echo "Warning: Could not parse BCH nodes from config file"
    echo "Falling back to manual check..."
    echo
    echo "Run this on your BCH node"
    echo "========================="
else
    echo "Found BCH nodes in config:"
    echo "$NODES"
    echo
    echo "Checking each node..."
    echo "====================="

    for NODE in $NODES; do
        IP=$(echo $NODE | cut -d: -f1)
        PORT=$(echo $NODE | cut -d: -f2)

        echo
        echo "Checking node: $IP (ZMQ port: $PORT)"
        echo "-----------------------------------"

        # Test connectivity to RPC port
        echo -n "Testing RPC connectivity (port 8332)... "
        if timeout 2 bash -c "echo >/dev/tcp/$IP/8332" 2>/dev/null; then
            echo "✓ OK"
        else
            echo "✗ FAILED"
        fi

        # Test connectivity to ZMQ port
        echo -n "Testing ZMQ connectivity (port $PORT)... "
        if timeout 2 bash -c "echo >/dev/tcp/$IP/$PORT" 2>/dev/null; then
            echo "✓ OK"
        else
            echo "✗ FAILED - ZMQ may not be enabled on $IP"
        fi

        # If we have SSH access, we can run remote checks
        echo
        echo "For detailed checks, SSH to $IP and run:"
        echo "  grep -i zmq ~/.bitcoin/bitcoin.conf"
        echo "  bitcoin-cli getzmqnotifications"
        echo "  ss -tln | grep $PORT"
    done
fi

echo
echo "======================================="
echo "Manual checks on BCH node(s):"
echo "======================================="
echo

echo "1. Check if ZMQ is enabled in bitcoin.conf:"
echo "   grep -i zmq ~/.bitcoin/bitcoin.conf"

echo
echo "2. Check if bitcoind is listening on ZMQ port:"
echo "   sudo netstat -tlnp | grep 28333"
echo "   or: ss -tln | grep 28333"

echo
echo "3. Check bitcoind ZMQ settings:"
echo "   bitcoin-cli getzmqnotifications"

echo
echo "4. Check firewall rules:"
echo "   sudo ufw status | grep -E '28333|8332'"

echo
echo "5. Check recent bitcoind logs for ZMQ:"
echo "   tail -100 ~/.bitcoin/debug.log | grep -i zmq | tail -10"

echo
echo "If ZMQ is not enabled, add to bitcoin.conf:"
echo "   zmqpubhashblock=tcp://0.0.0.0:28333"
echo "Then restart bitcoind"