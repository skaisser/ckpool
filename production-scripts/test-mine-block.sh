#!/bin/bash

# Test Mining Script for CKPool Regtest
# This script simulates mining a block with a specific username
# to verify the coinbase message contains "EloPool/Mined by [username]/"

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
BITCOIN_CLI="bitcoin-cli -datadir=$HOME/.bitcoin-regtest -regtest"
USERNAME="${1:-testuser}"

echo "======================================"
echo "CKPool Coinbase Message Test"
echo "======================================"
echo

# Check if bitcoind is running
if ! $BITCOIN_CLI getblockchaininfo > /dev/null 2>&1; then
    echo -e "${RED}❌ Bitcoin regtest not running!${NC}"
    echo "Please run: ./test-ckpool-regtest.sh start"
    exit 1
fi

# Check if ckpool is running
if ! pgrep -x "ckpool" > /dev/null; then
    echo -e "${RED}❌ CKPool not running!${NC}"
    echo "Please run: ./test-ckpool-regtest.sh start"
    exit 1
fi

echo "🔍 Testing with username: $USERNAME"
echo

# Step 1: Submit a share as the specified user
echo "📤 Simulating mining activity for user: $USERNAME"
# Note: In a real test, you would connect a miner with this username
# For now, we'll just generate a block and check the result

# Step 2: Generate a block
echo "⛏️ Generating a test block..."
BLOCKHASH=$($BITCOIN_CLI -rpcwallet=regtestwallet generatetoaddress 1 $($BITCOIN_CLI -rpcwallet=regtestwallet getnewaddress) | jq -r '.[0]')
echo "Generated block: $BLOCKHASH"
echo

# Step 3: Get block details
echo "🔍 Analyzing block..."
BLOCK=$($BITCOIN_CLI getblock $BLOCKHASH 2)

# Extract coinbase transaction
COINBASE_HEX=$(echo "$BLOCK" | jq -r '.tx[0].vin[0].coinbase')
echo "Coinbase hex: $COINBASE_HEX"

# Convert hex to readable text
COINBASE_TEXT=$(echo "$COINBASE_HEX" | xxd -r -p | strings)
echo
echo "📝 Coinbase text:"
echo "$COINBASE_TEXT"
echo

# Check for EloPool signature
if echo "$COINBASE_TEXT" | grep -q "EloPool"; then
    echo -e "${GREEN}✅ Found EloPool signature in coinbase!${NC}"
    
    # Check if it includes the username (when mining through ckpool)
    if echo "$COINBASE_TEXT" | grep -q "Mined by $USERNAME"; then
        echo -e "${GREEN}✅ Found username '$USERNAME' in coinbase message!${NC}"
        echo -e "${GREEN}✅ Coinbase format verified: EloPool/Mined by $USERNAME/${NC}"
    else
        echo -e "${YELLOW}⚠️ Username not found in coinbase (expected when mining directly)${NC}"
        echo "Note: Username only appears when mining through ckpool stratum"
    fi
else
    echo -e "${RED}❌ EloPool signature NOT found in coinbase${NC}"
fi

echo
echo "💡 To test with actual mining:"
echo "  1. Connect a miner to stratum+tcp://localhost:3333"
echo "  2. Use username: $USERNAME.worker1"
echo "  3. Mine a block through the pool"
echo "  4. Check the coinbase with this script"
echo

# Display recent blocks
echo "📊 Recent blocks:"
RECENT_BLOCKS=$($BITCOIN_CLI getblockcount)
for i in {0..2}; do
    BLOCK_HEIGHT=$((RECENT_BLOCKS - i))
    if [ $BLOCK_HEIGHT -ge 0 ]; then
        HASH=$($BITCOIN_CLI getblockhash $BLOCK_HEIGHT)
        COINBASE_HEX=$($BITCOIN_CLI getblock $HASH 2 | jq -r '.tx[0].vin[0].coinbase')
        COINBASE_TEXT=$(echo "$COINBASE_HEX" | xxd -r -p | strings | tr '\n' ' ')
        echo "  Block $BLOCK_HEIGHT: $COINBASE_TEXT"
    fi
done