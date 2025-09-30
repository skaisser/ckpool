#!/bin/bash

# CKPool Installation Script
# Builds from current working directory and installs to ~/ckpool

set -e

echo "======================================"
echo "CKPool Installation"
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

# Set directories
INSTALL_DIR="$HOME/ckpool"
CURRENT_DIR=$(pwd)

echo "Building from: $CURRENT_DIR"
echo "Installing to: $INSTALL_DIR"
echo

# Build from current directory
echo "Building CKPool..."

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

echo -e "${GREEN}✓ Build successful${NC}"

# Install
echo "Installing to $INSTALL_DIR..."
make install 2>&1 | grep -v "CAP_NET_BIND_SERVICE" || true

# Create installation directory structure
mkdir -p "$INSTALL_DIR"/{logs,users,pool,data}
mkdir -p "$INSTALL_DIR/logs/shares"

# Copy binaries to main directory for easy access
echo "Copying binaries..."
cp src/ckpool "$INSTALL_DIR/" 2>/dev/null || true
cp src/ckpmsg "$INSTALL_DIR/" 2>/dev/null || true
cp src/notifier "$INSTALL_DIR/" 2>/dev/null || true
[ -d "build/bin" ] && cp build/bin/* "$INSTALL_DIR/" 2>/dev/null || true

# Make binaries executable
chmod +x "$INSTALL_DIR"/{ckpool,ckpmsg,notifier} 2>/dev/null || true

echo -e "${GREEN}✓ Installation complete${NC}"

# Create mainnet configuration
echo "Creating mainnet configuration..."
cat > "$INSTALL_DIR/ckpool-mainnet.conf" << 'EOF'
{
    "btcd": [{
        "url": "127.0.0.1:8332",
        "auth": "yourrpcuser",
        "pass": "yourrpcpass",
        "notify": true,
        "zmqnotify": "tcp://127.0.0.1:28333"
    }],
    "btcaddress": "bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy",
    "btcsig": "YourPool",
    "pooladdress": "bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy",
    "poolfee": 1,
    "blockpoll": 50,
    "update_interval": 15,
    "serverurl": ["0.0.0.0:3333"],
    "logdir": "logs",
    "node_warning": false,
    "log_shares": true,
    "asicboost": true,
    "version_mask": "1fffe000",
    "maxclients": 10000,
    "mindiff": 500000,
    "startdiff": 500000,
    "maxdiff": 1000000,
    "mindiff_overrides": {
        "nicehash": 500000,
        "MiningRigRentals": 1000000
    }
}
EOF

# Create testnet configuration
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
    "btcsig": "TestPool",
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
    "maxdiff": 10000
}
EOF

# Create default symlink to mainnet
ln -sf ckpool-mainnet.conf "$INSTALL_DIR/ckpool.conf"

echo -e "${GREEN}✓ Created configuration files${NC}"

# Create start script
cat > "$INSTALL_DIR/start-ckpool.sh" << 'EOF'
#!/bin/bash

CONFIG="${1:-ckpool.conf}"

echo "Starting CKPool with config: $CONFIG"

if pgrep -x "ckpool" > /dev/null; then
    echo "CKPool is already running!"
    exit 1
fi

cd "$(dirname "$0")"

# Start ckpool
./ckpool -c "$CONFIG" -L

echo "CKPool started. Check logs/ckpool.log"
EOF

chmod +x "$INSTALL_DIR/start-ckpool.sh"

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

echo
echo "======================================"
echo -e "${GREEN}Installation Complete!${NC}"
echo "======================================"
echo
echo "Installed to: $INSTALL_DIR"
echo
echo "Configuration files created:"
echo "  • ckpool-mainnet.conf - Mainnet configuration (port 3333)"
echo "  • ckpool-testnet.conf - Testnet configuration (port 3334)"
echo "  • ckpool.conf - Symlink to mainnet (default)"
echo
echo -e "${YELLOW}Before starting:${NC}"
echo "1. Edit the appropriate config file with your BCH node credentials"
echo "2. Update btcaddress with your address (CashAddr format supported!)"
echo
echo "To start:"
echo "  cd ~/ckpool"
echo "  ./start-ckpool.sh                    # Uses mainnet config"
echo "  ./start-ckpool.sh ckpool-testnet.conf  # Uses testnet config"
echo
echo "To monitor:"
echo "  tail -f ~/ckpool/logs/ckpool.log"
echo
echo "To stop:"
echo "  ./stop-ckpool.sh"
echo
echo -e "${GREEN}CashAddr Support:${NC}"
echo "✓ bitcoincash: addresses (mainnet)"
echo "✓ bchtest: addresses (testnet)"
echo "✓ bchreg: addresses (regtest)"
echo "✓ Legacy addresses also supported"