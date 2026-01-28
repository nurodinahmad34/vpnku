#!/bin/bash
# Zivpn Uninstaller - (Improved)

# --- Colors ---
BLUE='\033[1;34m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

clear
echo -e "${YELLOW}--- Uninstall ZIVPN ---${NC}"
echo -e "${RED}PERINGATAN: Tindakan ini akan menghapus semua file Zivpn, konfigurasi, dan data pengguna.${NC}"
read -p "Anda yakin ingin melanjutkan? [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo -e "${GREEN}Proses uninstall dibatalkan.${NC}"
  exit 0
fi

echo -e "${WHITE}Memulai proses uninstall...${NC}"

# 1. Hentikan dan nonaktifkan layanan
echo -e "${BLUE} > Menghentikan layanan Zivpn...${NC}"
sudo systemctl stop zivpn.service > /dev/null 2>&1
sudo systemctl disable zivpn.service > /dev/null 2>&1

# 2. Hapus file layanan systemd
echo -e "${BLUE} > Menghapus file layanan systemd...${NC}"
sudo rm -f /etc/systemd/system/zivpn.service
sudo systemctl daemon-reload

# 3. Hapus semua file yang dapat dieksekusi
echo -e "${BLUE} > Menghapus file yang dapat dieksekusi...${NC}"
sudo rm -f /usr/local/bin/zivpn-bin
sudo rm -f /usr/local/bin/zivpn
sudo rm -f /usr/local/bin/zivpn-cleanup.sh

# 4. Hapus direktori konfigurasi
echo -e "${BLUE} > Menghapus direktori konfigurasi...${NC}"
sudo rm -rf /etc/zivpn

# 5. Hapus jadwal cron
echo -e "${BLUE} > Menghapus jadwal cron...${NC}"
sudo rm -f /etc/cron.d/zivpn-cleanup

# 6. Hapus aturan firewall
echo -e "${BLUE} > Menghapus aturan firewall...${NC}"
# Hapus aturan UFW
sudo ufw delete allow 6000:19999/udp > /dev/null 2>&1
sudo ufw delete allow 5667/udp > /dev/null 2>&1
echo -e "${WHITE}   - Aturan UFW dihapus.${NC}"

# Hapus aturan iptables (lebih andal)
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
if [ -z "$INTERFACE" ]; then
  echo -e "${YELLOW}   - Tidak dapat mendeteksi antarmuka jaringan utama. Aturan iptables mungkin perlu dihapus secara manual.${NC}"
  else
  # Terus hapus aturan PREROUTING hingga tidak ada lagi untuk menghindari error
  while sudo iptables -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null; do :; done
  sudo iptables -D FORWARD -p udp -d 127.0.0.1 --dport 5667 -j ACCEPT 2>/dev/null
  sudo iptables -t nat -D POSTROUTING -s 127.0.0.1/32 -o "$INTERFACE" -j MASQUERADE 2>/dev/null
  # Simpan perubahan iptables
  sudo netfilter-persistent save > /dev/null 2>&1
  echo -e "${WHITE}   - Aturan iptables dihapus.${NC}"
fi

echo -e "${GREEN}Uninstall ZIVPN selesai.${NC}"
echo -e "${WHITE}Sistem Anda telah dibersihkan dari instalasi Zivpn.${NC}"

exit 0