#!/bin/bash

# CKPool Test Installation Script for Bitcoin Cash Regtest
# Builds from current directory and installs to ~/ckpool-test directory
# Usage: Run this script from the cloned ckpool repository

set -e

echo "======================================"
echo "CKPool Test Environment Installer"
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
    echo "  cd ~/my-ckpool"
    echo "  ./install-ckpool-test.sh"
    exit 1
fi

# Set installation directory for test environment
INSTALL_DIR="$HOME/ckpool-test"
echo "Installing CKPool Test to: $INSTALL_DIR"
echo

# Install dependencies (if not already installed)
echo "Checking dependencies..."
if ! dpkg -l | grep -q "libjansson-dev"; then
    echo "Installing dependencies..."
    sudo apt-get update
    sudo apt-get install -y build-essential autoconf automake libtool \
        libssl-dev libjansson-dev libcurl4-openssl-dev libgmp-dev \
        libevent-dev git screen pkg-config jq
else
    echo -e "${GREEN}✓ Dependencies already installed${NC}"
fi

# Stop any running ckpool first
echo "Stopping any running CKPool instances..."
if pgrep -x "ckpool" > /dev/null; then
    pkill -TERM ckpool 2>/dev/null || true
    sleep 2
    # Force kill if still running
    pkill -9 ckpool 2>/dev/null || true
else
    echo "No ckpool process running"
fi

# Clean up old binaries
echo "Cleaning up old binaries..."
rm -f "$INSTALL_DIR/ckpool" "$INSTALL_DIR/ckpmsg" "$INSTALL_DIR/notifier" 2>/dev/null || true
rm -rf "$INSTALL_DIR/build" 2>/dev/null || true

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
echo "Cleaning previous build..."
make distclean 2>/dev/null || true
make clean 2>/dev/null || true
rm -f ltmain.sh 2>/dev/null || true
rm -rf autom4te.cache 2>/dev/null || true
rm -f config.status config.log 2>/dev/null || true

# Run autoreconf with proper flags
echo "Running autoreconf..."
autoreconf -fiv

# Configure with test-specific options
echo
echo "Configuring CKPool for testing..."
echo "Note: This build includes username-based coinbase support"
./configure --prefix="$INSTALL_DIR/build" --enable-debug

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

# Show binary timestamp to verify it's fresh
echo
echo "Binary build timestamp:"
ls -la "$INSTALL_DIR/ckpool" | awk '{print $6, $7, $8}'

# Go back to main directory
cd "$INSTALL_DIR"

# Make binaries executable
chmod +x ckpool ckpmsg notifier 2>/dev/null || true

# Create working directories
echo "Creating working directories..."
mkdir -p logs users pool data
mkdir -p logs/shares
mkdir -p logs/ckdb
mkdir -p logs-regtest

# Set permissions
chmod 755 logs users pool data logs-regtest

# Copy binaries to main directory for easy access
cp build/bin/* . 2>/dev/null || true

# Create symlinks for test binaries with different names
echo "Creating symlinks for test binaries..."
sudo ln -sf "$INSTALL_DIR/ckpmsg" /usr/local/bin/ckpmsg-test 2>/dev/null || true
sudo ln -sf "$INSTALL_DIR/ckpool" /usr/local/bin/ckpool-test 2>/dev/null || true
sudo ln -sf "$INSTALL_DIR/notifier" /usr/local/bin/notifier-test 2>/dev/null || true

echo
echo -e "${GREEN}✓ CKPool Test environment installed successfully!${NC}"
echo

# Create default regtest configuration
echo "Creating default regtest configuration..."

cat > ckpool-regtest.conf << 'EOF'
{
    "btcd": [
        {
            "url": "127.0.0.1:18443",
            "auth": "regtest",
            "pass": "regtest123",
            "notify": true
        }
    ],
    "btcaddress": "bchreg:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy",
    "btcsig": "/EloPool/",
    "pooladdress": "bchreg:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy",
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

echo -e "${GREEN}✓ Created default ckpool-regtest.conf${NC}"

# Create start script for testing
cat > start-ckpool-test.sh << 'EOF'
#!/bin/bash

# Start CKPool Test Environment
echo "Starting CKPool Test..."

# Check if ckpool is already running
if pgrep -x "ckpool" > /dev/null; then
    echo "CKPool is already running!"
    exit 1
fi

# Ensure we're in the right directory
cd "$(dirname "$0")"

# Clear any old unix sockets
rm -rf /tmp/ckpool 2>/dev/null || true

# Start ckpool with debug logging
./ckpool -c ckpool-regtest.conf -L -D

echo "CKPool test environment started. Check logs-regtest/ directory for output."
echo "To monitor: tail -f logs-regtest/ckpool.log"
EOF

chmod +x start-ckpool-test.sh

# Create stop script
cat > stop-ckpool-test.sh << 'EOF'
#!/bin/bash

# Stop CKPool Test
echo "Stopping CKPool Test..."

# Send SIGTERM to ckpool
pkill -TERM ckpool

sleep 2

# Check if stopped
if pgrep -x "ckpool" > /dev/null; then
    echo "CKPool still running, force stopping..."
    pkill -9 ckpool
fi

# Clean up unix sockets
rm -rf /tmp/ckpool 2>/dev/null || true

echo "CKPool test environment stopped."
EOF

chmod +x stop-ckpool-test.sh

echo
echo "======================================"
echo -e "${GREEN}Test Installation Complete!${NC}"
echo "======================================"
echo
echo "CKPool test environment installed to: $INSTALL_DIR"
echo
echo "Default regtest configuration created in:"
echo "  $INSTALL_DIR/ckpool-regtest.conf"
echo
echo "To use with your test script:"
echo "  1. Update test-ckpool-regtest.sh to use:"
echo "     CKPOOL_BINARY=\"$INSTALL_DIR/ckpool\""
echo "     CKPOOL_DIR=\"$INSTALL_DIR\""
echo
echo "To start manually:"
echo "  cd $INSTALL_DIR"
echo "  ./start-ckpool-test.sh"
echo
echo "To stop:"
echo "  cd $INSTALL_DIR"
echo "  ./stop-ckpool-test.sh"
echo
echo "Monitor logs:"
echo "  tail -f $INSTALL_DIR/logs-regtest/ckpool.log"
echo
echo "Note: This installation is separate from your production ckpool"
echo "and is specifically configured for testing with regtest."
echo
echo "Username-based Coinbase Messages:"
echo "  - Blocks will show: 'EloPool/Mined by [username]/'"
echo "  - Connect miners with format: username.workername"
echo "  - Example: skaisser.rig1 will show 'EloPool/Mined by skaisser/'"