#!/bin/bash

# CKPool Regtest Cleanup Script
# This script removes all test artifacts and services

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "======================================"
echo "CKPool Complete Cleanup Script"
echo "======================================"
echo

echo -e "${YELLOW}⚠️  This will remove:${NC}"
echo "  - All regtest test data and services"
echo "  - Test installations (ckpool-test)"
echo "  - Current ckpool-regtest.conf in working directory"
echo
read -p "Are you sure you want to cleanup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo
echo "🧹 Starting cleanup..."

# Stop services
echo "📴 Stopping services..."

# Stop ckpool-regtest service if exists
if systemctl list-units --full -all | grep -Fq "ckpool-regtest.service"; then
    echo "  - Stopping ckpool-regtest service..."
    sudo systemctl stop ckpool-regtest 2>/dev/null || true
    sudo systemctl disable ckpool-regtest 2>/dev/null || true
    sudo rm -f /etc/systemd/system/ckpool-regtest.service
    sudo systemctl daemon-reload
fi

# Stop bitcoind processes
bitcoin-cli -datadir=$HOME/.bitcoin-regtest -regtest stop 2>/dev/null || true
bitcoin-cli -datadir=$HOME/.bitcoin-regtest-peer -regtest stop 2>/dev/null || true
sleep 3

# Stop systemctl services
echo "  - Stopping systemctl services..."
sudo systemctl stop bitcoind 2>/dev/null || true
sudo systemctl stop ckpool 2>/dev/null || true

# Kill any remaining processes
pkill -9 ckpool 2>/dev/null || true
pkill -9 -f "bitcoind.*regtest" 2>/dev/null || true

# Also check for any ckpool processes by pattern
pkill -9 -f "ckpool.*regtest" 2>/dev/null || true

echo "✅ Services stopped"

# Remove data directories
echo "🗑️  Removing data directories..."

# Bitcoin regtest data
if [ -d "$HOME/.bitcoin-regtest" ]; then
    echo "  - Removing $HOME/.bitcoin-regtest"
    rm -rf "$HOME/.bitcoin-regtest"
fi

if [ -d "$HOME/.bitcoin-regtest-peer" ]; then
    echo "  - Removing $HOME/.bitcoin-regtest-peer"
    rm -rf "$HOME/.bitcoin-regtest-peer"
fi

# CKPool test installation
if [ -d "$HOME/ckpool-test" ]; then
    echo "  - Removing $HOME/ckpool-test"
    rm -rf "$HOME/ckpool-test"
fi

# Remove test symlinks
echo "  - Removing test symlinks"
sudo rm -f /usr/local/bin/ckpool-test
sudo rm -f /usr/local/bin/ckpmsg-test
sudo rm -f /usr/local/bin/notifier-test

# Remove logs
echo "  - Removing regtest logs"
rm -rf logs-regtest 2>/dev/null || true
rm -rf ~/ckpool-test/logs-regtest 2>/dev/null || true

# Remove unix sockets
echo "  - Removing unix sockets"
rm -rf /tmp/ckpool 2>/dev/null || true

# Remove config files
echo "  - Removing regtest config files"
rm -f ckpool-regtest.conf 2>/dev/null || true
rm -f ckpool-regtest.service 2>/dev/null || true
rm -f ~/ckpool-test/ckpool-regtest.conf 2>/dev/null || true
rm -f ~/my-ckpool/ckpool-regtest.conf 2>/dev/null || true

# Remove test start/stop scripts if they exist
rm -f ~/ckpool-test/start-ckpool-test.sh 2>/dev/null || true
rm -f ~/ckpool-test/stop-ckpool-test.sh 2>/dev/null || true

echo "✅ Data directories removed"

# Remove firewall rules (optional)
if sudo ufw status | grep -q "Status: active"; then
    read -p "Remove regtest firewall rules? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🔥 Removing firewall rules..."
        sudo ufw delete allow 18443/tcp comment "Bitcoin regtest RPC" 2>/dev/null || true
        sudo ufw delete allow 18444/tcp comment "Bitcoin regtest P2P" 2>/dev/null || true
        sudo ufw delete allow 18445/tcp comment "Bitcoin regtest peer P2P" 2>/dev/null || true
        sudo ufw delete allow 18446/tcp 2>/dev/null || true
        sudo ufw delete allow 3333/tcp comment "CKPool Stratum" 2>/dev/null || true
        echo "✅ Firewall rules removed"
    fi
fi

echo
echo "======================================"
echo -e "${GREEN}✅ Cleanup Complete!${NC}"
echo "======================================"
echo
echo "Removed:"
echo "  - CKPool regtest systemd service"
echo "  - Bitcoin regtest data directories"
echo "  - CKPool test installation directory"
echo "  - Test configurations and logs"
echo "  - Unix sockets"
echo "  - Test symlinks"
echo
echo "To run tests again:"
echo "  1. Reinstall test environment:"
echo "     ./install-ckpool-test.sh"
echo "  2. Run regtest:"
echo "     cd production-scripts/"
echo "     ./test-ckpool-regtest.sh start"