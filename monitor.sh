#!/bin/bash

# CKPool Monitor - Matrix Style
# Colors
GREEN='\033[0;32m'
BRIGHT_GREEN='\033[1;32m'
CYAN='\033[0;36m'
BRIGHT_CYAN='\033[1;36m'
YELLOW='\033[0;33m'
BRIGHT_YELLOW='\033[1;33m'
RED='\033[0;31m'
BRIGHT_RED='\033[1;31m'
MAGENTA='\033[0;35m'
BRIGHT_MAGENTA='\033[1;35m'
BLUE='\033[0;34m'
BRIGHT_BLUE='\033[1;34m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
DIM='\033[2m'
NC='\033[0m'

# Configuration - use environment variable or default
CKPOOL_DIR="${CKPOOL_DIR:-$HOME/ckpool}"
LOG_FILE="$CKPOOL_DIR/logs/ckpool.log"

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo -e "${RED}Error: Log file not found at $LOG_FILE${NC}"
    echo "Set CKPOOL_DIR environment variable or ensure ckpool is installed at $CKPOOL_DIR"
    exit 1
fi

# Clear screen
clear

# Simple header
echo -e "${BRIGHT_GREEN}▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓${NC}"
echo -e "${BRIGHT_GREEN}                        CKPOOL MONITOR SYSTEM                             ${NC}"
echo -e "${BRIGHT_GREEN}▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓${NC}"
echo -e "${DIM}Monitoring: $LOG_FILE${NC}"
echo -e "${DIM}Press Ctrl+C to exit${NC}"
echo

# Monitor logs
while IFS= read -r line; do
    # Different colors for different log types
    if echo "$line" | grep -q "Block hash changed to"; then
        echo -e "${BRIGHT_MAGENTA}${line}${NC}"
    elif echo "$line" | grep -q "BLOCK"; then
        echo -e "${BRIGHT_GREEN}${line}${NC}"
    elif echo "$line" | grep -q "Authorised client"; then
        echo -e "${GREEN}${line}${NC}"
    elif echo "$line" | grep -q "Network diff set to"; then
        echo -e "${BRIGHT_YELLOW}${line}${NC}"
    elif echo "$line" | grep -q 'User.*hashrate.*"hashrate1m"'; then
        echo -e "${BRIGHT_CYAN}${line}${NC}"
    elif echo "$line" | grep -q 'Pool:{"hashrate1m"'; then
        echo -e "${YELLOW}${line}${NC}"
    elif echo "$line" | grep -q 'Pool:{"diff"'; then
        echo -e "${CYAN}${line}${NC}"
    elif echo "$line" | grep -q 'Pool:{"runtime"'; then
        echo -e "${MAGENTA}${line}${NC}"
    elif echo "$line" | grep -q "ZMQ"; then
        echo -e "${BRIGHT_BLUE}${line}${NC}"
    elif echo "$line" | grep -q "Stored local workbase"; then
        echo -e "${GRAY}${line}${NC}"
    elif echo "$line" | grep -q "Failed over to bitcoind"; then
        echo -e "${BRIGHT_YELLOW}${line}${NC}"
    elif echo "$line" | grep -q "Server alive"; then
        echo -e "${BRIGHT_GREEN}${line}${NC}"
    elif echo "$line" | grep -q "ERROR\|error"; then
        echo -e "${BRIGHT_RED}${line}${NC}"
    elif echo "$line" | grep -q "Disconnected"; then
        echo -e "${RED}${line}${NC}"
    elif echo "$line" | grep -q "Connected"; then
        echo -e "${GREEN}${line}${NC}"
    elif echo "$line" | grep -q "shares"; then
        echo -e "${CYAN}${line}${NC}"
    elif echo "$line" | grep -q "accepted\|rejected"; then
        echo -e "${WHITE}${line}${NC}"
    else
        echo -e "${GREEN}${line}${NC}"
    fi
done < <(tail -f "$LOG_FILE" 2>/dev/null)
