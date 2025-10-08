#!/bin/bash

# CKPool block directory cleanup script
# Removes block directories older than X days

# Configuration
CKPOOL_DIR="${CKPOOL_DIR:-$HOME/ckpool}"
CKPOOL_LOG_DIR="$CKPOOL_DIR/logs"
DAYS_TO_KEEP=7  # Keep last 7 days of block directories
LOG_FILE="$CKPOOL_LOG_DIR/cleanup.log"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Start cleanup
log_message "Starting block directory cleanup"

# Count directories before cleanup
BEFORE_COUNT=$(find "$CKPOOL_LOG_DIR" -maxdepth 1 -type d -name "000*" | wc -l)

# Find and remove directories older than DAYS_TO_KEEP
find "$CKPOOL_LOG_DIR" -maxdepth 1 -type d -name "000*" -mtime +$DAYS_TO_KEEP -exec rm -rf {} \; 2>/dev/null

# Count directories after cleanup
AFTER_COUNT=$(find "$CKPOOL_LOG_DIR" -maxdepth 1 -type d -name "000*" | wc -l)

# Calculate removed
REMOVED=$((BEFORE_COUNT - AFTER_COUNT))

# Log results
log_message "Cleanup complete. Removed $REMOVED directories. $AFTER_COUNT remaining."

# Optional: Also clean up old rotated logs
find "$CKPOOL_LOG_DIR" -name "ckpool.log.*" -mtime +30 -delete 2>/dev/null
