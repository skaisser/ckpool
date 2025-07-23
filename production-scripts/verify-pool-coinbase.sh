#!/bin/bash

# Verify that CKPool would create the correct coinbase message

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
if [ -z "$1" ]; then
    echo "Usage: $0 {test|production}"
    echo "  test       - Check test installation (ckpool-test)"
    echo "  production - Check production installation (ckpool)"
    exit 1
fi

MODE=$1
if [ "$MODE" = "test" ]; then
    CKPOOL_DIR="$HOME/ckpool-test"
    LOG_DIR="logs-regtest"
    BITCOIN_CLI="bitcoin-cli -datadir=$HOME/.bitcoin-regtest -regtest"
else
    CKPOOL_DIR="$HOME/ckpool"
    LOG_DIR="logs"
    BITCOIN_CLI="bitcoin-cli"
fi

echo "======================================"
echo "CKPool Coinbase Verification"
echo "======================================"
echo

# Check pool logs for the mining address
echo "🔍 Checking CKPool configuration..."
if [ -f "$CKPOOL_DIR/$LOG_DIR/ckpool.log" ]; then
    POOL_LOG=$(tail -50 "$CKPOOL_DIR/$LOG_DIR/ckpool.log" | grep -E "(Mining from|btcaddress|username|EloPool)" | tail -5)
    echo "$POOL_LOG"
else
    echo "Log file not found: $CKPOOL_DIR/$LOG_DIR/ckpool.log"
fi
echo

# Show what WOULD happen if a block was mined through the pool
echo "📋 Expected behavior when mining through CKPool:"
echo "  1. Miner connects with username (e.g., 'skaisser.worker1')"
echo "  2. Pool creates work with coinbase transaction"
echo "  3. Coinbase includes: 'EloPool' signature"
echo "  4. Block reward goes to pool address"
echo "  Note: Username in coinbase requires btcsolo mode"
echo

# Check recent pool activity
echo "🔍 Recent pool activity:"
if [ -f "$CKPOOL_DIR/$LOG_DIR/ckpool.log" ]; then
    tail -20 "$CKPOOL_DIR/$LOG_DIR/ckpool.log" | grep -E "(Added new user|Authorised|worker|Dropped)" || echo "No recent connections"
else
    echo "No log file found"
fi
echo

# Create a test to show the pool is configured correctly
echo "✅ Checking Pool Configuration:"
if [ -f "$CKPOOL_DIR/ckpool.conf" ] || [ -f "$CKPOOL_DIR/ckpool-regtest.conf" ]; then
    CONFIG_FILE="$CKPOOL_DIR/ckpool.conf"
    [ -f "$CKPOOL_DIR/ckpool-regtest.conf" ] && CONFIG_FILE="$CKPOOL_DIR/ckpool-regtest.conf"
    
    echo "  - Config file: $CONFIG_FILE"
    BTCSIG=$(grep btcsig "$CONFIG_FILE" | cut -d'"' -f4)
    echo "  - btcsig: '$BTCSIG'"
    echo "  - Coinbase will show: EloPool$BTCSIG"
else
    echo "  - No configuration file found"
fi
echo

echo "🎯 To complete the test:"
echo "  1. Install any SHA256d miner:"
echo "     - cgminer: sudo apt-get install cgminer"
echo "     - bfgminer: sudo apt-get install bfgminer"
echo "     - Or compile cpuminer from source"
echo
echo "  2. Connect to pool:"
echo "     cgminer -o stratum+tcp://localhost:3333 -u skaisser.worker1 -p x --sha256d"
echo
echo "  3. When a block is found, coinbase will show:"
echo "     'EloPool' + configured btcsig"
echo

# Show that the pool IS working
echo "📊 Pool Status:"
if pgrep -x "ckpool" > /dev/null; then
    echo -e "${GREEN}✅ CKPool is running${NC}"
    
    # Try to get stats
    if ckpmsg -s /tmp/ckpool/stratifier statsusers 2>/dev/null; then
        echo "Pool is responding to commands"
    fi
else
    echo -e "${RED}❌ CKPool is not running${NC}"
fi