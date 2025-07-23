#!/bin/bash

# Dynamic paths
REGTEST_DIR="$HOME/.bitcoin-regtest"
CKPOOL_DIR="$HOME/ckpool"

# Check if regtest directory exists
if [ ! -d "$REGTEST_DIR" ]; then
    echo "❌ Regtest directory not found at: $REGTEST_DIR"
    echo "Please run setup-bch-regtest.sh first"
    exit 1
fi

echo "🌀 Starting bitcoind in regtest mode..."
bitcoind -regtest -datadir="$REGTEST_DIR" -daemon

echo -n "⏳ Waiting for bitcoind to respond to RPC"
until bitcoin-cli -regtest -datadir="$REGTEST_DIR" getblockchaininfo > /dev/null 2>&1; do
  echo -n "."
  sleep 0.5
done
echo " ✅"

# Get a mining address from the wallet
echo "📍 Getting mining address..."
MINING_ADDRESS=$(bitcoin-cli -regtest -datadir="$REGTEST_DIR" -rpcwallet=regtestwallet getnewaddress 2>/dev/null || echo "bchreg:qz7ypfwrmmv0vmtl6wcac0tkahm9v08v75jkr3xenk")

echo "⛏️ Generating 1 block to enable getblocktemplate..."
bitcoin-cli -regtest -datadir="$REGTEST_DIR" -rpcwallet=regtestwallet \
  generatetoaddress 1 "$MINING_ADDRESS"

sleep 1

echo "🚀 Starting ckpool..."

# Check if ckpool directory exists
if [ ! -d "$CKPOOL_DIR" ]; then
    echo "❌ CKPool directory not found at: $CKPOOL_DIR"
    echo "Please run install-ckpool.sh first"
    exit 1
fi

cd "$CKPOOL_DIR"

# Check if ckpool binary exists
if [ ! -f "./ckpool" ]; then
    echo "❌ CKPool binary not found"
    echo "Please build CKPool first"
    exit 1
fi

# Create regtest-specific config
echo "📝 Creating regtest configuration..."

# Get RPC credentials from regtest bitcoin.conf
RPC_USER=$(grep "^rpcuser=" "$REGTEST_DIR/bitcoin.conf" | cut -d'=' -f2)
RPC_PASS=$(grep "^rpcpassword=" "$REGTEST_DIR/bitcoin.conf" | cut -d'=' -f2)

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
    "btcaddress": "bchreg:qz7ypfwrmmv0vmtl6wcac0tkahm9v08v75jkr3xenk",
    "btcsig": "",
    "pooladdress": "bchreg:qz7ypfwrmmv0vmtl6wcac0tkahm9v08v75jkr3xenk",
    "poolfee": 0,

    "blockpoll": 100,
    "update_interval": 30,
    "serverurl": [
        "0.0.0.0:3333"
    ],

    "mindiff": 1,
    "startdiff": 1,
    "maxdiff": 0,
    "logdir": "logs",

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

echo "✅ Created ckpool-regtest.conf with port 18443"

./ckpool -c ckpool-regtest.conf
