#!/bin/bash

# Konfigurasi
CPU_THRESHOLD=90
RAM_THRESHOLD=90
LOG_FILE="/var/log/zivpn_monitor.log"

# --- Fungsi Notifikasi Telegram ---
# Salinan fungsi ini ada di sini agar skrip bisa berjalan mandiri via cron
send_notification() {
  local message="$1"
  BOT_CONFIG="/etc/zivpn/bot_config.sh"
  
  if [ -f "$BOT_CONFIG" ]; then
    source "$BOT_CONFIG"
    else
    echo "File konfigurasi bot tidak ditemukan." >> "$LOG_FILE"
    return
  fi
  
  if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "BOT_TOKEN atau CHAT_ID tidak diatur." >> "$LOG_FILE"
    return
  fi
  
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "text=${message}" \
  -d "parse_mode=HTML" > /dev/null
}

# --- Fungsi Utama Pemantauan ---
check_server_usage() {
  # 1. Cek Penggunaan CPU
  # Mengabaikan 100% jika itu adalah idle time
  CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
  CPU_USAGE_INT=${CPU_USAGE%.*}
  
  # 2. Cek Penggunaan RAM
  RAM_USAGE=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2 }')
  
  # Dapatkan info tambahan
  HOSTNAME=$(hostname)
  IP_ADDRESS=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
  
  local notification_needed=false
  local message="🚨 <b>PERINGATAN PENGGUNAAN SERVER TINGGI</b> 🚨%0A"
  message+="============================%0A"
  message+="<b>Server:</b> <code>$HOSTNAME ($IP_ADDRESS)</code>%0A"
  
  if [ "$CPU_USAGE_INT" -ge "$CPU_THRESHOLD" ]; then
    message+="%0A🔥 <b>CPU Usage:</b> <code>${CPU_USAGE}%</code> (Melebihi batas ${CPU_THRESHOLD}%)"
    notification_needed=true
  fi
  
  if [ "$RAM_USAGE" -ge "$RAM_THRESHOLD" ]; then
    message+="%0A💾 <b>RAM Usage:</b> <code>${RAM_USAGE}%</code> (Melebihi batas ${RAM_THRESHOLD}%)"
    notification_needed=true
  fi
  
  if [ "$notification_needed" = true ]; then
    echo "$(date): Mengirim notifikasi penggunaan tinggi. CPU: ${CPU_USAGE}%, RAM: ${RAM_USAGE}%" >> "$LOG_FILE"
    send_notification "$message"
    else
    echo "$(date): Penggunaan normal. CPU: ${CPU_USAGE}%, RAM: ${RAM_USAGE}%" >> "$LOG_FILE"
  fi
}

# Jalankan fungsi utama
check_server_usage