#!/bin/bash

# CKPool Post-Installation Script
# Sets up systemd service and firewall rules

set -e

echo "======================================"
echo "CKPool Post-Installation Setup"
echo "======================================"
echo

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo -e "${RED}This script must be run as root (use sudo)${NC}"
   exit 1
fi

# Get the user who called sudo
ACTUAL_USER="${SUDO_USER:-$USER}"
if [ "$ACTUAL_USER" = "root" ]; then
    echo -e "${RED}Please run this script with sudo as a regular user, not as root directly${NC}"
    exit 1
fi

# Prompt for installation directory
echo -e "${YELLOW}Where is CKPool installed?${NC}"
read -e -p "Installation directory (default: /home/$ACTUAL_USER/ckpool): " USER_INSTALL_DIR
INSTALL_DIR="${USER_INSTALL_DIR:-/home/$ACTUAL_USER/ckpool}"

# Verify installation directory exists
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}Error: Directory $INSTALL_DIR does not exist${NC}"
    exit 1
fi

# Verify ckpool binary exists
if [ ! -f "$INSTALL_DIR/ckpool" ]; then
    echo -e "${RED}Error: ckpool binary not found in $INSTALL_DIR${NC}"
    echo "Please run install-ckpool.sh first"
    exit 1
fi

echo
echo "Installation directory: $INSTALL_DIR"
echo "Running as user: $ACTUAL_USER"
echo

# Function to extract ports from JSON config
extract_ports_from_config() {
    local config_file="$1"
    local ports=()

    if [ -f "$config_file" ]; then
        # Extract serverurl ports using grep and sed
        local server_ports=$(grep -o '"serverurl"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$config_file" | \
            grep -o '"[^"]*:[0-9]*"' | \
            sed 's/.*:\([0-9]*\)"/\1/')

        for port in $server_ports; do
            ports+=("$port")
        done
    fi

    echo "${ports[@]}"
}

# Detect ports from configs
echo "Detecting ports from configuration files..."
PORTS=()

# Check main config
if [ -f "$INSTALL_DIR/ckpool.conf" ]; then
    echo "Reading $INSTALL_DIR/ckpool.conf..."
    MAIN_PORTS=($(extract_ports_from_config "$INSTALL_DIR/ckpool.conf"))
    PORTS+=("${MAIN_PORTS[@]}")
fi

# Check testnet config
if [ -f "$INSTALL_DIR/ckpool-testnet.conf" ]; then
    echo "Reading $INSTALL_DIR/ckpool-testnet.conf..."
    TESTNET_PORTS=($(extract_ports_from_config "$INSTALL_DIR/ckpool-testnet.conf"))
    PORTS+=("${TESTNET_PORTS[@]}")
fi

# Remove duplicates
PORTS=($(echo "${PORTS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

echo -e "${GREEN}Detected ports: ${PORTS[*]}${NC}"
echo

# Ask if user wants to configure firewall
if command -v ufw &> /dev/null; then
    echo -e "${YELLOW}Configure firewall (UFW)?${NC}"
    read -p "This will open ports: ${PORTS[*]} (y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Configuring UFW firewall rules..."

        # Ensure UFW is enabled
        if ! ufw status | grep -q "Status: active"; then
            echo "Enabling UFW..."
            ufw --force enable
        fi

        # Open detected ports
        for port in "${PORTS[@]}"; do
            echo "Opening port $port/tcp for stratum mining..."
            ufw allow "$port/tcp" comment "CKPool stratum port"
        done

        # Ask about SSH if not already allowed
        if ! ufw status | grep -q "22/tcp"; then
            echo -e "${YELLOW}Warning: SSH port 22 is not open. Add it now? (y/n)${NC}"
            read -p "" -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                ufw allow 22/tcp comment "SSH"
            fi
        fi

        echo -e "${GREEN}✓ Firewall rules configured${NC}"
        ufw status numbered
    fi
else
    echo -e "${YELLOW}UFW not found. Skipping firewall configuration.${NC}"
fi

echo

# Create systemd service file
echo "Creating systemd service..."

SERVICE_FILE="/etc/systemd/system/ckpool.service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=CKPool - Bitcoin Cash Mining Pool
After=network.target

[Service]
Type=simple
User=$ACTUAL_USER
Group=$ACTUAL_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/ckpool -c $INSTALL_DIR/ckpool.conf -L
ExecStop=/bin/kill -TERM \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ckpool

# Security settings
NoNewPrivileges=true
PrivateTmp=false
ProtectSystem=false
ProtectHome=false
ReadWritePaths=$INSTALL_DIR/logs $INSTALL_DIR/users $INSTALL_DIR/pool $INSTALL_DIR/data /tmp/ckpool

# Resource limits
LimitNOFILE=1048576
LimitNPROC=512

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✓ Systemd service created${NC}"

# Create systemd service file for testnet (optional)
if [ -f "$INSTALL_DIR/ckpool-testnet.conf" ]; then
    echo "Creating testnet systemd service..."

    TESTNET_SERVICE_FILE="/etc/systemd/system/ckpool-testnet.service"
    cat > "$TESTNET_SERVICE_FILE" << EOF
[Unit]
Description=CKPool Testnet - Bitcoin Cash Mining Pool (Testnet)
After=network.target

[Service]
Type=simple
User=$ACTUAL_USER
Group=$ACTUAL_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/ckpool -c $INSTALL_DIR/ckpool-testnet.conf -L
ExecStop=/bin/kill -TERM \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ckpool-testnet

# Security settings
NoNewPrivileges=true
PrivateTmp=false
ProtectSystem=false
ProtectHome=false
ReadWritePaths=$INSTALL_DIR/logs $INSTALL_DIR/users $INSTALL_DIR/pool $INSTALL_DIR/data /tmp/ckpool-testnet

# Resource limits
LimitNOFILE=1048576
LimitNPROC=512

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}✓ Testnet systemd service created${NC}"
fi

# Reload systemd
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable services
echo
echo -e "${YELLOW}Enable CKPool to start on boot?${NC}"
read -p "(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl enable ckpool.service
    echo -e "${GREEN}✓ CKPool service enabled${NC}"

    if [ -f "$TESTNET_SERVICE_FILE" ]; then
        echo -e "${YELLOW}Enable CKPool Testnet to start on boot?${NC}"
        read -p "(y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl enable ckpool-testnet.service
            echo -e "${GREEN}✓ CKPool Testnet service enabled${NC}"
        fi
    fi
fi

# Create monitor script
echo
echo "Creating monitoring and maintenance scripts..."

MONITOR_SCRIPT="$INSTALL_DIR/monitor.sh"
cat > "$MONITOR_SCRIPT" << 'MONITOR_EOF'
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
MONITOR_EOF

chmod +x "$MONITOR_SCRIPT"
chown "$ACTUAL_USER:$ACTUAL_USER" "$MONITOR_SCRIPT"

# Also create in user's home directory for easy access
cp "$MONITOR_SCRIPT" "/home/$ACTUAL_USER/monitor.sh"
chmod +x "/home/$ACTUAL_USER/monitor.sh"
chown "$ACTUAL_USER:$ACTUAL_USER" "/home/$ACTUAL_USER/monitor.sh"

echo -e "${GREEN}✓ Monitor script created${NC}"

# Create cleanup script
CLEANUP_SCRIPT="$INSTALL_DIR/clean-old-blocks.sh"
cat > "$CLEANUP_SCRIPT" << CLEANUP_EOF
#!/bin/bash

# CKPool block directory cleanup script
# Removes block directories older than X days

# Configuration
CKPOOL_DIR="$INSTALL_DIR"
CKPOOL_LOG_DIR="\$CKPOOL_DIR/logs"
DAYS_TO_KEEP=7  # Keep last 7 days of block directories
LOG_FILE="\$CKPOOL_LOG_DIR/cleanup.log"

# Function to log messages
log_message() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" >> "\$LOG_FILE"
}

# Start cleanup
log_message "Starting block directory cleanup"

# Count directories before cleanup
BEFORE_COUNT=\$(find "\$CKPOOL_LOG_DIR" -maxdepth 1 -type d -name "000*" 2>/dev/null | wc -l)

# Find and remove directories older than DAYS_TO_KEEP
find "\$CKPOOL_LOG_DIR" -maxdepth 1 -type d -name "000*" -mtime +\$DAYS_TO_KEEP -exec rm -rf {} \\; 2>/dev/null

# Count directories after cleanup
AFTER_COUNT=\$(find "\$CKPOOL_LOG_DIR" -maxdepth 1 -type d -name "000*" 2>/dev/null | wc -l)

# Calculate removed
REMOVED=\$((BEFORE_COUNT - AFTER_COUNT))

# Log results
log_message "Cleanup complete. Removed \$REMOVED directories. \$AFTER_COUNT remaining."

# Optional: Also clean up old rotated logs
find "\$CKPOOL_LOG_DIR" -name "ckpool.log.*" -mtime +30 -delete 2>/dev/null
CLEANUP_EOF

chmod +x "$CLEANUP_SCRIPT"
chown "$ACTUAL_USER:$ACTUAL_USER" "$CLEANUP_SCRIPT"

echo -e "${GREEN}✓ Cleanup script created${NC}"

# Add cron job for cleanup
echo
echo -e "${YELLOW}Add daily cleanup task to crontab?${NC}"
echo "This will run clean-old-blocks.sh at 3 AM daily"
read -p "(y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Check if cron job already exists
    CRON_JOB="0 3 * * * $CLEANUP_SCRIPT"
    (crontab -u "$ACTUAL_USER" -l 2>/dev/null | grep -v "clean-old-blocks.sh"; echo "$CRON_JOB") | crontab -u "$ACTUAL_USER" -

    echo -e "${GREEN}✓ Cron job added (runs daily at 3 AM)${NC}"
fi

echo
echo "======================================"
echo -e "${GREEN}Post-Installation Complete!${NC}"
echo "======================================"
echo
echo "Service files created:"
echo "  • /etc/systemd/system/ckpool.service"
[ -f "$TESTNET_SERVICE_FILE" ] && echo "  • /etc/systemd/system/ckpool-testnet.service"
echo
echo "Scripts created:"
echo "  • $INSTALL_DIR/monitor.sh"
echo "  • /home/$ACTUAL_USER/monitor.sh (shortcut)"
echo "  • $INSTALL_DIR/clean-old-blocks.sh"
echo
echo "Firewall ports opened:"
for port in "${PORTS[@]}"; do
    echo "  • $port/tcp (stratum mining)"
done
echo
echo -e "${YELLOW}Before starting, please configure:${NC}"
echo "1. Edit $INSTALL_DIR/ckpool.conf with your BCH node credentials"
echo "2. Update btcaddress with your mining address"
echo "3. Update pooladdress with your pool operator fee address"
echo "4. Set poolfee to desired percentage"
echo
echo "Service management commands:"
echo "  sudo systemctl start ckpool          # Start the pool"
echo "  sudo systemctl stop ckpool           # Stop the pool"
echo "  sudo systemctl restart ckpool        # Restart the pool"
echo "  sudo systemctl status ckpool         # Check status"
echo "  sudo journalctl -u ckpool -f         # View logs"
echo
if [ -f "$TESTNET_SERVICE_FILE" ]; then
    echo "Testnet service commands:"
    echo "  sudo systemctl start ckpool-testnet"
    echo "  sudo systemctl status ckpool-testnet"
    echo "  sudo journalctl -u ckpool-testnet -f"
    echo
fi
echo "Monitoring commands:"
echo "  ~/monitor.sh                          # Run colorized log monitor"
echo "  sudo journalctl -u ckpool -f          # View systemd logs"
echo
echo "Maintenance:"
echo "  $CLEANUP_SCRIPT                       # Manual cleanup (runs daily at 3 AM via cron)"
echo
echo -e "${GREEN}Ready to start mining!${NC}"
echo
