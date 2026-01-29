#!/bin/bash
# Zivpn UDP Module installer - Fixed
# Creator Deki_niswara

# --- Colors ---
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- Validasi Lisensi ---
# Menggunakan URL Raw GitHub. Pastikan file ada di repo 'izin_ips' branch 'main'.
# Ditambahkan parameter random (?v=...) untuk mencegah cache GitHub agar update IP real-time.
IZIN_URL="https://raw.githubusercontent.com/nurodinahmad34/izin_ips/main/izin_ips.txt?v=$(date +%s)"
SERVER_IP=$(curl -s ifconfig.me)

# Periksa apakah pengambilan IP berhasil
if [ -z "$SERVER_IP" ]; then
  echo "Gagal mendapatkan IP server. Silakan periksa koneksi internet Anda."
  exit 1
fi

# Unduh daftar IP yang diizinkan dalam mode senyap
IZIN_IPS=$(curl -s "$IZIN_URL")

# [BARU] Cek apakah gagal download (misal server down/internet mati)
if [ $? -ne 0 ]; then
  echo -e "\033[1;31mGagal mengunduh file lisensi. Periksa koneksi ke server lisensi.\033[0m"
  exit 1
fi

MATCHING_LINE=$(echo "$IZIN_IPS" | grep -w "$SERVER_IP")

# [BARU] Tampilan pesan error yang lebih rapi
if [ -z "$MATCHING_LINE" ]; then
  clear
  echo -e "\033[1;31m===================================================\033[0m"
  echo -e "\033[1;31m          LISENSI ANDA TIDAK VALID\033[0m"
  echo -e "\033[1;31m===================================================\033[0m"
  echo -e "\033[1;37mIP Anda: \033[1;33m$SERVER_IP\033[0m"
  echo -e "\033[1;37mSilakan hubungi developer untuk mendaftarkan IP Anda.\033[0m"
  echo -e "\033[1;37mKontak: \033[1;32mt.me/Dark_System2x\033[0m"
  echo -e "\033[1;31m===================================================\033[0m"
  exit 1
fi

# Ekstrak informasi dari baris yang cocok
CLIENT_NAME=$(echo "$MATCHING_LINE" | awk '{for(i=2;i<=NF-2;i++) printf $i " "; print ""}' | sed 's/ $//')
EXPIRY_DATE=$(echo "$MATCHING_LINE" | awk '{print $(NF-1)}')

# Validasi tanggal kedaluwarsa
if [[ "$EXPIRY_DATE" != "lifetime" ]]; then
  EXPIRY_SECONDS=$(date -d "$EXPIRY_DATE" +%s)
  CURRENT_SECONDS=$(date +%s)
  
  if [ "$CURRENT_SECONDS" -gt "$EXPIRY_SECONDS" ]; then
    echo "Lisensi untuk klien '$CLIENT_NAME' telah kedaluwarsa pada $EXPIRY_DATE."
    exit 1
  fi
fi

# Simpan informasi lisensi
sudo mkdir -p /etc/zivpn
echo "CLIENT_NAME=\"$CLIENT_NAME\"" > /etc/zivpn/license.conf
echo "EXPIRY_DATE=$EXPIRY_DATE" >> /etc/zivpn/license.conf
echo ""
echo -e "${YELLOW}┌──────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│        LISENSI BERHASIL DIVERIFIKASI         │${NC}"
echo -e "${YELLOW}├──────────────────────────────────────────────┤${NC}"
printf "${YELLOW}│ ${WHITE}%-13s: ${YELLOW}%-29s ${YELLOW}│${NC}\n" "Klien" "$CLIENT_NAME"
printf "${YELLOW}│ ${WHITE}%-13s: ${YELLOW}%-29s ${YELLOW}│${NC}\n" "Kedaluwarsa" "$EXPIRY_DATE"
echo -e "${YELLOW}└──────────────────────────────────────────────┘${NC}"
echo ""
sleep 3
# --- Akhir Validasi Lisensi ---

# Fix for sudo: unable to resolve host
HOSTNAME=$(hostname)
if ! grep -q "127.0.0.1 $HOSTNAME" /etc/hosts; then
  echo "Adding $HOSTNAME to /etc/hosts"
  sudo bash -c "echo '127.0.0.1 $HOSTNAME' >> /etc/hosts"
fi

echo -e "Updating server"
sudo apt-get update && sudo apt-get upgrade -y
if ! command -v ufw &> /dev/null
then
  echo "ufw could not be found, installing it now..."
  sudo apt-get install ufw -y
fi
if ! command -v jq &> /dev/null
then
  echo "jq could not be found, installing it now..."
  sudo apt-get install jq -y
fi
if ! command -v curl &> /dev/null
then
  echo "curl could not be found, installing it now..."
  sudo apt-get install curl -y
fi

# Meminta domain dari pengguna
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
RED='\033[1;31m'
NC='\033[0m'
echo -e "${YELLOW}┌──────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│   Silakan masukkan nama domain Anda      │${NC}"
echo -e "${YELLOW}└──────────────────────────────────────────┘${NC}"
echo -n -e "${WHITE}└──> ${NC}"
read user_domain
if [ -z "$user_domain" ]; then
  echo -e "${RED}Nama domain tidak boleh kosong. Menggunakan hostname sebagai fallback.${NC}"
  user_domain=$(hostname)
fi
echo "Domain Anda akan disimpan sebagai: $user_domain"
sleep 2

if ! command -v figlet &> /dev/null; then
  echo "figlet not found, installing..."
  sudo apt-get install -y figlet
fi

if ! command -v lolcat &> /dev/null; then
  echo "lolcat not found, installing..."
  sudo apt-get install -y ruby-full
  sudo gem install lolcat
fi


# Stop service kalau ada
sudo systemctl stop zivpn.service > /dev/null 2>&1

echo -e "Downloading UDP Service"
# Download to temp file first to verify
sudo wget -q https://github.com/nurodinahmad34/vpnku/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /tmp/zivpn-bin-download

# Check if download succeeded and is not a 404 HTML page (basic check)
if [ -s /tmp/zivpn-bin-download ] && ! grep -q "<html" /tmp/zivpn-bin-download; then
  sudo mv /tmp/zivpn-bin-download /usr/local/bin/zivpn-bin
  sudo chmod +x /usr/local/bin/zivpn-bin
  else
  echo -e "\033[1;31mGagal mengunduh binary zivpn! URL mungkin mati atau salah.\033[0m"
  echo -e "Silakan cek repository atau hubungi developer."
  # Do not exit immediately, maybe user has backup? But service will fail.
  # We remove the invalid file if it exists
  rm -f /tmp/zivpn-bin-download
fi
sudo mkdir -p /etc/zivpn
sudo wget https://raw.githubusercontent.com/nurodinahmad34/vpnku/main/config.json -O /etc/zivpn/config.json

echo "Generating cert files:"
sudo openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
sudo sysctl -w net.core.rmem_max=16777216 > /dev/null
sudo sysctl -w net.core.wmem_max=16777216 > /dev/null

sudo tee /etc/systemd/system/zivpn.service > /dev/null <<EOF
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn-bin server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# Buat file database pengguna awal, file tema, dan file domain
sudo bash -c 'echo "[]" > /etc/zivpn/users.db.json'
sudo bash -c 'echo "rainbow" > /etc/zivpn/theme.conf'
sudo bash -c "echo \"$user_domain\" > /etc/zivpn/domain.conf"

# Bersihin iptables rules yang lama
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
while sudo iptables -t nat -D PREROUTING -i $INTERFACE -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null; do :; done
sudo iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 6000:19999 -j DNAT --to-destination :5667
sudo iptables -A FORWARD -p udp -d 127.0.0.1 --dport 5667 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s 127.0.0.1/32 -o $INTERFACE -j MASQUERADE
sudo apt install iptables-persistent -y -qq
sudo netfilter-persistent save > /dev/null

sudo systemctl daemon-reload
sudo systemctl enable zivpn.service
sudo systemctl start zivpn.service
sudo ufw allow 6000:19999/udp > /dev/null
sudo ufw allow 5667/udp > /dev/null

sudo wget -O /usr/local/bin/zivpn https://raw.githubusercontent.com/nurodinahmad34/vpnku/main/zivpn-menu.sh
sudo chmod +x /usr/local/bin/zivpn

# Unduh skrip uninstall dan letakkan di path yang dapat diakses
sudo wget -O /usr/local/bin/uninstall.sh https://raw.githubusercontent.com/nurodinahmad34/vpnku/main/uninstall.sh
sudo chmod +x /usr/local/bin/uninstall.sh

# Pasang skrip pembersihan otomatis dan jadwalkan
sudo wget -O /usr/local/bin/zivpn-cleanup.sh https://raw.githubusercontent.com/nurodinahmad34/vpnku/main/zivpn-cleanup.sh
sudo chmod +x /usr/local/bin/zivpn-cleanup.sh
sudo wget -O /usr/local/bin/zivpn-autobackup.sh https://raw.githubusercontent.com/nurodinahmad34/vpnku/main/zivpn-autobackup.sh
sudo chmod +x /usr/local/bin/zivpn-autobackup.sh
# Pasang skrip pemantauan server
sudo wget -O /usr/local/bin/zivpn-monitor.sh https://raw.githubusercontent.com/nurodinahmad34/vpnku/main/zivpn-monitor.sh
sudo chmod +x /usr/local/bin/zivpn-monitor.sh

# Jalankan setiap menit untuk penghapusan yang mendekati real-time
sudo bash -c 'echo "* * * * * root /usr/local/bin/zivpn-cleanup.sh" > /etc/cron.d/zivpn-cleanup'
# Jalankan pemantauan server setiap 5 menit
sudo bash -c 'echo "*/5 * * * * root /usr/local/bin/zivpn-monitor.sh" > /etc/cron.d/zivpn-monitor'

# Pasang skrip MOTD (Message of the Day)
sudo wget -O /etc/profile.d/zivpn-motd.sh https://raw.githubusercontent.com/nurodinahmad34/vpnku/main/zivpn-motd.sh
sudo chmod +x /etc/profile.d/zivpn-motd.sh

# --- Install ZIVPN Telegram Bot ---
echo -e "\n${YELLOW}Installing ZIVPN Telegram Bot...${NC}"

# Define Python Executable
PYTHON_EXEC="/usr/bin/python3"

# Install Python3 and pip
if ! command -v $PYTHON_EXEC &> /dev/null; then
  sudo apt-get update
  sudo apt-get install -y python3 python3-pip
fi

# Ensure pip is available
if ! $PYTHON_EXEC -m pip --version &> /dev/null; then
  sudo apt-get install -y python3-pip
fi

# Install python-telegram-bot
echo "Installing python-telegram-bot..."
if ! $PYTHON_EXEC -m pip install python-telegram-bot --break-system-packages; then
  $PYTHON_EXEC -m pip install python-telegram-bot
fi

# Download Bot Script
echo "Downloading bot script..."
sudo wget -O /usr/local/bin/zivpn_bot.py https://raw.githubusercontent.com/nurodinahmad34/vpnku/main/zivpn_bot.py
sudo chmod +x /usr/local/bin/zivpn_bot.py

# --- BAGIAN DOWNLOAD QRIS
echo "Downloading QRIS image..."
# Download QRIS image dari github ke folder /etc/zivpn/
sudo wget -O /etc/zivpn/qris.jpg https://raw.githubusercontent.com/nurodinahmad34/vpnku/main/qris.jpg

# Create systemd service for Bot
echo "Creating bot service..."
sudo tee /etc/systemd/system/zivpn-bot.service > /dev/null <<EOF
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

# Enable and Start Bot Service
sudo systemctl daemon-reload
sudo systemctl enable zivpn-bot.service
sudo systemctl restart zivpn-bot.service
echo -e "${GREEN}ZIVPN Bot installed! Configure token in menu.${NC}"

# Pesan Selesai Instalasi
clear
echo -e "\n${GREEN}============================================${NC}"
echo -e "      ✅ ${WHITE}Instalasi ZIVPN Selesai!${NC} ✅"
echo -e "${GREEN}============================================${NC}"
echo -e "${WHITE}Untuk membuka menu, ketik:${NC} ${YELLOW}zivpn${NC}"
echo -e "${WHITE}Pesan selamat datang akan muncul setiap kali Anda login.${NC}\n"

# Cleanup
rm -f zi.sh* zi-fixed.sh* > /dev/null 2>&1