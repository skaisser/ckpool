#!/bin/bash

# CKPool Standalone Installation Script for Bitcoin Cash
# Builds from current directory and installs to ~/ckpool directory
# Usage: Run this script from the cloned ckpool repository

set -e

echo "======================================"
echo "EloPool CkPool BCH      Pool Installer"
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

# Save the source directory (where script is run from)
SOURCE_DIR="$(pwd)"

# Check if we're running from the source directory
if [ -f "$SOURCE_DIR/configure.ac" ] && [ -f "$SOURCE_DIR/src/ckpool.c" ]; then
    echo "Running from CKPool source directory: $SOURCE_DIR"
else
    echo -e "${RED}Error: This script must be run from the CKPool source directory${NC}"
    echo "Looking for configure.ac and src/ckpool.c in: $SOURCE_DIR"
    echo
    echo "Please make sure you're in the ckpool directory:"
    echo "  git clone git@github.com:skaisser/ckpool.git"
    echo "  cd ckpool"
    echo "  ./install-ckpool.sh"
    exit 1
fi

# Set installation directory
INSTALL_DIR="$HOME/ckpool"
echo "Installing CKPool to: $INSTALL_DIR"
echo

# Install dependencies
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y build-essential autoconf automake libtool \
    libssl-dev libjansson-dev libcurl4-openssl-dev libgmp-dev \
    libevent-dev git screen pkg-config jq

# Create installation directory
mkdir -p "$INSTALL_DIR"

# Now work in the source directory for building
cd "$SOURCE_DIR"

# Fix build issues
echo
echo "Preparing build environment..."

# Create m4 directory if missing
mkdir -p m4

# Clean any previous build attempts
make clean 2>/dev/null || true
rm -f ltmain.sh 2>/dev/null || true

# Run autoreconf with proper flags
echo "Running autoreconf..."
autoreconf -fiv

# Configure
echo
echo "Configuring CKPool..."
./configure --prefix="$INSTALL_DIR/build"

# Build
echo
echo "Building CKPool..."
make -j$(nproc)

# Install to local directory
echo
echo "Installing CKPool..."
# Ignore capability errors as they're not needed for ports > 1024
make install 2>&1 | grep -v "CAP_NET_BIND_SERVICE" || true

# Check if binaries were created
if [ ! -f "src/ckpool" ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

# Copy binaries manually if install had issues
echo "Copying binaries..."
cp src/ckpool "$INSTALL_DIR/" 2>/dev/null || true
cp src/ckpmsg "$INSTALL_DIR/" 2>/dev/null || true
cp src/notifier "$INSTALL_DIR/" 2>/dev/null || true

# Go back to main directory
cd "$INSTALL_DIR"

# Make binaries executable
chmod +x ckpool ckpmsg notifier 2>/dev/null || true

# Create working directories
echo "Creating working directories..."
mkdir -p logs users pool data
mkdir -p logs/shares
mkdir -p logs/ckdb

# Set permissions
chmod 755 logs users pool data

# Copy binaries to main directory for easy access
cp build/bin/* . 2>/dev/null || true

# Create symlinks for easy access
echo "Creating symlinks for system-wide access..."
sudo ln -sf "$INSTALL_DIR/ckpmsg" /usr/local/bin/ckpmsg 2>/dev/null || true
sudo ln -sf "$INSTALL_DIR/ckpool" /usr/local/bin/ckpool 2>/dev/null || true
sudo ln -sf "$INSTALL_DIR/notifier" /usr/local/bin/notifier 2>/dev/null || true

# Verify symlinks
if [ -L "/usr/local/bin/ckpmsg" ]; then
    echo -e "${GREEN}✓ Created symlink for ckpmsg${NC}"
else
    echo -e "${YELLOW}! Could not create symlink for ckpmsg (may need sudo)${NC}"
fi

echo
echo -e "${GREEN}✓ CKPool installed successfully!${NC}"
echo

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Create configuration
echo "======================================"
echo "Pool Configuration"
echo "======================================"
echo

# Get pool address
read -p "Enter your pool's BCH address (for fees): " POOL_ADDRESS
read -p "Enter pool fee percentage (e.g., 1 for 1%): " POOL_FEE

# Get RPC credentials from bitcoin.conf if available
if [ -f "$HOME/.bitcoin/bitcoin.conf" ]; then
    RPC_USER=$(grep "^rpcuser=" "$HOME/.bitcoin/bitcoin.conf" | cut -d'=' -f2)
    RPC_PASS=$(grep "^rpcpassword=" "$HOME/.bitcoin/bitcoin.conf" | cut -d'=' -f2)
    if [ -n "$RPC_USER" ] && [ -n "$RPC_PASS" ]; then
        echo -e "${GREEN}✓ Found RPC credentials in bitcoin.conf${NC}"
        echo "  Username: $RPC_USER"
    else
        echo -e "${YELLOW}! No RPC credentials found in bitcoin.conf${NC}"
        echo "Please run the BCH node installer first or add credentials manually"
        exit 1
    fi
else
    echo -e "${YELLOW}! No bitcoin.conf found${NC}"
    echo "Please install Bitcoin Cash Node first:"
    echo "  cd ../bchn"
    echo "  ./install-bch-node-stable.sh"
    exit 1
fi

# Create ckpool configuration
cat > ckpool.conf << EOF
{
    "btcd": [
        {
            "url": "127.0.0.1:8332",
            "auth": "$RPC_USER",
            "pass": "$RPC_PASS",
            "notify": true
        }
    ],
    "btcaddress": "$POOL_ADDRESS",
    "btcsig": "",
    "pooladdress": "$POOL_ADDRESS",
    "poolfee": $POOL_FEE,

    "blockpoll": 100,
    "update_interval": 30,
    "serverurl": [
        "0.0.0.0:3333"
    ],

    "mindiff": 1,
    "startdiff": 42,
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
    },
    "api": {
        "bind": "127.0.0.1:4028",
        "port": 4028,
        "enabled": true
    }
}
EOF

echo -e "${GREEN}✓ Created ckpool.conf${NC}"

# Create start script
cat > start-ckpool.sh << 'EOF'
#!/bin/bash

# Start CKPool
echo "Starting CKPool..."

# Check if ckpool is already running
if pgrep -x "ckpool" > /dev/null; then
    echo "CKPool is already running!"
    exit 1
fi

# Ensure we're in the right directory
cd "$(dirname "$0")"

# Start ckpool
./ckpool -c ckpool.conf -L

echo "CKPool started. Check logs/ directory for output."
echo "To monitor: tail -f logs/ckpool.log"
EOF

chmod +x start-ckpool.sh

# Create stop script
cat > stop-ckpool.sh << 'EOF'
#!/bin/bash

# Stop CKPool
echo "Stopping CKPool..."

# Send SIGTERM to ckpool
pkill -TERM ckpool

sleep 2

# Check if stopped
if pgrep -x "ckpool" > /dev/null; then
    echo "CKPool still running, force stopping..."
    pkill -9 ckpool
fi

echo "CKPool stopped."
EOF

chmod +x stop-ckpool.sh

# Create systemd service file
cat > ckpool.service << EOF
[Unit]
Description=CKPool Bitcoin Cash Mining Pool
After=network.target bitcoind.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/ckpool -c $INSTALL_DIR/ckpool.conf -L
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Configure blocknotify in bitcoin.conf
echo
echo "Configuring Bitcoin Cash Node blocknotify..."
if [ -f "$HOME/.bitcoin/bitcoin.conf" ]; then
    # Check if blocknotify already exists
    if grep -q "blocknotify=" "$HOME/.bitcoin/bitcoin.conf"; then
        echo -e "${YELLOW}! blocknotify already configured in bitcoin.conf${NC}"
        echo "Current setting:"
        grep "blocknotify=" "$HOME/.bitcoin/bitcoin.conf"
        echo
        read -p "Replace with CKPool notifier? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Comment out old blocknotify
            sed -i 's/^blocknotify=/#blocknotify=/' "$HOME/.bitcoin/bitcoin.conf"
            # Add new blocknotify
            echo "blocknotify=$INSTALL_DIR/notifier -s /tmp/ckpool/generator -b %s" >> "$HOME/.bitcoin/bitcoin.conf"
            echo -e "${GREEN}✓ Updated blocknotify configuration${NC}"
        fi
    else
        # Add blocknotify
        echo "" >> "$HOME/.bitcoin/bitcoin.conf"
        echo "# CKPool block notifications" >> "$HOME/.bitcoin/bitcoin.conf"
        echo "blocknotify=$INSTALL_DIR/notifier -s /tmp/ckpool/generator -b %s" >> "$HOME/.bitcoin/bitcoin.conf"
        echo -e "${GREEN}✓ Added blocknotify configuration${NC}"
    fi

    echo
    echo -e "${YELLOW}NOTE: Restart bitcoind for blocknotify changes to take effect:${NC}"
    echo "  bitcoin-cli stop"
    echo "  bitcoind -daemon"
else
    echo -e "${YELLOW}! bitcoin.conf not found${NC}"
    echo "Add this line to your bitcoin.conf:"
    echo "  blocknotify=$INSTALL_DIR/notifier -s /tmp/ckpool/generator -b %s"
fi

echo
echo "======================================"
echo -e "${GREEN}Installation Complete!${NC}"
echo "======================================"
echo
echo "CKPool installed to: $INSTALL_DIR"
echo
echo "Configuration Summary:"
echo "  - Pool Address: $POOL_ADDRESS"
echo "  - Pool Fee: $POOL_FEE%"
echo "  - Stratum Port: 3333"
echo "  - ASICBoost: Enabled"
echo
echo "To start the pool:"
echo "  cd ~/ckpool"
echo "  ./start-ckpool.sh"
echo
echo "To stop the pool:"
echo "  cd ~/ckpool"
echo "  ./stop-ckpool.sh"
echo
echo "To install as systemd service:"
echo "  sudo cp ~/ckpool/ckpool.service /etc/systemd/system/"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl enable ckpool"
echo "  sudo systemctl start ckpool"
echo
echo "Monitor logs:"
echo "  tail -f ~/ckpool/logs/ckpool.log"
echo
echo "Query pool stats with ckpmsg:"
echo "  ckpmsg -s /tmp/ckpool/stratifier stats"
echo "  ckpmsg -s /tmp/ckpool/stratifier users"
echo "  ckpmsg -s /tmp/ckpool/stratifier workers"
echo
echo "See API documentation: CKPOOL_API_GUIDE.md"
echo
echo "Note: CKPool will create user share logs in ~/ckpool/users/"
echo "tracking shares by username for your external payment system."
echo
echo "Dynamic Coinbase Messages:"
echo "  - Blocks will show: 'EloPool/Mined by [username]/'"
echo "  - Connect miners with format: username.workername"
echo "  - Example: skaisser.rig1 will show 'EloPool/Mined by skaisser/'"
