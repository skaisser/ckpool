#!/bin/bash

# Rebuild CKPool test installation with changes
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "======================================"
echo "Rebuilding CKPool Test with Changes"
echo "======================================"
echo

# Source and install directories
SOURCE_DIR="/home/skaisser/my-ckpool"
INSTALL_DIR="$HOME/ckpool-test"

# Stop ckpool if running
echo "Stopping CKPool if running..."
sudo systemctl stop ckpool-regtest 2>/dev/null || true
pkill -9 ckpool 2>/dev/null || true

cd "$SOURCE_DIR"

# Clean build
echo
echo "Cleaning previous build..."
make clean 2>/dev/null || true

# Configure for test installation
echo
echo "Configuring..."
./configure --prefix="$INSTALL_DIR/build"

# Build
echo
echo "Building CKPool with username coinbase support..."
make -j$(nproc)

# Install
echo
echo "Installing to $INSTALL_DIR..."
make install 2>&1 | grep -v "CAP_NET_BIND_SERVICE" || true

# Copy binaries
cp src/ckpool "$INSTALL_DIR/" 2>/dev/null || true
cp src/ckpmsg "$INSTALL_DIR/" 2>/dev/null || true
cp src/notifier "$INSTALL_DIR/" 2>/dev/null || true

# Make executable
chmod +x "$INSTALL_DIR"/{ckpool,ckpmsg,notifier} 2>/dev/null || true

echo
echo -e "${GREEN}✅ CKPool test rebuilt successfully!${NC}"
echo
echo "Changes applied:"
echo "  - Username-based coinbase messages enabled"
echo "  - No longer requires btcsolo mode"
echo "  - Will show 'EloPool/Mined by [username]/' in blocks"
echo
echo "To test:"
echo "  cd $SOURCE_DIR"
echo "  ./test-ckpool-regtest.sh restart"