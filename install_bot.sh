#!/bin/bash
# install_bot.sh

echo -e "\033[1;33mInstalling ZIVPN Bot...\033[0m"

# Define the python executable we want to use for the system service
PYTHON_EXEC="/usr/bin/python3"

# Install Python3 and pip if not present
if ! command -v $PYTHON_EXEC &> /dev/null; then
  echo "Installing Python3..."
  apt-get update
  apt-get install -y python3 python3-pip
fi

# Ensure pip is available for that python
if ! $PYTHON_EXEC -m pip --version &> /dev/null; then
  apt-get install -y python3-pip
fi

# Install python-telegram-bot
echo "Installing python-telegram-bot library for $PYTHON_EXEC..."
# Try installing with --break-system-packages (for newer distros like Debian 12/Ubuntu 24)
if ! $PYTHON_EXEC -m pip install python-telegram-bot --break-system-packages; then
  echo "Retrying without --break-system-packages..."
  $PYTHON_EXEC -m pip install python-telegram-bot
fi

# Copy bot script
echo "Copying bot script to /usr/local/bin/zivpn_bot.py..."
cp zivpn_bot.py /usr/local/bin/zivpn_bot.py
chmod +x /usr/local/bin/zivpn_bot.py

# Create systemd service
echo "Creating systemd service..."
cat > /etc/systemd/system/zivpn-bot.service <<EOF
[Unit]
Description=ZIVPN Telegram Bot
After=network.target

[Service]
ExecStart=$PYTHON_EXEC /usr/local/bin/zivpn_bot.py
Restart=always
RestartSec=10
User=root
WorkingDirectory=/etc/zivpn
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

# Reload daemon and enable service
echo "Starting service..."
systemctl daemon-reload
systemctl enable zivpn-bot.service
systemctl restart zivpn-bot.service

# Verification
echo "Checking service status..."
sleep 5

if systemctl is-active --quiet zivpn-bot.service; then
  echo -e "\033[1;32m✅ ZIVPN Bot Service is RUNNING!\033[0m"
  else
  echo -e "\033[1;31m❌ ZIVPN Bot Service FAILED to start!\033[0m"
  echo "Check logs below:"
fi

# Show logs
echo "--- Service Logs (last 20 lines) ---"
journalctl -u zivpn-bot --no-pager -n 20
echo "------------------------------------"

echo -e "\033[1;33mNOTE:\033[0m If the logs show 'Unauthorized Access' or 'Invalid Token', please check /etc/zivpn/bot_config.sh"