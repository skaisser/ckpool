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
Type=forking
User=$ACTUAL_USER
Group=$ACTUAL_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/ckpool -c $INSTALL_DIR/ckpool.conf
ExecStop=/usr/bin/pkill -TERM ckpool
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ckpool

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
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
Type=forking
User=$ACTUAL_USER
Group=$ACTUAL_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/ckpool -c $INSTALL_DIR/ckpool-testnet.conf
ExecStop=/usr/bin/pkill -TERM -f "ckpool.*testnet"
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ckpool-testnet

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
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

echo
echo "======================================"
echo -e "${GREEN}Post-Installation Complete!${NC}"
echo "======================================"
echo
echo "Service files created:"
echo "  • /etc/systemd/system/ckpool.service"
[ -f "$TESTNET_SERVICE_FILE" ] && echo "  • /etc/systemd/system/ckpool-testnet.service"
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
echo -e "${GREEN}Ready to start mining!${NC}"
echo
