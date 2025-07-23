#!/bin/bash

# Unified CKPool Regtest Testing Script
# This script safely sets up a regtest environment without affecting production

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "======================================"
echo "CKPool Regtest Testing Environment"
echo "======================================"
echo

# Configuration
REGTEST_DIR="$HOME/.bitcoin-regtest"
CKPOOL_DIR="$HOME/ckpool"
BITCOIN_CLI="bitcoin-cli -datadir=$REGTEST_DIR -regtest"
BITCOIND="bitcoind -datadir=$REGTEST_DIR -regtest"

# === STEP 1: Stop any running services (TEST SERVER ONLY) ===
echo "🛑 Stopping existing services for test environment..."

# Stop systemctl services first (they auto-restart)
echo "Stopping systemctl services..."
sudo systemctl stop bitcoind 2>/dev/null || true
sudo systemctl stop ckpool 2>/dev/null || true
sleep 2

# Now stop any remaining processes
echo "Stopping any remaining bitcoind..."
bitcoin-cli stop 2>/dev/null || true
bitcoin-cli -regtest stop 2>/dev/null || true
$BITCOIN_CLI stop 2>/dev/null || true
sleep 3

# Stop any remaining ckpool
if pgrep -x "ckpool" > /dev/null; then
    echo "Stopping remaining ckpool..."
    pkill -TERM ckpool || true
    sleep 2
    # Force kill if still running
    pkill -9 ckpool 2>/dev/null || true
fi

# Clean up unix sockets
rm -rf /tmp/ckpool 2>/dev/null || true

# === STEP 2: Check firewall ===
echo
echo "🔥 Checking firewall settings..."

# Check if ufw is active
if sudo ufw status | grep -q "Status: active"; then
    echo "UFW is active, checking ports..."
    # Check if ports are already allowed
    if ! sudo ufw status | grep -q "18443"; then
        echo "Opening port 18443 for Bitcoin regtest RPC..."
        sudo ufw allow 18443/tcp comment "Bitcoin regtest RPC" || true
    fi
    if ! sudo ufw status | grep -q "18444"; then
        echo "Opening port 18444 for Bitcoin regtest P2P..."
        sudo ufw allow 18444/tcp comment "Bitcoin regtest P2P" || true
    fi
    if ! sudo ufw status | grep -q "3333"; then
        echo "Opening port 3333 for CKPool Stratum..."
        sudo ufw allow 3333/tcp comment "CKPool Stratum" || true
    fi
    echo "✅ Firewall ports configured"
else
    echo "✓ UFW not active, no firewall changes needed"
fi

# === STEP 3: Setup Bitcoin Cash Regtest ===
echo
echo "🚧 Setting up Bitcoin Cash Regtest node..."

# Create data directory
mkdir -p "$REGTEST_DIR"

# Generate RPC credentials
RPC_USER="${BCH_RPC_USER:-regtest}"
RPC_PASS="${BCH_RPC_PASS:-$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-25)}"

# Create bitcoin.conf with blocknotify
cat > "$REGTEST_DIR/bitcoin.conf" <<EOF
[regtest]
server=1
txindex=1
rpcuser=$RPC_USER
rpcpassword=$RPC_PASS
rpcallowip=127.0.0.1
rpcport=18443
port=18444
fallbackfee=0.00001
dnsseed=0
upnp=0
listen=1

# CKPool block notifications
blocknotify=$CKPOOL_DIR/notifier -s /tmp/ckpool/generator -b %s
EOF

echo -e "${GREEN}✓ Created bitcoin.conf with blocknotify${NC}"

# === STEP 3: Start bitcoind ===
echo "🚀 Starting bitcoind in regtest mode..."
$BITCOIND -daemon

# Wait for node to be ready
echo -n "⏳ Waiting for node to start"
until $BITCOIN_CLI getblockchaininfo > /dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo " ✅"

# Wait for network to be ready
echo -n "⏳ Waiting for network connections"
for i in {1..30}; do
    if $BITCOIN_CLI getnetworkinfo > /dev/null 2>&1; then
        echo " ✅"
        break
    fi
    echo -n "."
    sleep 1
done

# Additional wait to ensure bitcoind is fully ready
echo "⏳ Ensuring bitcoind is fully initialized..."
sleep 5

# === STEP 4: Setup wallet and initial blocks ===
echo "💼 Setting up wallet..."

# Create or load wallet
if $BITCOIN_CLI listwallets 2>/dev/null | grep -q "regtestwallet"; then
    echo "✓ Wallet 'regtestwallet' already exists"
else
    echo "Creating new wallet..."
    $BITCOIN_CLI createwallet "regtestwallet" 2>&1 > /dev/null || echo "✓ Wallet already exists"
fi

# Make sure wallet is loaded
$BITCOIN_CLI loadwallet "regtestwallet" 2>/dev/null || true

# Get mining address
MINING_ADDRESS=$($BITCOIN_CLI -rpcwallet=regtestwallet getnewaddress)
echo "📍 Mining address: $MINING_ADDRESS"

# Mine initial blocks if needed
BLOCK_COUNT=$($BITCOIN_CLI getblockcount)
if [ "$BLOCK_COUNT" -lt 101 ]; then
    echo "⛏️ Mining $(( 101 - BLOCK_COUNT )) blocks..."
    $BITCOIN_CLI generatetoaddress $(( 101 - BLOCK_COUNT )) "$MINING_ADDRESS" > /dev/null
else
    echo "✓ Already have $BLOCK_COUNT blocks"
fi

# Verify node is synced
echo "🧪 Verifying node status..."
NODE_INFO=$($BITCOIN_CLI getblockchaininfo 2>&1)
if echo "$NODE_INFO" | grep -q '"initialblockdownload": false'; then
    echo "✅ Bitcoin node is synced and ready!"
else
    echo "⏳ Node still syncing, waiting..."
    sleep 5
fi

# Mine an extra block to ensure we're past any initialization issues
echo "⛏️ Mining one more block for good measure..."
$BITCOIN_CLI -rpcwallet=regtestwallet generatetoaddress 1 "$MINING_ADDRESS" > /dev/null
sleep 2

# === STEP 5: Setup CKPool ===
echo
echo "🔧 Setting up CKPool for regtest..."

# Check if ckpool directory exists
if [ ! -d "$CKPOOL_DIR" ]; then
    echo -e "${RED}❌ CKPool directory not found at: $CKPOOL_DIR${NC}"
    echo "Please run install-ckpool.sh first"
    exit 1
fi

cd "$CKPOOL_DIR"

# Create regtest-specific config
echo "📝 Creating regtest configuration..."

cat > ckpool-regtest.conf << EOF
{
    "btcd": [
        {
            "url": "127.0.0.1:18443",
            "auth": "$RPC_USER",
            "pass": "$RPC_PASS",
            "notify": true
        }
    ],
    "btcaddress": "$MINING_ADDRESS",
    "btcsig": "",
    "pooladdress": "$MINING_ADDRESS",
    "poolfee": 0,
    "donation": 0,

    "blockpoll": 10,
    "update_interval": 5,
    "serverurl": [
        "0.0.0.0:3333"
    ],

    "mindiff": 1,
    "startdiff": 1,
    "maxdiff": 0,
    "logdir": "logs-regtest",

    "stratum_port": 3333,
    "node_warning": false,
    "log_shares": true,

    "asicboost": true,
    "version_mask": "1fffe000",

    "connector": {
        "bind": "0.0.0.0:3333",
        "bind_address": "0.0.0.0",
        "port": 3333
    }
}
EOF

# Create separate log directory for regtest
mkdir -p logs-regtest

echo -e "${GREEN}✓ Created ckpool-regtest.conf${NC}"

# === STEP 6: Start CKPool ===
echo
echo "🚀 Starting CKPool in regtest mode..."

# Clear any old unix sockets
rm -rf /tmp/ckpool 2>/dev/null || true

# Start ckpool with regtest config
./ckpool -c ckpool-regtest.conf -L &
CKPOOL_PID=$!

# Wait for ckpool to start
echo -n "⏳ Waiting for CKPool to start"
sleep 3
if ! kill -0 $CKPOOL_PID 2>/dev/null; then
    echo -e " ${RED}❌ Failed to start${NC}"
    echo "Check logs-regtest/ckpool.log for errors"
    exit 1
fi
echo " ✅"

# === STEP 7: Display status ===
echo
echo "======================================"
echo -e "${GREEN}Regtest Environment Ready!${NC}"
echo "======================================"
echo
echo "📊 Status:"
echo "  - Bitcoind regtest: Running on port 18443"
echo "  - CKPool: Running on port 3333"
echo "  - Logs: $CKPOOL_DIR/logs-regtest/"
echo
echo "🔌 Connect your miner:"
echo "  - Pool: stratum+tcp://localhost:3333"
echo "  - User: testuser.worker1"
echo "  - Pass: x"
echo
echo "📈 Monitor with:"
echo "  - Stats: ckpmsg -s /tmp/ckpool/stratifier stats"
echo "  - Users: ckpmsg -s /tmp/ckpool/stratifier users"
echo "  - Logs: tail -f $CKPOOL_DIR/logs-regtest/ckpool.log"
echo
echo "⛏️ Generate blocks:"
echo "  $BITCOIN_CLI generatetoaddress 1 $MINING_ADDRESS"
echo
echo "🛑 To stop everything:"
echo "  $0 stop"
echo

# === Handle stop command ===
if [ "$1" == "stop" ]; then
    echo "🛑 Stopping regtest environment..."
    
    # Stop ckpool
    if pgrep -f "ckpool.*regtest" > /dev/null; then
        echo "Stopping CKPool..."
        pkill -f "ckpool.*regtest"
    fi
    
    # Stop regtest bitcoind
    if $BITCOIN_CLI stop 2>/dev/null; then
        echo "Stopping regtest bitcoind..."
        sleep 2
    fi
    
    echo
    echo "🔄 Restarting production services..."
    sudo systemctl start bitcoind 2>/dev/null || echo "bitcoind service not found"
    sudo systemctl start ckpool 2>/dev/null || echo "ckpool service not found"
    
    # Optionally remove firewall rules
    read -p "Remove regtest firewall rules? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo ufw delete allow 18443/tcp 2>/dev/null || true
        sudo ufw delete allow 18444/tcp 2>/dev/null || true
        echo "✅ Removed regtest firewall rules"
    fi
    
    echo "✅ Regtest environment stopped, production services restarted"
    exit 0
fi

# Keep script running to show logs
echo "Press Ctrl+C to stop the test environment"
echo
echo "=== CKPool Log ==="
tail -f logs-regtest/ckpool.log