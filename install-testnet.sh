#!/bin/bash

# CKPool Testnet Installation Script for Bitcoin Cash
# Installs from current directory to ~/ckpool with testnet configuration

set -e

echo "======================================"
echo "CKPool Testnet Installation"
echo "======================================"
echo

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -eq 0 ]; then
   echo -e "${RED}Please don't run this script as root${NC}"
   exit 1
fi

# Set installation directory
INSTALL_DIR="$HOME/ckpool"
CURRENT_DIR=$(pwd)

echo "Building from: $CURRENT_DIR"
echo "Installing to: $INSTALL_DIR"
echo

# Check if already built
if [ ! -f "src/ckpool" ]; then
    echo -e "${YELLOW}Building CKPool first...${NC}"

    # Clean any previous build attempts
    make clean 2>/dev/null || true

    # Build
    autoreconf -fiv
    ./configure --prefix="$INSTALL_DIR/build"
    make -j$(nproc)

    if [ ! -f "src/ckpool" ]; then
        echo -e "${RED}Build failed!${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Build successful${NC}"

# Install
echo "Installing to $INSTALL_DIR..."
make install 2>&1 | grep -v "CAP_NET_BIND_SERVICE" || true

# Create installation directory structure
mkdir -p "$INSTALL_DIR"/{logs,users,pool,data}
mkdir -p "$INSTALL_DIR/logs/shares"

# Copy binaries
echo "Copying binaries..."
cp src/ckpool "$INSTALL_DIR/" 2>/dev/null || true
cp src/ckpmsg "$INSTALL_DIR/" 2>/dev/null || true
cp src/notifier "$INSTALL_DIR/" 2>/dev/null || true
cp build/bin/* "$INSTALL_DIR/" 2>/dev/null || true

# Make binaries executable
chmod +x "$INSTALL_DIR"/{ckpool,ckpmsg,notifier} 2>/dev/null || true

# Create testnet configuration with CashAddr support
echo "Creating testnet configuration..."
cat > "$INSTALL_DIR/ckpool-testnet.conf" << 'EOF'
{
    "btcd": [{
        "url": "127.0.0.1:18332",
        "auth": "yourrpcuser",
        "pass": "yourrpcpass",
        "notify": true
    }],
    "btcaddress": "bchtest:qpvvcah8gzn7kz04jzamet8q2vv8uat9fqvhuy25gm",
    "btcsig": "TestPool-CashAddr",
    "pooladdress": "bchtest:qpvvcah8gzn7kz04jzamet8q2vv8uat9fqvhuy25gm",
    "poolfee": 1,
    "blockpoll": 50,
    "update_interval": 15,
    "serverurl": ["0.0.0.0:3334"],
    "logdir": "logs",
    "node_warning": false,
    "log_shares": true,
    "asicboost": true,
    "version_mask": "1fffe000",
    "maxclients": 100,
    "mindiff": 10,
    "startdiff": 100,
    "maxdiff": 10000,
    "mindiff_overrides": {
        "test": 1,
        "cpu": 1,
        "nicehash": 500000
    }
}
EOF

echo -e "${GREEN}✓ Created testnet configuration with CashAddr${NC}"

# Create testnet start script
cat > "$INSTALL_DIR/start-testnet.sh" << 'EOF'
#!/bin/bash

echo "Starting CKPool on testnet..."

# Check if already running
if pgrep -x "ckpool" > /dev/null; then
    echo "CKPool is already running!"
    exit 1
fi

cd "$(dirname "$0")"

# Start with testnet config and high debug level
./ckpool -c ckpool-testnet.conf -L -l 7

echo "CKPool testnet started."
echo "Monitoring: tail -f logs/ckpool.log"
echo
echo "CashAddr validation logs:"
echo "  grep -i cashaddr logs/ckpool.log"
EOF

chmod +x "$INSTALL_DIR/start-testnet.sh"

# Create stop script
cat > "$INSTALL_DIR/stop-ckpool.sh" << 'EOF'
#!/bin/bash

echo "Stopping CKPool..."
pkill -TERM ckpool
sleep 2

if pgrep -x "ckpool" > /dev/null; then
    echo "Force stopping..."
    pkill -9 ckpool
fi

echo "CKPool stopped."
EOF

chmod +x "$INSTALL_DIR/stop-ckpool.sh"

# Create BCH testnet node config example
cat > "$INSTALL_DIR/bitcoin-testnet.conf.example" << 'EOF'
# Bitcoin Cash testnet configuration
testnet=1
server=1
rpcuser=yourrpcuser
rpcpassword=yourrpcpass
rpcallowip=127.0.0.1
rpcbind=127.0.0.1

# For ZMQ support (optional but recommended)
zmqpubhashblock=tcp://0.0.0.0:28333

# Mining settings
gen=0
EOF

echo
echo "======================================"
echo -e "${GREEN}Installation Complete!${NC}"
echo "======================================"
echo
echo "Installed to: $INSTALL_DIR"
echo
echo "Testnet Configuration:"
echo "  - Stratum Port: 3334"
echo "  - Min Difficulty: 10 (testnet friendly)"
echo "  - CashAddr: bchtest:qpvvcah8gzn7kz04jzamet8q2vv8uat9fqvhuy25gm"
echo "  - RPC Port: 18332 (testnet)"
echo
echo -e "${YELLOW}Before starting:${NC}"
echo "1. Edit ~/ckpool/ckpool-testnet.conf with your BCH testnet node credentials"
echo "2. Update btcaddress with your testnet CashAddr or legacy address"
echo
echo "To start testnet pool:"
echo "  cd ~/ckpool"
echo "  ./start-testnet.sh"
echo
echo "To monitor CashAddr processing:"
echo "  tail -f ~/ckpool/logs/ckpool.log | grep -i cashaddr"
echo
echo "To stop:"
echo "  ./stop-ckpool.sh"
echo
echo -e "${GREEN}CashAddr Support:${NC}"
echo "This build includes CashAddr support for:"
echo "  - bitcoincash: (mainnet)"
echo "  - bchtest: (testnet)"
echo "  - bchreg: (regtest)"