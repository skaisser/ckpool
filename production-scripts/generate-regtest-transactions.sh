#!/bin/bash

# Generate fake transactions on regtest network
# This creates a more realistic mining environment with transaction fees

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
BITCOIN_CLI="bitcoin-cli -datadir=$HOME/.bitcoin-regtest -regtest"
NUM_TXS="${1:-100}"

echo "======================================"
echo "Generating Regtest Transactions"
echo "======================================"
echo

# Check if bitcoind is running
if ! $BITCOIN_CLI getblockchaininfo > /dev/null 2>&1; then
    echo -e "${RED}❌ Bitcoin regtest not running!${NC}"
    echo "Please run: ./test-ckpool-regtest.sh start"
    exit 1
fi

echo "🔍 Current mempool info:"
MEMPOOL_INFO=$($BITCOIN_CLI getmempoolinfo)
echo "$MEMPOOL_INFO" | jq .
echo

# Get current balance
BALANCE=$($BITCOIN_CLI -rpcwallet=regtestwallet getbalance)
echo "💰 Wallet balance: $BALANCE BCH"

# Generate some addresses
echo
echo "🏠 Generating addresses..."
ADDRESSES=()
for i in {1..10}; do
    ADDR=$($BITCOIN_CLI -rpcwallet=regtestwallet getnewaddress)
    ADDRESSES+=($ADDR)
done
echo "Generated ${#ADDRESSES[@]} addresses"

# Create transactions
echo
echo "📤 Creating $NUM_TXS transactions..."
echo

TX_COUNT=0
FAILED_COUNT=0

for ((i=1; i<=NUM_TXS; i++)); do
    # Random address from our list
    RANDOM_INDEX=$((RANDOM % ${#ADDRESSES[@]}))
    TO_ADDR=${ADDRESSES[$RANDOM_INDEX]}
    
    # Random amount between 0.001 and 0.1 BCH
    AMOUNT=$(awk -v min=0.001 -v max=0.1 'BEGIN{srand(); print min+rand()*(max-min)}')
    AMOUNT=$(printf "%.8f" $AMOUNT)
    
    # Try to send transaction
    if TXID=$($BITCOIN_CLI -rpcwallet=regtestwallet sendtoaddress "$TO_ADDR" "$AMOUNT" 2>/dev/null); then
        echo -e "${GREEN}✓${NC} TX $i: Sent $AMOUNT BCH to ${TO_ADDR:0:20}... (${TXID:0:16}...)"
        ((TX_COUNT++))
        
        # Every 10 transactions, show progress
        if [ $((i % 10)) -eq 0 ]; then
            MEMPOOL_SIZE=$($BITCOIN_CLI getmempoolinfo | jq -r .size)
            echo "   📊 Mempool size: $MEMPOOL_SIZE transactions"
        fi
    else
        ((FAILED_COUNT++))
        if [ $FAILED_COUNT -lt 5 ]; then
            echo -e "${YELLOW}⚠${NC} TX $i: Failed (probably insufficient funds)"
        fi
    fi
    
    # Small delay to avoid overwhelming
    if [ $((i % 20)) -eq 0 ]; then
        sleep 0.1
    fi
done

echo
echo "======================================"
echo "Transaction Generation Complete"
echo "======================================"
echo

# Final mempool info
FINAL_MEMPOOL=$($BITCOIN_CLI getmempoolinfo)
MEMPOOL_SIZE=$(echo "$FINAL_MEMPOOL" | jq -r .size)
MEMPOOL_BYTES=$(echo "$FINAL_MEMPOOL" | jq -r .bytes)
MEMPOOL_FEES=$(echo "$FINAL_MEMPOOL" | jq -r .mempoolminfee)

echo "📊 Final mempool statistics:"
echo "  - Transactions: $MEMPOOL_SIZE"
echo "  - Size: $MEMPOOL_BYTES bytes"
echo "  - Total created: $TX_COUNT transactions"
echo

if [ $MEMPOOL_SIZE -gt 0 ]; then
    echo -e "${GREEN}✅ Success!${NC} The mempool now has $MEMPOOL_SIZE transactions waiting to be mined."
    echo
    echo "💡 When you mine the next block through CKPool, it will include these transactions!"
    echo "   This makes the test more realistic and generates transaction fees for the pool."
else
    echo -e "${YELLOW}⚠️ Warning:${NC} No transactions in mempool. They may have been mined already."
fi

# Show next steps
echo
echo "🎯 Next steps:"
echo "  1. Start mining: cpuminer -a sha256d -o stratum+tcp://localhost:3333 -u skaisser.worker1 -p x"
echo "  2. Check mempool: $BITCOIN_CLI getrawmempool"
echo "  3. After mining a block: ./test-mine-block.sh skaisser"