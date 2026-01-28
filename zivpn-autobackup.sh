#!/bin/bash

# --- Helper function to send a document to Telegram ---
send_document() {
  local file_path="$1"
  local caption="$2"
  BOT_CONFIG="/etc/zivpn/bot_config.sh"
  
  # Load bot config if it exists
  if [ -f "$BOT_CONFIG" ]; then
    source "$BOT_CONFIG"
    else
    # Exit silently if bot is not configured
    return
  fi
  
  # Check for BOT_TOKEN and CHAT_ID
  if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    return
  fi
  
  # Send the document using curl in silent mode
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
  -F "chat_id=${CHAT_ID}" \
  -F "document=@${file_path}" \
  -F "caption=${caption}" > /dev/null
}

# --- Main Backup Logic ---
BACKUP_DIR="/root"
BACKUP_FILE="$BACKUP_DIR/zivpn_backup_$(date +%Y-%m-%d).tar.gz"
CONFIG_DIR="/etc/zivpn"
DOMAIN=$(cat /etc/zivpn/domain.conf 2>/dev/null || echo "Not Set")
IP_ADDRESS=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# Create the backup archive
tar -czf "$BACKUP_FILE" -C "$CONFIG_DIR" .

# Check if the backup was created successfully
if [ -f "$BACKUP_FILE" ]; then
  # Create a professional caption for the Telegram message
  CAPTION=" ZIVPN AUTO BACKUP
  --------------------
  🗓 DATE: $(date +'%d-%m-%Y %H:%M:%S')
  --------------------
  🌎 DOMAIN: ${DOMAIN}
  🌐 IP      : ${IP_ADDRESS}
  --------------------
  ✅ Backup was successful"
  
  # Send the backup file to Telegram
  send_document "$BACKUP_FILE" "$CAPTION"
  
  # Remove the local backup file after sending
  rm "$BACKUP_FILE"
fi