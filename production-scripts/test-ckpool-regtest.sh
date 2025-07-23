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
REGTEST_PEER_DIR="$HOME/.bitcoin-regtest-peer"
CKPOOL_BINARY="$HOME/ckpool-test/ckpool"  # Use test binary
CKPOOL_DIR="$HOME/ckpool-test"  # CKPool test installation directory
CONFIG_DIR="$(pwd)"  # Config in current directory
BITCOIN_CLI="bitcoin-cli -datadir=$REGTEST_DIR -regtest"
BITCOIND="bitcoind -datadir=$REGTEST_DIR -regtest"
BITCOIN_CLI_PEER="bitcoin-cli -datadir=$REGTEST_PEER_DIR -regtest"
BITCOIND_PEER="bitcoind -datadir=$REGTEST_PEER_DIR -regtest"

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
$BITCOIN_CLI_PEER stop 2>/dev/null || true
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
    if ! sudo ufw status | grep -q "18445"; then
        echo "Opening port 18445 for Bitcoin regtest peer P2P..."
        sudo ufw allow 18445/tcp comment "Bitcoin regtest peer P2P" || true
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

# Use simple credentials for testing
RPC_USER="test"
RPC_PASS="test"

# Create bitcoin.conf with blocknotify
cat > "$REGTEST_DIR/bitcoin.conf" <<EOF
[regtest]
server=1
txindex=1
rpcuser=$RPC_USER
rpcpassword=$RPC_PASS
rpcbind=127.0.0.1:18443
rpcallowip=127.0.0.1/32
rpcport=18443
port=18444
fallbackfee=0.00001
dnsseed=0
upnp=0
listen=1
listenonion=0

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

# === STEP 3.5: Setup peer node for network connectivity ===
echo
echo "🔗 Setting up peer node for network connectivity..."

# Create peer data directory
mkdir -p "$REGTEST_PEER_DIR"

# Create peer bitcoin.conf
cat > "$REGTEST_PEER_DIR/bitcoin.conf" <<EOF
[regtest]
server=1
txindex=1
rpcuser=$RPC_USER
rpcpassword=$RPC_PASS
rpcbind=127.0.0.1:18446
rpcallowip=127.0.0.1/32
rpcport=18446
port=18445
fallbackfee=0.00001
dnsseed=0
upnp=0
listen=1
listenonion=0

# Connect to main node
addnode=127.0.0.1:18444
EOF

echo -e "${GREEN}✓ Created peer bitcoin.conf${NC}"

# Start peer bitcoind
echo "🚀 Starting peer bitcoind..."
$BITCOIND_PEER -daemon

# Wait for peer to be ready
echo -n "⏳ Waiting for peer node to start"
until $BITCOIN_CLI_PEER getblockchaininfo > /dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo " ✅"

# Wait for nodes to connect
echo -n "⏳ Waiting for nodes to connect"
for i in {1..30}; do
    CONNECTIONS=$($BITCOIN_CLI getconnectioncount 2>/dev/null || echo "0")
    if [ "$CONNECTIONS" -gt 0 ]; then
        echo " ✅ Connected! ($CONNECTIONS peers)"
        break
    fi
    echo -n "."
    sleep 1
done

# Verify connection
PEER_COUNT=$($BITCOIN_CLI getconnectioncount)
if [ "$PEER_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️ Warning: Nodes not connected, forcing connection...${NC}"
    $BITCOIN_CLI addnode "127.0.0.1:18445" "add"
    sleep 2
fi

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

# Debug: Check RPC connection
echo "🔍 Verifying RPC connection..."
echo "Testing RPC with credentials: $RPC_USER"
if curl -s --user "$RPC_USER:$RPC_PASS" --data-binary '{"jsonrpc": "1.0", "id":"test", "method": "getblockchaininfo", "params": [] }' -H 'content-type: text/plain;' http://127.0.0.1:18443/ > /dev/null 2>&1; then
    echo "✅ RPC connection successful"
else
    echo "❌ RPC connection failed"
    echo "Checking if bitcoind is listening on port 18443..."
    netstat -tln | grep 18443 || echo "Port 18443 not listening!"
    echo "Checking bitcoind logs..."
    tail -20 "$REGTEST_DIR/regtest/debug.log" 2>/dev/null || echo "No debug log found"
fi

# === STEP 5: Setup CKPool ===
echo
echo "🔧 Setting up CKPool for regtest..."

# Check if production ckpool exists
if [ ! -f "$CKPOOL_BINARY" ]; then
    echo -e "${RED}❌ CKPool not found at: $CKPOOL_BINARY${NC}"
    echo "Please run install-ckpool.sh first"
    exit 1
fi

echo "✓ Using ckpool from: $CKPOOL_BINARY"

# Create regtest-specific config in current directory
echo "📝 Creating regtest configuration in: $CONFIG_DIR"

cat > "$CONFIG_DIR/ckpool-regtest.conf" << EOF
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
    "poolfee": 1,

    "blockpoll": 100,
    "update_interval": 30,
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
    },
    "api": {
        "bind": "127.0.0.1:4028",
        "port": 4028,
        "enabled": true
    }
}
EOF

# Create separate log directory for regtest in test ckpool dir
mkdir -p "$CKPOOL_DIR/logs-regtest"

echo -e "${GREEN}✓ Created ckpool-regtest.conf in $CONFIG_DIR${NC}"

# === STEP 6: Start CKPool ===
echo
echo "🚀 CKPool configuration ready!"

# Clear any old unix sockets
rm -rf /tmp/ckpool 2>/dev/null || true

if [ "$1" != "nostart" ]; then
    # Copy service file and start ckpool via systemctl
    echo "Setting up CKPool systemd service..."
    sudo cp "$CONFIG_DIR/ckpool-regtest.service" /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl start ckpool-regtest
    echo "✅ Started ckpool-regtest service"
else
    echo "Skipping ckpool start (nostart flag set)"
    echo
    echo "To manually start ckpool after debugging:"
    echo "  cd $CKPOOL_DIR"
    echo "  $CKPOOL_BINARY -c $CONFIG_DIR/ckpool-regtest.conf -L"
    echo
    exit 0
fi

# Wait for ckpool to start
echo -n "⏳ Waiting for CKPool to initialize"
for i in {1..10}; do
    sleep 1
    echo -n "."
    # Check if ckpool is ready (unix socket exists)
    if [ -S "/tmp/ckpool/stratifier" ]; then
        echo -e " ${GREEN}✅${NC}"
        break
    fi
    # Check if process crashed
    if [ $i -eq 10 ] && [ ! -S "/tmp/ckpool/stratifier" ]; then
        echo -e " ${RED}❌ CKPool failed to start${NC}"
        echo "Last 20 lines of log:"
        tail -20 $CKPOOL_DIR/logs-regtest/ckpool.log 2>/dev/null || echo "No log found"
        exit 1
    fi
done

# Additional wait for bitcoind connection
echo "⏳ Waiting for CKPool to connect to bitcoind..."
sleep 5

# === STEP 7: Display status ===
echo
echo "======================================"
echo -e "${GREEN}Regtest Environment Ready!${NC}"
echo "======================================"
echo
echo "📊 Status:"
echo "  - Bitcoind regtest: Running on port 18443"
echo "  - CKPool: Running on port 3333"
echo "  - Config: $CONFIG_DIR/ckpool-regtest.conf"
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

fi # End of SKIP_START block

# === Handle commands early ===
if [ "$1" == "stop" ]; then
    echo "🛑 Stopping regtest environment..."
    
    # Stop ckpool service
    if systemctl is-active --quiet ckpool-regtest; then
        echo "Stopping CKPool regtest service..."
        sudo systemctl stop ckpool-regtest
        sleep 2
    fi
    
    # Also kill any remaining ckpool processes
    if pgrep -x "ckpool" > /dev/null; then
        echo "Stopping remaining CKPool processes..."
        pkill -TERM ckpool
        sleep 2
    fi
    
    # Stop regtest bitcoind
    if $BITCOIN_CLI stop 2>/dev/null; then
        echo "Stopping regtest bitcoind..."
        sleep 2
    fi
    
    # Stop peer bitcoind
    if $BITCOIN_CLI_PEER stop 2>/dev/null; then
        echo "Stopping peer bitcoind..."
        sleep 2
    fi
    
    echo "✅ Regtest environment stopped"
    exit 0
fi

# Handle status/logs/mine commands that don't need services started
if [ "$1" == "status" ] || [ "$1" == "logs" ] || [ "$1" == "mine" ]; then
    # Jump directly to command handling
    SKIP_START=true
elif [ "$1" != "" ] && [ "$1" != "start" ]; then
    echo "Unknown command: $1"
    echo "Usage: $0 {start|stop|status|logs|mine [username]}"
    exit 1
else
    SKIP_START=false
fi

# Only run the startup sequence if not skipping
if [ "$SKIP_START" != "true" ]; then

# === Handle different commands ===
case "$1" in
    "status")
        echo "🔍 Checking regtest environment status..."
        echo
        
        # Check bitcoind
        if $BITCOIN_CLI getblockchaininfo > /dev/null 2>&1; then
            BLOCKS=$($BITCOIN_CLI getblockcount)
            CONNECTIONS=$($BITCOIN_CLI getconnectioncount)
            echo "✅ Bitcoin Core (main): Running - $BLOCKS blocks, $CONNECTIONS connections"
        else
            echo "❌ Bitcoin Core (main): Not running"
        fi
        
        # Check peer
        if $BITCOIN_CLI_PEER getblockchaininfo > /dev/null 2>&1; then
            echo "✅ Bitcoin Core (peer): Running"
        else
            echo "❌ Bitcoin Core (peer): Not running"
        fi
        
        # Check ckpool
        if systemctl is-active --quiet ckpool-regtest; then
            echo "✅ CKPool: Running (systemd service)"
            # Try to get stats
            ckpmsg -s /tmp/ckpool/stratifier stats 2>/dev/null || echo "   (Unable to get stats)"
        elif pgrep -x "ckpool" > /dev/null; then
            echo "✅ CKPool: Running (standalone process)"
            # Try to get stats
            ckpmsg -s /tmp/ckpool/stratifier stats 2>/dev/null || echo "   (Unable to get stats)"
        else
            echo "❌ CKPool: Not running"
        fi
        
        echo
        exit 0
        ;;
        
    "logs")
        echo "📜 Showing CKPool logs..."
        echo "(Press Ctrl+C to exit)"
        echo
        tail -f $CKPOOL_DIR/logs-regtest/ckpool.log
        ;;
        
    "mine")
        USERNAME="${2:-testuser}"
        echo "⛏️ Testing mining with username: $USERNAME"
        echo
        
        # Get mining address if not set
        if [ -z "$MINING_ADDRESS" ]; then
            MINING_ADDRESS=$($BITCOIN_CLI -rpcwallet=regtestwallet getnewaddress 2>/dev/null || echo "bchreg:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy")
        fi
        
        # Generate a block to trigger ckpool
        echo "Generating a test block..."
        BLOCKHASH=$($BITCOIN_CLI -rpcwallet=regtestwallet generatetoaddress 1 $MINING_ADDRESS | jq -r '.[0]')
        echo "Generated block: $BLOCKHASH"
        
        # Get block details to check coinbase
        echo "Checking coinbase message..."
        COINBASE=$($BITCOIN_CLI getblock $BLOCKHASH 2 | jq -r '.tx[0].vin[0].coinbase' | xxd -r -p)
        echo "Coinbase text: $COINBASE"
        
        # Check if our pool signature is there
        if echo "$COINBASE" | grep -q "EloPool"; then
            echo "✅ Found EloPool signature in coinbase!"
        else
            echo "❌ EloPool signature not found in coinbase"
        fi
        
        exit 0
        ;;
        
    "start")
        # Continue with normal start process
        echo "✅ Starting regtest environment..."
        ;;
        
    *)
        echo "Usage: $0 {start|stop|status|logs|mine [username]}"
        echo
        echo "Commands:"
        echo "  start   - Start the regtest environment"
        echo "  stop    - Stop the regtest environment"
        echo "  status  - Check status of all components"
        echo "  logs    - View CKPool logs"
        echo "  mine    - Test mining with optional username"
        echo
        echo "Example:"
        echo "  $0 start                # Start environment"
        echo "  $0 mine skaisser        # Test mining as 'skaisser'"
        echo "  $0 status               # Check if everything is running"
        echo "  $0 logs                 # View logs"
        echo "  $0 stop                 # Stop everything"
        exit 1
        ;;
esac

echo
echo "✅ Regtest environment is running in background!"
echo
echo "Next steps:"
echo "  - Check status: $0 status"
echo "  - View logs: $0 logs"
echo "  - Test mining: $0 mine skaisser"
echo "  - Stop environment: $0 stop"