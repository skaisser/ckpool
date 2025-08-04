#!/bin/bash

# CKPool Local Build Script for Bitcoin Cash
# Builds from current directory instead of cloning

set -e

echo "======================================"
echo "EloPool CkPool Local Build & Install"
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

# Install dependencies
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y build-essential autoconf automake libtool \
    libssl-dev libjansson-dev libcurl4-openssl-dev libgmp-dev \
    libevent-dev git screen pkg-config jq libzmq3-dev

# For ZMQ support
echo "Ensuring ZMQ development libraries are installed..."
sudo apt-get install -y libzmq3-dev

# Fix build issues
echo
echo "Preparing build environment..."

# Create m4 directory if missing
mkdir -p m4

# Clean any previous build attempts
echo "Cleaning previous builds..."
make clean 2>/dev/null || true
rm -f ltmain.sh 2>/dev/null || true

# Run autoreconf with proper flags
echo "Running autoreconf..."
autoreconf -fiv

# Configure
echo
echo "Configuring CKPool with ZMQ support..."
./configure --prefix="$INSTALL_DIR/build"

# Build
echo
echo "Building CKPool..."
make -j$(nproc)

# Create installation directory
mkdir -p "$INSTALL_DIR"

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

# Copy binaries manually
echo "Copying binaries..."
cp src/ckpool "$INSTALL_DIR/" 2>/dev/null || true
cp src/ckpmsg "$INSTALL_DIR/" 2>/dev/null || true
cp src/notifier "$INSTALL_DIR/" 2>/dev/null || true

# Create working directories
echo "Creating working directories..."
cd "$INSTALL_DIR"
mkdir -p logs users pool data
mkdir -p logs/shares
mkdir -p logs/ckdb

# Set permissions
chmod 755 logs users pool data

# Make binaries executable
chmod +x ckpool ckpmsg notifier 2>/dev/null || true

# Copy binaries to main directory for easy access
cp build/bin/* . 2>/dev/null || true

echo
echo -e "${GREEN}✓ CKPool built and installed successfully!${NC}"
echo

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Check if we already have a test config in source
if [ -f "$CURRENT_DIR/ckpool-test-multinode.conf" ]; then
    echo "Found test configuration file..."
    cp "$CURRENT_DIR/ckpool-test-multinode.conf" "$INSTALL_DIR/ckpool.conf"
    echo -e "${GREEN}✓ Copied test configuration${NC}"
else
    # Create configuration
    echo "======================================"
    echo "Pool Configuration"
    echo "======================================"
    echo

    # Get pool address
    read -p "Enter your pool's BCH address (for fees): " POOL_ADDRESS
    read -p "Enter pool fee percentage (e.g., 1 for 1%): " POOL_FEE

    # Default RPC placeholders for multi-node setup
    echo
    echo -e "${YELLOW}Note: This config supports multiple BCH nodes.${NC}"
    echo "You'll need to edit the RPC credentials and IPs in ckpool.conf"
    echo "after installation to match your BCH nodes."

    # Create ckpool configuration
    cat > ckpool.conf << EOF
{
    "btcd": [
        {
            "url": "CHANGE_ME_NODE1_IP:8332",
            "auth": "CHANGE_ME_RPC_USER",
            "pass": "CHANGE_ME_RPC_PASS",
            "notify": true,
            "zmqnotify": "tcp://CHANGE_ME_NODE1_IP:28333"
        },
        {
            "url": "CHANGE_ME_NODE2_IP:8332",
            "auth": "CHANGE_ME_RPC_USER",
            "pass": "CHANGE_ME_RPC_PASS",
            "notify": true,
            "zmqnotify": "tcp://CHANGE_ME_NODE2_IP:28333"
        }
    ],
    "btcaddress": "$POOL_ADDRESS",
    "btcsig": "/[Solo]",
    "pooladdress": "$POOL_ADDRESS",
    "poolfee": $POOL_FEE,
    "blockpoll": 50,
    "update_interval": 15,
    "serverurl": [
        "0.0.0.0:3333"
    ],
    "logdir": "logs",
    "node_warning": false,
    "log_shares": true,
    "asicboost": true,
    "version_mask": "1fffe000",
    "maxclients": 10000,
    "mindiff": 500000,
    "startdiff": 500000,
    "maxdiff": 1000000,
    "ports": {
        "3333": {
            "mindiff": 500000,
            "startdiff": 500000,
            "maxdiff": 1000000,
            "client_timeout": 1200
        }
    }
}
EOF
fi

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
After=network.target

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

# Note about ZMQ
echo
echo -e "${GREEN}✓ Using ZMQ for block notifications${NC}"
echo "This pool uses ZMQ instead of blocknotify for faster block detection."
echo "Make sure your BCH nodes have ZMQ enabled in their bitcoin.conf."

echo
echo "======================================"
echo -e "${GREEN}Installation Complete!${NC}"
echo "======================================"
echo
echo "CKPool installed to: $INSTALL_DIR"
echo
echo "Configuration Summary:"
echo "  - Stratum Port: 3333"
echo "  - ASICBoost: Enabled"
echo "  - Min Difficulty: 500,000 (ASIC optimized)"
echo "  - Start Difficulty: 500,000"
echo "  - Max Difficulty: 1,000,000"
echo "  - Multi-Node Support: Enabled (2 nodes)"
echo "  - ZMQ Support: Enabled"
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
if [ -f "$INSTALL_DIR/ckpool.conf" ] && grep -q "CHANGE_ME" "$INSTALL_DIR/ckpool.conf"; then
    echo -e "${YELLOW}IMPORTANT: Before starting the pool:${NC}"
    echo "1. Edit ~/ckpool/ckpool.conf and replace:"
    echo "   - CHANGE_ME_NODE1_IP with your first BCH node IP"
    echo "   - CHANGE_ME_NODE2_IP with your second BCH node IP"
    echo "   - CHANGE_ME_RPC_USER with your RPC username"
    echo "   - CHANGE_ME_RPC_PASS with your RPC password"
    echo
    echo "2. Ensure your BCH nodes have ZMQ enabled:"
    echo "   zmqpubhashblock=tcp://0.0.0.0:28333"
    echo
else
    echo -e "${GREEN}Using test configuration with pre-configured nodes.${NC}"
    echo "Check ~/ckpool/ckpool.conf to verify settings."
    echo
fi
echo "Note: CKPool will create user share logs in ~/ckpool/users/"
echo "tracking shares by username for your external payment system."