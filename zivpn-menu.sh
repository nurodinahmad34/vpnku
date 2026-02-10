#!/bin/bash

# --- Konfigurasi Dasar & URL ---
# Arahkan ke folder repo izin_ips
BASE_URL="https://raw.githubusercontent.com/nurodinahmad34/izin_ips/main"
USER_DB="/etc/zivpn/users.db.json"
CONFIG_FILE="/etc/zivpn/config.json"
LICENSE_FILE="/etc/zivpn/license.conf"

# --- Fungsi Validasi Lisensi Online ---
validate_license_online() {
  local IZIN_URL="$BASE_URL/izin_ips.txt?v=$(date +%s)"
  local SERVER_IP
  SERVER_IP=$(curl -s ifconfig.me)
  if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
  fi
  
  if [ -z "$SERVER_IP" ]; then
    echo -e "\033[1;31mGagal mendapatkan IP server. Silakan periksa koneksi internet Anda.\033[0m"
    exit 1
  fi
  
  # Unduh daftar IP yang diizinkan dalam mode senyap
  local IZIN_IPS
  IZIN_IPS=$(curl -s "$IZIN_URL")
  if [ $? -ne 0 ]; then
    echo -e "\033[1;31mGagal mengunduh file lisensi. Periksa koneksi ke server lisensi.\033[0m"
    exit 1
  fi
  
  local MATCHING_LINE
  MATCHING_LINE=$(echo "$IZIN_IPS" | grep -w "$SERVER_IP")
  
  if [ -z "$MATCHING_LINE" ]; then
    clear
    echo -e "\033[1;31m===================================================\033[0m"
    echo -e "\033[1;31m          LISENSI ANDA TIDAK VALID\033[0m"
    echo -e "\033[1;31m===================================================\033[0m"
    echo -e "\033[1;37mIP Anda: \033[1;33m$SERVER_IP\033[0m"
    echo -e "\033[1;37mSilakan hubungi developer untuk mendaftarkan IP Anda.\033[0m"
    echo -e "\033[1;37mKontak: \033[1;32mt.me/adm_tren\033[0m"
    echo -e "\033[1;31m===================================================\033[0m"
    exit 1
  fi
  
  local CLIENT_NAME
  CLIENT_NAME=$(echo "$MATCHING_LINE" | awk '{for(i=2;i<=NF-2;i++) printf $i " "; print ""}' | sed 's/ $//')
  local EXPIRY_DATE
  EXPIRY_DATE=$(echo "$MATCHING_LINE" | awk '{print $(NF-1)}')
  
  if [[ "$EXPIRY_DATE" != "lifetime" ]]; then
    local EXPIRY_SECONDS
    EXPIRY_SECONDS=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
    local CURRENT_SECONDS
    CURRENT_SECONDS=$(date +%s)
    
    if [ "$CURRENT_SECONDS" -gt "$EXPIRY_SECONDS" ]; then
      clear
      echo -e "\033[1;31m===================================================\033[0m"
      echo -e "\033[1;31m            LISENSI ANDA TELAH KEDALUWARSA\033[0m"
      echo -e "\033[1;31m===================================================\033[0m"
      echo -e "\033[1;37mKlien: \033[1;33m$CLIENT_NAME\033[0m"
      echo -e "\033[1;37mTanggal Kedaluwarsa: \033[1;31m$EXPIRY_DATE\033[0m"
      echo -e "\033[1;37mSilakan hubungi developer untuk perpanjangan.\033[0m"
      echo -e "\033[1;37mKontak: \033[1;32mt.me/adm_tren\033[0m"
      echo -e "\033[1;31m===================================================\033[0m"
      exit 1
    fi
  fi
  
  # Jika valid, perbarui file lisensi lokal untuk jaga-jaga
  # Ini memastikan info `lifetime` atau perpanjangan tercermin
  echo "CLIENT_NAME=\"$CLIENT_NAME\"" > "$LICENSE_FILE"
  echo "EXPIRY_DATE=$EXPIRY_DATE" >> "$LICENSE_FILE"
}

# --- Jalankan Validasi Lisensi Saat Startup ---
validate_license_online

# --- Colors ---
BLUE='\033[1;34m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

# --- Theme Configuration ---
THEME_CONFIG="/etc/zivpn/theme.conf"
THEME_CMD="cat" # Default value for main output
PROMPT_COLOR="$YELLOW" # Default prompt color

# Function to load the theme
load_theme() {
  if [ -f "$THEME_CONFIG" ] && [ -s "$THEME_CONFIG" ]; then
    THEME=$(cat "$THEME_CONFIG")
    case $THEME in
    rainbow)
    if command -v lolcat &> /dev/null; then THEME_CMD="lolcat"; else THEME_CMD="cat"; fi
    PROMPT_COLOR="$YELLOW" # Rainbow theme uses a consistent yellow prompt
    ;;
    red)
    THEME_CMD="sed 's/\\x1b\\[[0-9;]*m//g' | sed -e \"s/^/$(echo -e $RED)/\" -e \"s/$/$(echo -e $NC)/\""
    PROMPT_COLOR="$RED"
    ;;
    green)
    THEME_CMD="sed 's/\\x1b\\[[0-9;]*m//g' | sed -e \"s/^/$(echo -e $GREEN)/\" -e \"s/$/$(echo -e $NC)/\""
    PROMPT_COLOR="$GREEN"
    ;;
    yellow)
    THEME_CMD="sed 's/\\x1b\\[[0-9;]*m//g' | sed -e \"s/^/$(echo -e $YELLOW)/\" -e \"s/$/$(echo -e $NC)/\""
    PROMPT_COLOR="$YELLOW"
    ;;
    blue)
    THEME_CMD="sed 's/\\x1b\\[[0-9;]*m//g' | sed -e \"s/^/$(echo -e $BLUE)/\" -e \"s/$/$(echo -e $NC)/\""
    PROMPT_COLOR="$BLUE"
    ;;
    none)
    THEME_CMD="cat"
    PROMPT_COLOR="$WHITE"
    ;;
    *)
    THEME_CMD="cat"
    PROMPT_COLOR="$YELLOW"
    ;;
    esac
    elif command -v lolcat &> /dev/null; then
      # If no config, default to lolcat if available
      THEME_CMD="lolcat"
      PROMPT_COLOR="$YELLOW"
      echo "rainbow" > "$THEME_CONFIG" # Create the file with default
    fi
  }
  
  # Load the theme at the start of the script
  load_theme
  
  # This function is now designed to be called inside a subshell
  # that is piped to the theme engine. It should not contain colors.
  display_license_info_content() {
    local LICENSE_FILE="/etc/zivpn/license.conf"
    
    if [ -f "$LICENSE_FILE" ]; then
      source "$LICENSE_FILE" &> /dev/null
      
      local remaining_display
      if [[ "$EXPIRY_DATE" == "lifetime" ]]; then
        remaining_display="Lifetime"
        else
        local expiry_seconds=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
        if [[ -z "$expiry_seconds" ]]; then
          remaining_display="Invalid Date"
          else
          local current_seconds=$(date +%s)
          if [ "$current_seconds" -gt "$expiry_seconds" ]; then
            remaining_display="Expired"
            else
            local remaining_seconds=$((expiry_seconds - current_seconds))
            local remaining_days=$((remaining_seconds / 86400))
            remaining_display="$remaining_days Days"
          fi
        fi
      fi
      
      printf " License To : %-17s Expiry : %s\n" "$CLIENT_NAME" "$remaining_display"
      printf " Build By   : @adm_tren    Partner: @andyyuda\n"
      echo "==========================================================="
    fi
  }
  
  
  # --- Global Server Info (fetch once) ---
  IP_ADDRESS=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
  DOMAIN=$(cat /etc/zivpn/domain.conf 2>/dev/null || echo "Not Set")
  ISP=$(curl -s ipinfo.io/org || echo "Unknown")
  
  
  # --- Theme Configuration Menu ---
  configure_theme() {
    clear
    (
    echo "--- Pengaturan Tampilan Tema ---"
    echo "Pilih gaya warna untuk tampilan menu:"
    echo ""
    printf "[%2d] 🌈 Pelangi (lolcat)\n" 1
    printf "[%2d] ❤️ Merah\n" 2
    printf "[%2d] 💚 Hijau\n" 3
    printf "[%2d] 💛 Kuning\n" 4
    printf "[%2d] 💙 Biru\n" 5
    printf "[%2d]  plain Tanpa Warna\n" 6
    ) | eval "$THEME_CMD"
    echo ""
    echo -n -e "${PROMPT_COLOR} -> Pilihan Anda:${NC} "
    read choice
    
    case $choice in
    1) echo "rainbow" > "$THEME_CONFIG" && echo -e "${GREEN}Tema diatur ke Pelangi.${NC}" ;;
    2) echo "red" > "$THEME_CONFIG" && echo -e "${GREEN}Tema diatur ke Merah.${NC}" ;;
    3) echo "green" > "$THEME_CONFIG" && echo -e "${GREEN}Tema diatur ke Hijau.${NC}" ;;
    4) echo "yellow" > "$THEME_CONFIG" && echo -e "${GREEN}Tema diatur ke Kuning.${NC}" ;;
    5) echo "blue" > "$THEME_CONFIG" && echo -e "${GREEN}Tema diatur ke Biru.${NC}" ;;
    6) echo "none" > "$THEME_CONFIG" && echo -e "${GREEN}Warna tema dinonaktifkan.${NC}" ;;
    *) echo -e "${RED}Pilihan tidak valid.${NC}" ;;
    esac
    
    # Reload the theme immediately
    load_theme
    sleep 2
  }
  
  # Fungsi untuk mencadangkan dan memulihkan
  backup_restore() {
    clear
    echo -e "${YELLOW}--- Full Backup/Restore ---${NC}"
    echo -e "${WHITE}1. Create Backup${NC}"
    echo -e "${WHITE}2. Restore from Local File${NC}"
    echo -n -e "\n${PROMPT_COLOR} -> Pilihan Anda:${NC} "
    read choice
    
    case $choice in
    1)
    backup_file="/root/zivpn_backup_$(date +%Y-%m-%d).tar.gz"
    tar -czf "$backup_file" -C /etc/zivpn .
    echo -e "${GREEN}Backup created successfully at $backup_file${NC}"
    
    # Send the backup to Telegram
    caption="Zivpn Backup - $(date +'%Y-%m-%d %H:%M:%S')"
    send_document "$backup_file" "$caption"
    echo -e "${GREEN}Backup file sent to Telegram.${NC}"
    ;;
    2)
    echo -n -e "${PROMPT_COLOR} -> Masukkan path lengkap ke file backup:${NC} "
    read backup_file
    if [ -f "$backup_file" ]; then
      tar -xzf "$backup_file" -C /etc/zivpn
      echo -e "${GREEN}Restore successful. Restarting service...${NC}"
      sync_config
      else
      echo -e "${RED}Error: Backup file not found.${NC}"
    fi
    ;;
    *)
    echo -e "${RED}Invalid option.${NC}"
    ;;
    esac
    echo -n -e "\n${PROMPT_COLOR}Tekan [Enter] untuk melanjutkan...${NC}"; read
  }
  
  # Fungsi untuk info VPS
  vps_info() {
    clear
    (
    echo -e "${YELLOW}--- VPS Info ---${NC}"
    echo -e "${WHITE}Hostname: $(hostname)${NC}"
    echo -e "${WHITE}OS: $(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '\"')${NC}"
    echo -e "${WHITE}Kernel: $(uname -r)${NC}"
    echo -e "${WHITE}Uptime: $(uptime -p)${NC}"
    echo -e "${WHITE}Public IP: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')${NC}"
    echo -e "${WHITE}CPU: $(lscpu | grep 'Model name' | awk -F: '{print $2}' | sed 's/^[ \t]*//')${NC}"
    echo -e "${WHITE}RAM: $(free -h | grep Mem | awk '{print $2}')${NC}"
    echo -e "${WHITE}Disk: $(df -h / | tail -n 1 | awk '{print $2}')${NC}"
    ) | eval "$THEME_CMD"
    echo -n -e "\n${PROMPT_COLOR}Tekan [Enter] untuk melanjutkan...${NC}"; read
  }
  
  # Fungsi untuk uninstall interaktif
  interactive_uninstall() {
    clear
    echo -e "${YELLOW}--- Uninstall ZIVPN ---${NC}"
    
    # Periksa apakah skrip uninstall ada di lokasi yang diharapkan
    UNINSTALL_SCRIPT="/usr/local/bin/uninstall.sh"
    if [ ! -f "$UNINSTALL_SCRIPT" ]; then
      echo -e "${RED}Gagal menemukan skrip uninstall di $UNINSTALL_SCRIPT.${NC}"
      echo -e "${WHITE}Pastikan Zivpn diinstal dengan benar.${NC}"
      sleep 3
      return
    fi
    
    echo -n -e "${PROMPT_COLOR}Anda yakin ingin uninstall ZIVPN? [y/N]:${NC} "
    read confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo -e "${WHITE}Memulai proses uninstall...${NC}"
      # Jalankan skrip dari path absolutnya
      sudo bash "$UNINSTALL_SCRIPT"
      # Jika uninstall berhasil, keluar dari menu karena layanan sudah tidak ada
      echo -e "${GREEN}Kembali ke terminal...${NC}"
      exit 0
      else
      echo -e "${GREEN}Proses uninstall dibatalkan.${NC}"
      sleep 2
    fi
  }
  
  # --- END of restored functions ---
  
  # Fungsi untuk mengonfigurasi pengaturan bot Telegram
  configure_bot_settings() {
    clear
    BOT_CONFIG="/etc/zivpn/bot_config.sh"
    
    # Muat konfigurasi lama jika ada
    if [ -f "$BOT_CONFIG" ]; then
      source "$BOT_CONFIG"
    fi
    
    echo -e "${YELLOW}--- Konfigurasi Bot Telegram ---${NC}"
    echo -e "${WHITE}Masukkan detail bot Anda.${NC}\n"
    
    # 1. Minta Bot Token
    echo -n -e "${PROMPT_COLOR} -> Bot Token [${BOT_TOKEN:-'kosong'}]:${NC} "
    read new_token
    [[ -n "$new_token" ]] && BOT_TOKEN="$new_token"
    
    # 2. Minta Admin ID
    echo -n -e "${PROMPT_COLOR} -> Admin ID [${CHAT_ID:-'kosong'}]:${NC} "
    read new_chat_id
    [[ -n "$new_chat_id" ]] && CHAT_ID="$new_chat_id"
    
    # 3. Konfirmasi Penggunaan Channel Log (Y/N)
    echo -e "\n${YELLOW}[ Opsi Tambahan ]${NC}"
    echo -n -e "${PROMPT_COLOR} -> Apakah Anda ingin notifikasi transaksi masuk ke Channel? [y/n]:${NC} "
    read use_channel
    
    if [[ "$use_channel" =~ ^[Yy]$ ]]; then
      echo -e "${WHITE}Tips: Pastikan Bot sudah menjadi Admin di channel tersebut.${NC}"
      echo -n -e "${PROMPT_COLOR} -> Masukkan Grup/Channel ID [${CHANNEL_ID:-'kosong'}]:${NC} "
      read new_channel_id
      [[ -n "$new_channel_id" ]] && CHANNEL_ID="$new_channel_id"
      else
      echo -e "${RED}Fitur Log ke Grup/Channel dinonaktifkan.${NC}"
      CHANNEL_ID="" # Kosongkan ID agar bot tidak mengirim log
    fi
    
    # Simpan konfigurasi ke file
    echo "#!/bin/bash" > "$BOT_CONFIG"
    echo "export BOT_TOKEN='${BOT_TOKEN}'" >> "$BOT_CONFIG"
    echo "export CHAT_ID='${CHAT_ID}'" >> "$BOT_CONFIG"
    echo "export CHANNEL_ID='${CHANNEL_ID}'" >> "$BOT_CONFIG"
    
    echo -e "\n${GREEN}Pengaturan bot berhasil disimpan!${NC}"
    
    # 4. Update Service Systemd
    BOT_SERVICE_FILE="/etc/systemd/system/zivpn-bot.service"
    
    echo -e "${YELLOW}Mengupdate Service Bot...${NC}"
    cat <<EOF > "$BOT_SERVICE_FILE"
    [Unit]
    Description=ZIVPN Telegram Bot
    After=network.target
    
    [Service]
    ExecStart=/usr/bin/python3 /usr/local/bin/zivpn_bot.py
    Restart=always
    RestartSec=10
    User=root
    WorkingDirectory=/etc/zivpn
    Environment=PYTHONUNBUFFERED=1
    
    [Install]
    WantedBy=multi-user.target
    EOF
    
    systemctl daemon-reload
    systemctl enable zivpn-bot.service
    chmod +x /usr/local/bin/zivpn_bot.py
    systemctl restart zivpn-bot.service
    
    echo -e "${GREEN}Bot telah direstart dengan konfigurasi baru.${NC}"
    sleep 2
  }
  
  # Fungsi untuk mengedit domain
  edit_domain() {
    clear
    DOMAIN_CONFIG="/etc/zivpn/domain.conf"
    CURRENT_DOMAIN=$(cat "$DOMAIN_CONFIG" 2>/dev/null || echo "Belum diatur")
    
    echo -e "${YELLOW}--- Edit Domain Server ---${NC}"
    echo -e "${WHITE}Domain saat ini adalah: ${GREEN}$CURRENT_DOMAIN${NC}\n"
    
    echo -n -e "${PROMPT_COLOR} -> Masukkan domain baru:${NC} "
    read new_domain
    
    if [ -z "$new_domain" ]; then
      echo -e "\n${RED}Error: Domain tidak boleh kosong.${NC}"
      sleep 2
      return
    fi
    
    echo "$new_domain" > "$DOMAIN_CONFIG"
    echo -e "\n${GREEN}Domain berhasil diperbarui menjadi: $new_domain${NC}"
    sleep 2
  }
  
  # Fungsi untuk mengirim notifikasi ke Telegram
  send_notification() {
    local message="$1"
    BOT_CONFIG="/etc/zivpn/bot_config.sh"
    
    # Periksa apakah file konfigurasi ada dan dapat dibaca
    if [ -f "$BOT_CONFIG" ]; then
      source "$BOT_CONFIG"
      else
      # Jangan tampilkan error jika bot tidak dikonfigurasi
      return
    fi
    
    # Periksa apakah token dan ID ada isinya
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
      return
    fi
    
    # Kirim pesan menggunakan curl dalam mode senyap
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=${message}" \
    -d "parse_mode=HTML" > /dev/null
  }
  
  # Fungsi untuk mengirim dokumen ke Telegram
  send_document() {
    local file_path="$1"
    local caption="$2"
    BOT_CONFIG="/etc/zivpn/bot_config.sh"
    
    if [ -f "$BOT_CONFIG" ]; then
      source "$BOT_CONFIG"
      else
      return
    fi
    
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
      return
    fi
    
    # Kirim dokumen menggunakan curl dalam mode senyap
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
    -F "chat_id=${CHAT_ID}" \
    -F "document=@${file_path}" \
    -F "caption=${caption}" > /dev/null
  }
  
  
  # Fungsi bantuan untuk menyinkronkan kata sandi dari user.db.json ke config.json
  sync_config() {
    # Ekstrak semua kata sandi ke dalam array JSON menggunakan map
    passwords_json=$(jq '[.[].password]' "$USER_DB")
    
    # Perbarui file konfigurasi utama dengan array kata sandi yang baru
    # Gunakan --argjson untuk memasukkan array JSON dengan aman
    jq --argjson passwords "$passwords_json" '.auth.config = $passwords | .config = $passwords' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    # Muat ulang dan restart layanan untuk menerapkan perubahan
    sudo systemctl daemon-reload
    sudo systemctl restart zivpn.service > /dev/null 2>&1
  }
  
  # Fungsi untuk menambahkan akun reguler
  add_account() {
    clear
    echo -e "${YELLOW}--- Add Regular Account ---${NC}\n"
    echo -n -e "${PROMPT_COLOR} -> Masukkan Username:${NC} "
    read username
    if jq -e --arg user "$username" '.[] | select(.username == $user)' "$USER_DB" > /dev/null; then
      echo -e "\n${RED}Error: Username '$username' already exists.${NC}"
      sleep 2
      return
    fi
    
    echo -n -e "${PROMPT_COLOR} -> Masukkan Password:${NC} "
    read password
    echo -n -e "${PROMPT_COLOR} -> Masukkan Durasi (hari, default: 30):${NC} "
    read duration
    [[ -z "$duration" ]] && duration=30
    
    expiry_timestamp=$(date -d "+$duration days" +%s)
    expiry_readable=$(date -d "@$expiry_timestamp" '+%Y-%m-%d %H:%M:%S')
    
    new_user_json=$(jq -n --arg user "$username" --arg pass "$password" --argjson expiry "$expiry_timestamp" \
    '{username: $user, password: $pass, expiry_timestamp: $expiry}')
    
    jq --argjson new_user "$new_user_json" '. += [$new_user]' "$USER_DB" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
    
    # Tampilkan detail di terminal dan kirim notifikasi
    IP_ADDRESS=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    DOMAIN=$(cat /etc/zivpn/domain.conf 2>/dev/null || echo "$IP_ADDRESS")
    ISP=$(curl -s ipinfo.io/org)
    
    # Format untuk terminal
    expiry_date_only=$(date -d "@$expiry_timestamp" '+%d-%m-%Y')
    (
    echo -e "${YELLOW}────────────────────${NC}"
    echo -e "${GREEN}    ☘ NEW ACCOUNT DETAIL ☘${NC}"
    echo -e "${YELLOW}────────────────────${NC}"
    echo -e "${WHITE}User      : $username${NC}"
    echo -e "${WHITE}Password  : $password${NC}"
    echo -e "${WHITE}HOST      : $DOMAIN${NC}"
    echo -e "${WHITE}IP VPS    : $IP_ADDRESS${NC}"
    echo -e "${WHITE}ISP       : $ISP${NC}"
    echo -e "${WHITE}EXP       : $expiry_date_only / $duration HARI${NC}"
    echo -e "${YELLOW}────────────────────${NC}"
    ) | eval "$THEME_CMD"
    
    # Format untuk Telegram (menggunakan tag HTML untuk tebal)
    message="────────────────────%0A"
    message+="    ☘ <b>NEW ACCOUNT DETAIL</b> ☘%0A"
    message+="────────────────────%0A"
    message+="<b>User</b>      : <code>${username}</code>%0A"
    message+="<b>Password</b>  : <code>${password}</code>%0A"
    message+="<b>HOST</b>      : <code>${DOMAIN}</code>%0A"
    message+="<b>IP VPS</b>    : <code>${IP_ADDRESS}</code>%0A"
    message+="<b>ISP</b>       : <code>${ISP}</code>%0A"
    message+="<b>EXP</b>       : <code>${expiry_date_only} / ${duration} HARI</code>%0A"
    message+="────────────────────%0A"
    message+="Note: Auto notif from your script..."
    
    send_notification "$message"
    
    sync_config
    echo -n -e "\n${PROMPT_COLOR}Tekan [Enter] untuk melanjutkan...${NC}"; read
  }
  
  # Fungsi untuk menambahkan akun trial
  add_trial_account() {
    clear
    echo -e "${YELLOW}--- Add Trial Account ---${NC}\n"
    echo -n -e "${PROMPT_COLOR} -> Masukkan Username (kosongkan untuk acak):${NC} "
    read username
    if [[ -n "$username" ]] && jq -e --arg user "$username" '.[] | select(.username == $user)' "$USER_DB" > /dev/null; then
      echo -e "\n${RED}Error: Username '$username' already exists.${NC}"
      sleep 2
      return
    fi
    [[ -z "$username" ]] && username="trial-$(date +%s)"
    
    echo -n -e "${PROMPT_COLOR} -> Masukkan Password (kosongkan untuk acak):${NC} "
    read password
    [[ -z "$password" ]] && password=$(head -c 8 /dev/urandom | base64)
    
    echo -n -e "${PROMPT_COLOR} -> Masukkan Durasi (menit, default: 60):${NC} "
    read duration
    [[ -z "$duration" ]] && duration=60
    
    expiry_timestamp=$(date -d "+$duration minutes" +%s)
    expiry_readable=$(date -d "@$expiry_timestamp" '+%Y-%m-%d %H:%M:%S')
    
    new_user_json=$(jq -n --arg user "$username" --arg pass "$password" --argjson expiry "$expiry_timestamp" \
    '{username: $user, password: $pass, expiry_timestamp: $expiry}')
    
    jq --argjson new_user "$new_user_json" '. += [$new_user]' "$USER_DB" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
    
    # Tampilkan detail di terminal dan kirim notifikasi
    IP_ADDRESS=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    DOMAIN=$(cat /etc/zivpn/domain.conf 2>/dev/null || echo "$IP_ADDRESS")
    ISP=$(curl -s ipinfo.io/org)
    
    # Format untuk terminal
    expiry_date_only=$(date -d "@$expiry_timestamp" '+%d-%m-%Y')
    (
    echo -e "${YELLOW}────────────────────${NC}"
    echo -e "${GREEN}    ☘ NEW TRIAL ACCOUNT ☘${NC}"
    echo -e "${YELLOW}────────────────────${NC}"
    echo -e "${WHITE}User      : $username${NC}"
    echo -e "${WHITE}Password  : $password${NC}"
    echo -e "${WHITE}HOST      : $DOMAIN${NC}"
    echo -e "${WHITE}IP VPS    : $IP_ADDRESS${NC}"
    echo -e "${WHITE}ISP       : $ISP${NC}"
    echo -e "${WHITE}EXP       : $expiry_date_only / $duration MENIT${NC}"
    echo -e "${YELLOW}────────────────────${NC}"
    ) | eval "$THEME_CMD"
    
    # Format untuk Telegram
    message="────────────────────%0A"
    message+="    ☘ <b>NEW TRIAL ACCOUNT</b> ☘%0A"
    message+="────────────────────%0A"
    message+="<b>User</b>      : <code>${username}</code>%0A"
    message+="<b>Password</b>  : <code>${password}</code>%0A"
    message+="<b>HOST</b>      : <code>${DOMAIN}</code>%0A"
    message+="<b>IP VPS</b>    : <code>${IP_ADDRESS}</code>%0A"
    message+="<b>ISP</b>       : <code>${ISP}</code>%0A"
    message+="<b>EXP</b>       : <code>${expiry_date_only} / ${duration} MENIT</code>%0A"
    message+="────────────────────%0A"
    message+="Note: Auto notif from your script..."
    
    send_notification "$message"
    
    sync_config
    echo -n -e "\n${PROMPT_COLOR}Tekan [Enter] untuk melanjutkan...${NC}"; read
  }
  
  
  # Fungsi untuk menampilkan daftar akun
  list_accounts() {
    clear
    (
    echo -e "${YELLOW}--- Account Details ---${NC}"
    printf "${BLUE}%-20s | %-20s | %-25s${NC}\n" "Username" "Password" "Status"
    echo -e "${BLUE}-------------------------------------------------------------------${NC}"
    
    # Proses seluruh logika di dalam satu panggilan jq untuk efisiensi
    jq -r --argjson now "$(date +%s)" '
    .[] |
    . as $user |
    (
    ($user.expiry_timestamp // ($user.expiry_date | fromdate)) as $expiry_ts |
    ($expiry_ts - $now) as $remaining_seconds |
    if $remaining_seconds <= 0 then
      "\u001b[1;31mKedaluwarsa\u001b[0m"
      else
      ($remaining_seconds / 86400 | floor) as $days |
      (($remaining_seconds % 86400) / 3600 | floor) as $hours |
      (($remaining_seconds % 3600) / 60 | floor) as $minutes |
      if $days > 0 then
        "\u001b[1;32mSisa \($days) hari, \($hours) jam\u001b[0m"
        elif $hours > 0 then
          "\u001b[1;33mSisa \($hours) jam, \($minutes) mnt\u001b[0m"
          else
          "\u001b[1;33mSisa \($minutes) menit\u001b[0m"
          end
          end
          ) as $status |
          [$user.username, $user.password, $status] |
          @tsv' "$USER_DB" |
          while IFS=$'\t' read -r user pass status; do
            printf "${WHITE}%-20s | %-20s | %b${NC}\n" "$user" "$pass" "$status"
          done
          
          echo -e "${BLUE}-------------------------------------------------------------------${NC}"
          ) | eval "$THEME_CMD"
          echo -n -e "\n${PROMPT_COLOR}Tekan [Enter] untuk melanjutkan...${NC}"; read
        }
        
        # --- Helper function to display a simple user list ---
        list_users_simple() {
          echo -e "${YELLOW}--- Daftar Pengguna ---${NC}"
          jq -r '.[].username' "$USER_DB" | nl -w2 -s'. '
          echo "-----------------------"
        }
        
        
        # Fungsi untuk menghapus akun
        delete_account() {
          clear
          echo -e "${YELLOW}--- Delete Account ---${NC}\n"
          list_users_simple
          echo -n -e "${PROMPT_COLOR} -> Masukkan username yang akan dihapus:${NC} "
          read username
          
          if ! jq -e --arg user "$username" '.[] | select(.username == $user)' "$USER_DB" > /dev/null; then
            echo -e "\n${RED}Error: Username '$username' not found.${NC}"
            sleep 2
            return
          fi
          
          jq --arg user "$username" 'del(.[] | select(.username == $user))' "$USER_DB" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
          echo -e "\n${GREEN}Akun '$username' berhasil dihapus.${NC}"
          sync_config
          sleep 2
        }
        
        # Fungsi untuk mengedit tanggal kedaluwarsa
        edit_expiry() {
          clear
          echo -e "${YELLOW}--- Edit Account Expiry Date ---${NC}\n"
          list_users_simple
          echo -n -e "${PROMPT_COLOR} -> Masukkan username yang akan diedit:${NC} "
          read username
          
          if ! jq -e --arg user "$username" '.[] | select(.username == $user)' "$USER_DB" > /dev/null; then
            echo -e "\n${RED}Error: Username '$username' not found.${NC}"
            sleep 2
            return
          fi
          
          echo -n -e "${PROMPT_COLOR} -> Masukkan durasi baru (dalam hari dari sekarang):${NC} "
          read duration
          new_expiry_timestamp=$(date -d "+$duration days" +%s)
          
          # Hapus field lama jika ada
          jq --arg user "$username" --argjson new_expiry "$new_expiry_timestamp" \
          '(.[] | select(.username == $user) | .expiry_timestamp) = $new_expiry | del(.[] | select(.username == $user) | .expiry_date)' \
          "$USER_DB" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
          
          echo -e "\n${GREEN}Tanggal kedaluwarsa untuk '$username' berhasil diperbarui.${NC}"
          sleep 2
        }
        
        # Fungsi untuk mengedit kata sandi
        edit_password() {
          clear
          echo -e "${YELLOW}--- Edit Account Password ---${NC}\n"
          list_users_simple
          echo -n -e "${PROMPT_COLOR} -> Masukkan username yang akan diedit:${NC} "
          read username
          
          if ! jq -e --arg user "$username" '.[] | select(.username == $user)' "$USER_DB" > /dev/null; then
            echo -e "\n${RED}Error: Username '$username' not found.${NC}"
            sleep 2
            return
          fi
          
          echo -n -e "${PROMPT_COLOR} -> Masukkan password baru:${NC} "
          read new_password
          
          jq --arg user "$username" --arg new_pass "$new_password" '(.[] | select(.username == $user) | .password) |= $new_pass' "$USER_DB" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
          
          echo -e "\n${GREEN}Password untuk '$username' telah diperbarui.${NC}"
          sync_config
          sleep 2
        }
        
        # Fungsi untuk mengelola cron job cadangan otomatis
        manage_auto_backup() {
          CRON_FILE="/etc/cron.d/zivpn-autobackup"
          clear
          echo -e "${YELLOW}--- Pengaturan Cadangan Otomatis ---${NC}"
          
          # Periksa status saat ini
          if [ -f "$CRON_FILE" ]; then
            echo -e "${GREEN}Status: Cadangan Otomatis AKTIF${NC}"
            echo -e "${WHITE}Cadangan dijadwalkan setiap hari pada pukul 00:00.${NC}"
            echo ""
            echo -e "${WHITE}1. Nonaktifkan Cadangan Otomatis${NC}"
            echo -e "${WHITE}2. Kembali ke Menu Utama${NC}"
            echo -n -e "\n${PROMPT_COLOR} -> Pilihan Anda:${NC} "
            read choice
            case $choice in
            1)
            sudo rm "$CRON_FILE"
            echo -e "${GREEN}Cadangan otomatis telah dinonaktifkan.${NC}"
            sleep 2
            ;;
            *)
            ;;
            esac
            else
            echo -e "${RED}Status: Cadangan Otomatis NONAKTIF${NC}"
            echo ""
            echo -e "${WHITE}1. Aktifkan Cadangan Otomatis (Setiap hari jam 00:00)${NC}"
            echo -e "${WHITE}2. Kembali ke Menu Utama${NC}"
            echo -n -e "\n${PROMPT_COLOR} -> Pilihan Anda:${NC} "
            read choice
            case $choice in
            1)
            # Tulis cron job ke file dengan sudo
              sudo bash -c 'echo "0 0 * * * root /usr/local/bin/zivpn-autobackup.sh" > /etc/cron.d/zivpn-autobackup'
              echo -e "${GREEN}Cadangan otomatis telah diaktifkan.${NC}"
              sleep 2
              ;;
              *)
              ;;
              esac
            fi
          }
          
          # --- Bandwidth Monitor Menu ---
          bandwidth_menu() {
            # Check for vnstat once at the beginning
            if ! command -v vnstat &> /dev/null; then
              echo -e "${YELLOW}vnstat is not installed. Installing...${NC}"
              sudo apt-get update > /dev/null 2>&1
              sudo apt-get install -y vnstat > /dev/null 2>&1
              if [ $? -ne 0 ]; then
                echo -e "${RED}Failed to install vnstat. Please install it manually.${NC}"
                sleep 2
                return
              fi
              # find the default network interface
              INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
              sudo vnstat -u -i ${INTERFACE}
            fi
            
            while true; do
              clear
              (
              echo "──────────────────────────────────────"
              echo "           BANDWITH MONITOR"
              echo "──────────────────────────────────────"
              printf " [%02d] View Total Usage Summary\n" 1
              printf " [%02d] View Usage Table Every 5 Minutes\n" 2
              printf " [%02d] View Usage Table Every Hour\n" 3
              printf " [%02d] View Usage Table Every Day\n" 4
              printf " [%02d] View Usage Table Every Month\n" 5
              printf " [%02d] View Usage Table Every Year\n" 6
              printf " [%02d] View Highest Usage Table\n" 7
              printf " [%02d] Hourly Usage Statistics\n" 8
              printf " [%02d] View Current Active Usage\n" 9
              printf " [%02d] View Current Active Traffic Usage\n" 10
              echo "──────────────────────────────────────"
              echo " Input x or [ Ctrl+C ] • To-bw"
              echo "──────────────────────────────────────"
              ) | eval "$THEME_CMD"
              echo -n -e "${PROMPT_COLOR} -> Masukkan pilihan Anda:${NC} "
              read -r choice
              
              case $choice in
              1)
              clear
              vnstat
              ;;
              2)
              clear
              vnstat -5
              ;;
              3)
              clear
              vnstat -h
              ;;
              4)
              clear
              vnstat -d
              ;;
              5)
              clear
              vnstat -m
              ;;
              6)
              clear
              vnstat -y
              ;;
              7)
              clear
              vnstat -t
              ;;
              8)
              clear
              vnstat -h
              ;;
              9)
              clear
              vnstat -l
              ;;
              10)
              clear
              vnstat -tr
              ;;
              x)
              return
              ;;
              *)
              clear
              echo -e "${RED}Invalid option, please try again.${NC}"
              sleep 2
              continue
              ;;
              esac
              echo -n -e "\n${PROMPT_COLOR}Tekan [Enter] untuk kembali...${NC}"; read
            done
          }
          
          # --- Check CPU & RAM ---
          check_cpu_ram() {
            GOTOP_SCRIPT="/usr/local/bin/gotop"
            if [ ! -f "$GOTOP_SCRIPT" ]; then
              echo -e "${YELLOW}Downloading gotop script...${NC}"
              wget -O "$GOTOP_SCRIPT" https://raw.githubusercontent.com/Nizwarax/gotop/main/gotop > /dev/null 2>&1
              if [ $? -ne 0 ]; then
                echo -e "${RED}Failed to download gotop script.${NC}"
                sleep 2
                return
              fi
              chmod +x "$GOTOP_SCRIPT"
            fi
            echo -e "${GREEN}Starting gotop...${NC}"
            sleep 1
            "$GOTOP_SCRIPT"
          }
          
          # --- Service Management Menu ---
          manage_service() {
            while true; do
              clear
              # Get the latest status
              SERVICE_STATUS=$(sudo systemctl is-active zivpn.service)
              if [[ "$SERVICE_STATUS" == "active" ]]; then
                STATUS_DISPLAY="${GREEN}● Aktif${NC}"
                else
                STATUS_DISPLAY="${RED}● Tidak Aktif${NC}"
              fi
              
              (
              echo "──────────────────────────────────────"
              echo "           MANAJEMEN LAYANAN"
              echo "──────────────────────────────────────"
              echo -e " Status Layanan: $STATUS_DISPLAY"
              echo "--------------------------------------"
              printf " [%02d] Mulai Layanan Zivpn\n" 1
              printf " [%02d] Hentikan Layanan Zivpn\n" 2
              printf " [%02d] Mulai Ulang Layanan Zivpn\n" 3
              printf " [%02d] Lihat Status Layanan\n" 4
              echo "--------------------------------------"
              printf " [%02d] Kembali ke Menu Utama\n" 0
              echo "──────────────────────────────────────"
              ) | eval "$THEME_CMD"
              echo -n -e "${PROMPT_COLOR} -> Masukkan pilihan Anda:${NC} "
              read -r choice
              
              case $choice in
              1)
              clear
              echo -e "${YELLOW}Memulai layanan Zivpn...${NC}"
              sudo systemctl start zivpn.service
              sleep 1
              echo -e "${GREEN}Layanan Zivpn telah dimulai.${NC}"
              echo -n -e "\n${PROMPT_COLOR}Tekan [Enter] untuk melanjutkan...${NC}"; read
              ;;
              2)
              clear
              echo -e "${YELLOW}Menghentikan layanan Zivpn...${NC}"
              sudo systemctl stop zivpn.service
              sleep 1
              echo -e "${GREEN}Layanan Zivpn telah dihentikan.${NC}"
              echo -n -e "\n${PROMPT_COLOR}Tekan [Enter] untuk melanjutkan...${NC}"; read
              ;;
              3)
              clear
              echo -e "${YELLOW}Memulai ulang layanan Zivpn...${NC}"
              sudo systemctl restart zivpn.service
              sleep 1
              echo -e "${GREEN}Layanan Zivpn telah dimulai ulang.${NC}"
              echo -n -e "\n${PROMPT_COLOR}Tekan [Enter] untuk melanjutkan...${NC}"; read
              ;;
              4)
              clear
              echo -e "${YELLOW}--- Status Layanan Zivpn ---${NC}"
              sudo systemctl status zivpn.service
              echo -n -e "\n${PROMPT_COLOR}Tekan [Enter] untuk melanjutkan...${NC}"; read
              ;;
              0)
              return
              ;;
              *)
              clear
              echo -e "${RED}Pilihan tidak valid, silakan coba lagi.${NC}"
              sleep 2
              ;;
              esac
            done
          }
          
          # --- Update Script Function ---
          update_script() {
            clear
            echo -e "${YELLOW}--- Update ZIVPN Scripts ---${NC}"
            echo -e "${WHITE}This will download the latest versions of the scripts and binary without deleting your user data.${NC}"
            echo -n -e "${PROMPT_COLOR}Are you sure you want to continue? [y/N]:${NC} "
            read confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
              echo -e "${GREEN}Update cancelled.${NC}"
              sleep 2
              return
            fi
            
            echo -e "\n${WHITE}Updating... Please wait.${NC}"
            
            # --- Configuration ---
            REPO_URL="https://raw.githubusercontent.com/nurodinahmad34/vpnku/main"
            # Assuming the release version might get updated, but for now, this is the latest known one.
            RELEASE_URL="https://github.com/nurodinahmad34/vpnku/releases/download/udp-zivpn_1.4.9"
            
            # --- Detect Architecture ---
            ARCH=$(uname -m)
            if [[ "$ARCH" == "x86_64" ]]; then
              BINARY_NAME="udp-zivpn-linux-amd64"
              elif [[ "$ARCH" == "aarch64" ]]; then
                BINARY_NAME="udp-zivpn-linux-arm64"
                else
                echo -e "${RED}Error: Unsupported architecture '$ARCH'. Update aborted.${NC}"
                sleep 3
                return
              fi
              
              # --- Stop Service ---
              echo "Stopping Zivpn service..."
              sudo systemctl stop zivpn.service > /dev/null 2>&1
              
              # --- Update Files ---
              echo "Downloading latest scripts and binary..."
              # Update binary
              sudo wget -q -O /tmp/zivpn-bin-download "$RELEASE_URL/$BINARY_NAME"
              if [ -s /tmp/zivpn-bin-download ] && ! grep -q "<html" /tmp/zivpn-bin-download; then
                sudo mv /tmp/zivpn-bin-download /usr/local/bin/zivpn-bin
                sudo chmod +x /usr/local/bin/zivpn-bin
                else
                echo -e "${RED}Gagal update binary! Versi saat ini dipertahankan.${NC}"
                rm -f /tmp/zivpn-bin-download
              fi
              
              # Update scripts
              sudo wget -q -O /usr/local/bin/zivpn "$REPO_URL/zivpn-menu.sh"
              sudo wget -q -O /usr/local/bin/uninstall.sh "$REPO_URL/uninstall.sh"
              sudo wget -q -O /usr/local/bin/zivpn-cleanup.sh "$REPO_URL/zivpn-cleanup.sh"
              sudo wget -q -O /usr/local/bin/zivpn-autobackup.sh "$REPO_URL/zivpn-autobackup.sh"
              sudo wget -q -O /usr/local/bin/zivpn-monitor.sh "$REPO_URL/zivpn-monitor.sh"
              sudo wget -q -O /etc/profile.d/zivpn-motd.sh "$REPO_URL/zivpn-motd.sh"
              # Update Bot
              sudo wget -q -O /usr/local/bin/zivpn_bot.py "$REPO_URL/zivpn_bot.py"
              
              # --- Set Permissions ---
              echo "Setting permissions..."
              sudo chmod +x /usr/local/bin/zivpn-bin
              sudo chmod +x /usr/local/bin/zivpn
              sudo chmod +x /usr/local/bin/uninstall.sh
              sudo chmod +x /usr/local/bin/zivpn-cleanup.sh
              sudo chmod +x /usr/local/bin/zivpn-autobackup.sh
              sudo chmod +x /usr/local/bin/zivpn-monitor.sh
              sudo chmod +x /etc/profile.d/zivpn-motd.sh
              sudo chmod +x /usr/local/bin/zivpn_bot.py
              
              # --- Restart Service ---
              echo "Restarting Zivpn service..."
              sudo systemctl start zivpn.service > /dev/null 2>&1
              
              echo "Restarting Bot service..."
              # Ensure service exists, if not create it (auto-heal for upgrades)
              if [ ! -f /etc/systemd/system/zivpn-bot.service ]; then
                echo "Creating missing bot service..."
                PYTHON_EXEC="/usr/bin/python3"
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
                sudo systemctl daemon-reload
                sudo systemctl enable zivpn-bot.service
              fi
              sudo systemctl restart zivpn-bot.service > /dev/null 2>&1
              
              echo -e "\n${GREEN}✔ Update complete!${NC}"
              echo -e "${WHITE}The menu will now restart to apply changes.${NC}"
              sleep 3
              
              # Restart the menu script
              exec /usr/local/bin/zivpn
            }
            
            # --- Tampilan Menu Utama (Redesigned) ---
            show_menu() {
              clear
              
              # Get dynamic info
              TOTAL_ACCOUNTS=$(jq 'length' "$USER_DB")
              RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
              CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
              DISK_USAGE=$(df -h / | awk 'NR==2{print $5}')
              
              (
            figlet -f slant "ZIVPN"
            echo "==========================================================="
            echo " Host : $DOMAIN"
            echo " IP   : $IP_ADDRESS"
            echo " ISP  : $ISP"
            echo "==========================================================="
            echo " Info Server: [ CPU: $CPU_USAGE | RAM: $RAM_USAGE | Disk: $DISK_USAGE ]"
            echo "-----------------------------------------------------------"
            echo " Total Account : $TOTAL_ACCOUNTS User"
            echo "-----------------------------------------------------------"
            
            # --- Menu Options ---
            printf " [%02d] Add Regular    | [%02d] Delete Account\n" 1 4
            printf " [%02d] Add Trial      | [%02d] Edit Expiry\n" 2 5
            printf " [%02d] List Accounts  | [%02d] Edit Password\n" 3 6
            echo " ------------------- | --------------------"
            printf " [%02d] VPS Info       |\n" 7
            echo "-----------------------------------------------------------"
            echo " :: PENGATURAN & UTILITAS ::"
            echo "-----------------------------------------------------------"
            printf " [%02d] Backup/Restore | [%02d] Edit Domain\n" 8 11
            printf " [%02d] Bot Settings   | [%02d] Auto Backup\n" 9 12
            printf " [%02d] Theme Settings | [%02d] Uninstall\n" 10 13
            echo " ------------------- | --------------------"
            printf " [%02d] Bandwidth      | [%02d] Cek CPU/RAM\n" 14 15
            printf " [%02d] Update Script  | [%02d] Kelola Layanan\n" 16 17
            echo "-----------------------------------------------------------"
            printf " [%02d] Exit\n" 0
            echo "==========================================================="
            # Panggil fungsi lisensi di dalam subshell agar ikut tema
            display_license_info_content
            ) | eval "$THEME_CMD"
            
            echo -n -e "${PROMPT_COLOR} -> Masukkan pilihan Anda:${NC} "
            read -r choice
          }
          
          
          # Loop utama
          while true; do
            show_menu
            case $choice in
            1) add_account ;;
            2) add_trial_account ;;
            3) list_accounts ;;
            4) delete_account ;;
            5) edit_expiry ;;
            6) edit_password ;;
            7) vps_info ;;
            8) backup_restore ;;
            9) configure_bot_settings ;;
            10) configure_theme ;;
            11) edit_domain ;;
            12) manage_auto_backup ;;
            13) interactive_uninstall ;;
            14) bandwidth_menu ;;
            15) check_cpu_ram ;;
            16) update_script ;;
            17) manage_service ;;
            0) exit 0 ;;
            *)
            echo -e "${RED}Invalid option, please try again.${NC}"
            sleep 2
            ;;
            esac
          done
