#!/bin/bash

# === Config ===
REGTEST_DIR="$HOME/.bitcoin-regtest"
RPC_USER="${BCH_RPC_USER:-regtest}"
RPC_PASS="${BCH_RPC_PASS:-$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-25)}"
BITCOIN_CLI="bitcoin-cli -datadir=$REGTEST_DIR -regtest"
BITCOIND="bitcoind -datadir=$REGTEST_DIR -regtest"

echo "🚧 Setting up Bitcoin Cash Regtest node in: $REGTEST_DIR"

# === 1. Create data directory ===
mkdir -p "$REGTEST_DIR"

# === 2. Create bitcoin.conf ===
cat > "$REGTEST_DIR/bitcoin.conf" <<EOF
regtest=1
server=1
txindex=1
rpcuser=$RPC_USER
rpcpassword=$RPC_PASS
rpcallowip=127.0.0.1
fallbackfee=0.00001
EOF

echo "✅ Config written to $REGTEST_DIR/bitcoin.conf"

# === 3. Start bitcoind ===
echo "🚀 Launching bitcoind in regtest mode..."
$BITCOIND -daemon

# === 4. Wait for node to be ready ===
echo -n "⏳ Waiting for node to start"
until $BITCOIN_CLI getblockchaininfo > /dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo " ✅"

# === 5. Create a wallet ===
echo "💼 Creating wallet..."
$BITCOIN_CLI createwallet "regtestwallet" > /dev/null

# === 6. Get new address and mine 101 blocks ===
ADDRESS=$($BITCOIN_CLI getnewaddress)
echo "⛏ Mining 101 blocks to address: $ADDRESS"
$BITCOIN_CLI generatetoaddress 101 "$ADDRESS" > /dev/null

echo "🎉 Done! Regtest node is live and funded."
echo "🔗 RPC: http://$RPC_USER:$RPC_PASS@127.0.0.1:18443"
echo "📁 Data directory: $REGTEST_DIR"
echo "🔑 RPC credentials saved in: $REGTEST_DIR/bitcoin.conf"
