#!/bin/bash

# Skrip ini menghapus pengguna yang sudah kedaluwarsa dari database Zivpn dan mengirim notifikasi.

USER_DB="/etc/zivpn/users.db.json"
CONFIG_FILE="/etc/zivpn/config.json"
BOT_CONFIG="/etc/zivpn/bot_config.sh"

# Fungsi untuk mengirim notifikasi (salinan dari zivpn-menu.sh untuk portabilitas)
send_notification() {
  local message="$1"
  if [ -f "$BOT_CONFIG" ]; then
    source "$BOT_CONFIG"
    else
    return
  fi
  if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    return
  fi
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "text=${message}" \
  -d "parse_mode=HTML" > /dev/null
}

# --- Mulai Proses Pembersihan ---

# Periksa apakah file database pengguna ada
if [ ! -f "$USER_DB" ]; then
  # echo "Database pengguna tidak ditemukan. Keluar."
  exit 1
fi

# Dapatkan waktu saat ini sebagai Unix timestamp
current_time=$(date +%s)

# 1. Dapatkan daftar pengguna yang kedaluwarsa untuk notifikasi
expired_users=$(jq -c --argjson now "$current_time" '.[] | select(.expiry_timestamp <= $now)' "$USER_DB")

if [ -z "$expired_users" ]; then
  # echo "Tidak ada pengguna kedaluwarsa yang perlu dihapus."
  exit 0
fi

# 2. Hapus pengguna yang kedaluwarsa dari database
updated_users_db=$(jq --argjson now "$current_time" '[.[] | select(.expiry_timestamp > $now)]' "$USER_DB")
echo "$updated_users_db" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"

# 3. Kirim notifikasi untuk setiap pengguna yang dihapus
IP_ADDRESS=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
echo "$expired_users" | while read -r user_json; do
  username=$(jq -r '.username' <<< "$user_json")
  
  message="────────────────────%0A"
  message+="    ☠️ <b>EXPIRED ACCOUNT DELETED</b> ☠️%0A"
  message+="────────────────────%0A"
  message+="<b>User</b>   : <code>${username}</code>%0A"
  message+="<b>IP VPS</b> : <code>${IP_ADDRESS}</code>%0A"
  message+="────────────────────%0A"
  
  send_notification "$message"
  echo "Pengguna kedaluwarsa '$username' dihapus dan notifikasi dikirim."
done

# 4. Sinkronkan konfigurasi dan restart layanan
passwords_json=$(jq '[.[].password]' "$USER_DB")
jq --argjson passwords "$passwords_json" '.auth.config = $passwords | .config = $passwords' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

sudo systemctl daemon-reload
sudo systemctl restart zivpn.service > /dev/null 2>&1

# echo "Proses pembersihan selesai."
exit 0