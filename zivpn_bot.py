import logging
import json
import os
import subprocess
import time
import asyncio
import datetime
import random
import string
import re
import sys
import html
import zipfile
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, InputFile
from telegram.constants import ParseMode
from telegram.ext import (
ApplicationBuilder,
ContextTypes,
CommandHandler,
CallbackQueryHandler,
MessageHandler,
filters,
ConversationHandler
)
from telegram.error import InvalidToken

# --- Global Configuration & Paths ---
DIR_PATH = "/etc/zivpn"
USER_DB = f"{DIR_PATH}/users.db.json"
CONFIG_FILE = f"{DIR_PATH}/config.json"
BOT_CONFIG = f"{DIR_PATH}/bot_config.sh"
DOMAIN_FILE = f"{DIR_PATH}/domain.conf"
RESELLER_DB = f"{DIR_PATH}/resellers.json"
MEMBER_DB = f"{DIR_PATH}/all_members.json"
SETTINGS_DB = f"{DIR_PATH}/settings.json"
QRIS_IMAGE = f"{DIR_PATH}/qris.jpg"
INCOME_DB = f"{DIR_PATH}/income_log.json"
TRX_COUNTER_FILE = f"{DIR_PATH}/transaction_counter.txt"

# --- CONFIG SCRIPT BACKUP ---
BACKUP_SCRIPT_PATH = "/usr/local/bin/zivpn-autobackup.sh"

# --- Global Variable for Uptime ---
BOT_START_TIME = time.time()

# --- Logging Setup ---
logging.basicConfig(
format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
level=logging.INFO
)
logger = logging.getLogger(__name__)

# --- Conversation States ---
(
SELECTING_ACTION,
GEN_USER, GEN_PASS, GEN_DAYS,
RENEW_USER, RENEW_DAYS,
DEL_USER,
ADD_RESELLER,
DEL_RESELLER,
ADD_BALANCE_ID, ADD_BALANCE_AMOUNT,
SET_PRICE_INPUT,
SET_RESELLER_PRICE_INPUT,
BROADCAST_MSG,
SUB_BALANCE_ID,
SUB_BALANCE_AMOUNT
) = range(16)

# --- Helper Functions ---

LIMIT_DB = f"{DIR_PATH}/trial_limit.json"

def check_trial_limit(user_id):
"""Mengecek apakah user boleh trial atau sudah kena limit."""
# 1. Admin & Reseller selalu UNLIMITED
if is_admin(user_id) or check_is_reseller(user_id):
return True, "unlimited"

# 2. Cek database limit untuk Member biasa
data = load_json(LIMIT_DB) # Format: {"user_id": {"date": "YYYY-MM-DD", "count": 0}}
today = get_indo_date() # Fungsi tanggal WIB yang sudah ada di scriptmu
uid = str(user_id)

user_limit = data.get(uid, {"date": today, "count": 0})

# Jika ganti hari, reset hitungan
if user_limit["date"] != today:
user_limit = {"date": today, "count": 0}

if user_limit["count"] >= 2:
return False, user_limit["count"]

return True, user_limit["count"]

def update_trial_count(user_id):
"""Menambah hitungan trial user."""
if is_admin(user_id) or check_is_reseller(user_id):
return

data = load_json(LIMIT_DB)
today = get_indo_date()
uid = str(user_id)

if uid not in data or data[uid]["date"] != today:
data[uid] = {"date": today, "count": 1}
else:
data[uid]["count"] += 1

save_json(LIMIT_DB, data)

def get_config_value(key):
if not os.path.exists(BOT_CONFIG): return None
try:
with open(BOT_CONFIG, 'r') as f: content = f.read()
pattern = r'^\s*(?:export\s+)?' + re.escape(key) + r'\s*=\s*(["\']?)(.*?)\1\s*$'
match = re.search(pattern, content, re.MULTILINE)
if match: return match.group(2).strip()
except: pass
return None

def load_json(filepath):
if not os.path.exists(filepath): return [] if filepath == USER_DB else {}
try:
with open(filepath, 'r') as f: return json.load(f)
except: return [] if filepath == USER_DB else {}

def save_json(filepath, data):
with open(filepath, 'w') as f: json.dump(data, f, indent=4)

# --- LOGIKA DATABASE & ROLE ---
def load_resellers_data():
if not os.path.exists(RESELLER_DB): return {}
try:
with open(RESELLER_DB, 'r') as f: data = json.load(f)
if isinstance(data, list):
new_data = {}
for r_id in data:
new_data[str(r_id)] = {"balance": 0, "role": "member"}
save_json(RESELLER_DB, new_data)
return new_data
return data
except: return {}

def save_resellers_data(data): save_json(RESELLER_DB, data)

def get_reseller_balance(user_id):
data = load_resellers_data()
return data.get(str(user_id), {}).get("balance", 0)

def update_reseller_balance(user_id, amount):
data = load_resellers_data()
str_id = str(user_id)
if str_id not in data:
data[str_id] = {"balance": 0, "role": "member"}
current = data[str_id].get("balance", 0)
data[str_id]["balance"] = current + amount
save_resellers_data(data)
return data[str_id]["balance"]

def check_is_reseller(user_id):
data = load_resellers_data()
user_data = data.get(str(user_id), {})
return user_data.get("role") == "reseller"

def register_member(user_id):
if not os.path.exists(MEMBER_DB): save_json(MEMBER_DB, [])
members = load_json(MEMBER_DB)
if user_id not in members:
members.append(user_id)
save_json(MEMBER_DB, members)

# --- HARGA ---
def get_account_price():
data = load_json(SETTINGS_DB)
if not isinstance(data, dict): return 3000
return data.get("account_price", 3000)

def get_reseller_price():
data = load_json(SETTINGS_DB)
if not isinstance(data, dict): return 2000
return data.get("reseller_price", 2000)

def set_account_price(price):
data = load_json(SETTINGS_DB)
if not isinstance(data, dict): data = {}
data["account_price"] = int(price)
save_json(SETTINGS_DB, data)

def sync_config():
users = load_json(USER_DB)
passwords = [u['password'] for u in users]
config = {}
if os.path.exists(CONFIG_FILE):
try:
with open(CONFIG_FILE, 'r') as f: config = json.load(f)
except: pass
if 'auth' not in config: config['auth'] = {}
config['auth']['config'] = passwords
config['config'] = passwords
with open(CONFIG_FILE, 'w') as f: json.dump(config, f, indent=4)
subprocess.run(["systemctl", "restart", "zivpn.service"])

def get_public_ip():
try: return subprocess.getoutput("curl -s ifconfig.me")
except: return "127.0.0.1"

def get_domain():
if os.path.exists(DOMAIN_FILE):
with open(DOMAIN_FILE, 'r') as f:
domain = f.read().strip()
if domain: return domain
return get_public_ip()

def read_cpu_stats():
try:
with open('/proc/stat', 'r') as f: line = f.readline()
parts = line.split()
total = sum(int(x) for x in parts[1:])
idle = int(parts[4]) + int(parts[5])
return total, idle
except: return 0, 0

def get_uptime_str():
delta = int(time.time() - BOT_START_TIME)
days = delta // 86400
hours = (delta % 86400) // 3600
minutes = (delta % 3600) // 60
seconds = delta % 60
return f"{days}d {hours}h {minutes}m {seconds}s"

# --- PERBAIKAN WAKTU WIB (FIXED TIMEZONE) ---
def get_now_wib():
# Ambil waktu UTC server, tambah 7 jam manual
return datetime.datetime.utcnow() + datetime.timedelta(hours=7)

def get_indo_date():
now = get_now_wib()
return f"{now.strftime('%d')}.{now.strftime('%m')}.{now.strftime('%Y')}"

def get_time_wib():
return get_now_wib().strftime("%H:%M:%S WIB")

def format_rupiah(value):
try:
return f"Rp {int(value):,.0f}".replace(",", ".")
except:
return str(value)

def is_admin(user_id):
val = get_config_value("CHAT_ID")
return str(user_id) == str(val)

async def check_auth(update: Update, context: ContextTypes.DEFAULT_TYPE):
return True

# --- NOMOR TRANSAKSI ---
def get_next_transaction_id():
current = 1
if os.path.exists(TRX_COUNTER_FILE):
try:
with open(TRX_COUNTER_FILE, 'r') as f:
current = int(f.read().strip())
except:
current = 1
with open(TRX_COUNTER_FILE, 'w') as f:
f.write(str(current + 1))
return current

# --- MANAJEMEN PENDAPATAN ---
def record_income(user_id, username, amount, description=""):
if not os.path.exists(INCOME_DB):
save_json(INCOME_DB, [])
logs = load_json(INCOME_DB)
entry = {
"timestamp": int(time.time()),
"user_id": str(user_id),
"username": str(username),
"amount": int(amount),
"description": description
}
logs.append(entry)
save_json(INCOME_DB, logs)

def get_income_summary(since_timestamp=0, user_id_filter=None):
logs = load_json(INCOME_DB) if os.path.exists(INCOME_DB) else []
filtered_logs = [
log for log in logs
if log["timestamp"] >= since_timestamp
and (user_id_filter is None or log["user_id"] == str(user_id_filter))
]
if not filtered_logs:
return {"total": 0, "count": 0, "avg": 0, "max": 0}
amounts = [log["amount"] for log in filtered_logs]
return {
"total": sum(amounts),
"count": len(amounts),
"avg": sum(amounts) // len(amounts),
"max": max(amounts)
}

# --- GEO & MASKING ---
def get_geo_info():
try:
response = subprocess.getoutput("curl -s http://ip-api.com/json")
data = json.loads(response)
country_code = data.get('countryCode', 'ID')
flags = {'ID': '🇮🇩', 'SG': '🇸🇬', 'MY': '🇲🇾', 'US': '🇺🇸'}
return f"{country_code}-SERVER {flags.get(country_code, '🏳️')}"
except:
return "ID-SERVER 🇮🇩"

def mask_string(text):
if not text or text == "-": return "-"
text = str(text).strip()
if re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$", text):
parts = text.split('.')
return f"{parts[0]}.{parts[1]}.xxx.xxx"
if text.isdigit():
if len(text) > 6: return text[:3] + "xxx" + text[-3:]
else: return "xxx"
if text.startswith("@"):
uname = text[1:]
if len(uname) > 5: return "@" + uname[:3] + "xxx" + uname[-3:]
elif len(uname) > 2: return "@" + uname[:1] + "xxx"
return "@xxx"
if '.' in text and not text.startswith("@"):
if len(text) > 8: return text[:3] + "xxx" + text[-3:]
return "xxx.xxx"
if len(text) > 5: return text[:3] + "xxx" + text[-3:]
elif len(text) > 0: return text[0] + "xxx"
return "xxx"

# --- NOTIFIKASI ESTETIK ---
async def send_log_to_channel(context, user_data, product_data, trx_status, role_user):
channel_ids_raw = get_config_value("CHANNEL_ID")
if not channel_ids_raw or channel_ids_raw.strip() == "": return

chat_ids = [cid.strip() for cid in channel_ids_raw.split(",") if cid.strip()]
if not chat_ids: return

trx_id = f"#{get_next_transaction_id()}"
user_id = user_data['telegram_id']

total_cost = product_data['price']
days = product_data['days']
actual_daily_price = total_cost / days if days > 0 else 0

if role_user == "Admin":
saldo_keluar = "Gratis"
saldo_now = "∞"
price_display = "Gratis"
icon_role = "👑"
else:
saldo_keluar = format_rupiah(total_cost)
saldo_now = format_rupiah(product_data['remaining_balance'])
price_display = format_rupiah(actual_daily_price)
icon_role = "🏆" if role_user == "Reseller" else "👤"

server_loc = get_geo_info()
real_domain = get_domain()
real_ip = get_public_ip()

raw_username = f"@{user_data['telegram_username']}" if user_data['telegram_username'] else "-"
raw_id = str(user_id)
raw_name = user_data['first_name'] or "Member"

masked_username = mask_string(raw_username)
masked_id = mask_string(raw_id)
masked_domain = mask_string(real_domain)
masked_ip = mask_string(real_ip)
masked_name = mask_string(raw_name)

final_username = html.escape(masked_username)
final_name = html.escape(masked_name)

date_now = get_indo_date()
time_now = get_time_wib()

msg = (
"<b>╭────────────────╮</b>\n"
"   📦 <b>TRANSAKSI BERHASIL</b> 📦\n"
"<b>╰────────────────╯</b>\n\n"
f"📒 <b>No Trx</b>       : {trx_id}\n"
f"🌀 <b>Status</b>       : {role_user} {icon_role}\n"
f"👤 <b>Username</b>     : {final_username}\n"
f"🆔 <b>ID</b>           : <code>{masked_id}</code>\n\n"
f"🌐 <b>Server</b>       : {server_loc}\n"
f"🔗 <b>Domain/IP</b>    : <code>{masked_domain}</code> / <code>{masked_ip}</code>\n"
f"🙍 <b>Nama</b>         : {final_name}\n\n"
f"📦 <b>Produk</b>       : AKUN ZIVPN\n"
f"📊 <b>Limit Quota</b>  : Unlimited\n"
f"⏳ <b>Durasi Akun</b>  : {days} Hari\n"
f"💲 <b>Normal/Hari</b>  : {price_display}\n\n"
f"💳 <b>Saldo Keluar</b> : {saldo_keluar}\n"
f"💰 <b>Saldo Now</b>    : {saldo_now}\n\n"
f"📅 <b>Tanggal</b>      : {date_now}\n"
f"⏰ <b>Waktu</b>        : {time_now}\n\n"
"━━━━━━━━━━━━━━\n"
"📝 Catatan: Simpan nomor transaksi untuk support\n"
"━━━━━━━━━━━━━━"
)

for chat_id in chat_ids:
try:
await context.bot.send_message(chat_id=chat_id, text=msg, parse_mode=ParseMode.HTML)
except Exception as e:
logger.error(f"Gagal kirim notifikasi ke {chat_id}: {e}")

# --- FEATURE: BACKUP DATABASE ---
async def action_backup(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
if not is_admin(update.effective_user.id):
await query.message.reply_text("⛔ Hanya admin yang bisa backup.")
return SELECTING_ACTION

if not os.path.exists(BACKUP_SCRIPT_PATH):
await query.edit_message_text(f"❌ Script backup tidak ditemukan di: <code>{BACKUP_SCRIPT_PATH}</code>", parse_mode=ParseMode.HTML)
return SELECTING_ACTION

try:
await query.edit_message_text("⏳ <b>Menjalankan script backup...</b>\nSilakan tunggu file dikirim...", parse_mode=ParseMode.HTML)
process = subprocess.run([BACKUP_SCRIPT_PATH], capture_output=True, text=True)

if process.returncode == 0:
keyboard = [[InlineKeyboardButton("🔙 Menu Utama", callback_data='menu_back_new')]]
await context.bot.send_message(chat_id=update.effective_chat.id, text="✅ <b>Backup script telah dijalankan!</b>", parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup(keyboard))
else:
await context.bot.send_message(chat_id=update.effective_chat.id, text=f"⚠️ Script error:\n<code>{html.escape(process.stderr)}</code>", parse_mode=ParseMode.HTML)
except Exception as e:
await query.message.reply_text(f"❌ Gagal menjalankan script: {e}")

return SELECTING_ACTION

# --- Main Menu Display ---
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE, force_new=False):
if not await check_auth(update, context): return
register_member(update.effective_user.id)

user = update.effective_user
user_id = str(user.id)
safe_username = f"@{user.username}" if user.username else html.escape(user.first_name)

saldo = 0
status_user = "Member"
if is_admin(user_id):
status_user = "Admin"
saldo = "∞ (Unlimited)"
else:
balance = get_reseller_balance(user_id)
if check_is_reseller(user_id): status_user = "Reseller"
else: status_user = "Member"
saldo = format_rupiah(balance) if balance > 0 else "Rp 0"

users_db = load_json(USER_DB)
total_users = len(users_db)
uptime = get_uptime_str()
waktu_skr = get_time_wib()
tanggal_skr = get_indo_date()
current_price = format_rupiah(get_account_price())
reseller_price = format_rupiah(get_reseller_price())

# --- PERBAIKAN STATISTIK (WIB) ---
now_wib = get_now_wib()

# Hitung batas waktu 00:00 WIB Hari Ini (dalam timestamp UTC)
# Trik: Ambil 00:00 WIB, kurangi 7 jam = UTC timestamp start
today_wib_midnight = now_wib.replace(hour=0, minute=0, second=0, microsecond=0)
start_of_day = (today_wib_midnight - datetime.timedelta(hours=7)).timestamp()

# Hitung batas waktu Awal Minggu WIB
start_week_wib = (now_wib - datetime.timedelta(days=now_wib.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
start_of_week = (start_week_wib - datetime.timedelta(hours=7)).timestamp()

stat_daily = 0
stat_weekly = 0
for u in users_db:
created_at = u.get('created_at', 0)
if created_at >= start_of_day: stat_daily += 1
if created_at >= start_of_week: stat_weekly += 1
# ---------------------------------

text = (
f"📦━━━━━━━━━━━━━━━━━━━📦\n"
f"      ✨ <b>ZIVPN ORDER</b> ✨\n"
f"📦━━━━━━━━━━━━━━━━━━━📦\n\n"
f"selamat datang di ZIVPN ORDER 💎\n"
f"nikmati pengalaman membeli akun vpn tercepat, aman, dan otomatis 🚀\n\n"
f"🧭 <b>informasi akun</b>\n"
f"┏━━━━━━━━━━━━━━━━━━━━━┓\n"
f"┃ 💰 saldo: {saldo}\n"
f"┃ 👤 status: {status_user}\n"
f"┃ 🌐 username: {safe_username}\n"
f"┃ 🆔 id pengguna: <code>{user_id}</code>\n"
f"┃ ⏱️ bot aktif: {uptime}\n"
f"┗━━━━━━━━━━━━━━━━━━━━━┛\n\n"
f"🎯 <b>fitur & keunggulan</b>\n"
f"┏━━━━━━━━━━━━━━━━━━━━━┓\n"
f"┃ 🏷️ harga member: {current_price} / Hari\n"
f"┃ 🏷️ harga reseller: {reseller_price} / Hari\n"
f"┃ 🔐 support domain & ip\n"
f"┃ ⚡ sistem cepat & stabil\n"
f"┗━━━━━━━━━━━━━━━━━━━━━┛\n\n"
f"🌍 <b>statistik global</b>\n"
f"┏━━━━━━━━━━━━━━━━━━━━━┓\n"
f"┃ 📆 hari ini: {stat_daily} akun\n"
f"┃ 📅 minggu ini: {stat_weekly} akun\n"
f"┃ 🗓️ total user: {total_users} akun\n"
f"┗━━━━━━━━━━━━━━━━━━━━━┛\n\n"
f"🕒 <b>waktu & server</b>\n"
f"┏━━━━━━━━━━━━━━━━━━━━━┓\n"
f"┃ 🧭 waktu: {waktu_skr}\n"
f"┃ 📅 tanggal: {tanggal_skr}\n"
f"┃ 🖥️ server: online | 👥 user: {total_users}\n"
f"┗━━━━━━━━━━━━━━━━━━━━━┛\n\n"
f"☎️ <b>hubungi admin</b>\n"
f"╰📨 @Dark_System2x\n\n"
f"📦━━━━━━━━━━━━━━━━━━━📦\n"
f"     🌐 dikelola oleh 𝘿𝙚𝙠𝙞\_𝙣𝙞𝙨𝙬𝙖𝙧𝙖\n"
f"📦━━━━━━━━━━━━━━━━━━━📦"
)

buttons = [
[InlineKeyboardButton("➕ Generate Account", callback_data='menu_generate'), InlineKeyboardButton("⏳ Trial Account", callback_data='menu_trial')],
[InlineKeyboardButton("🔄 Renew Account", callback_data='menu_renew'), InlineKeyboardButton("🗑 Delete Account", callback_data='menu_delete')],
[InlineKeyboardButton("📊 Check Users", callback_data='menu_check'), InlineKeyboardButton("🖥 Server Status", callback_data='menu_status')],
[InlineKeyboardButton("💳 Topup Saldo", callback_data='menu_topup')]
]
if is_admin(user_id):
buttons.append([InlineKeyboardButton("👥 Manage Resellers & Saldo", callback_data='menu_resellers')])
buttons.append([InlineKeyboardButton("📢 Broadcast", callback_data='menu_broadcast'), InlineKeyboardButton("💾 Backup Data", callback_data='menu_backup')])
buttons.append([InlineKeyboardButton("📈 Laporan Pendapatan", callback_data='menu_income')])

reply_markup = InlineKeyboardMarkup(buttons)
if update.callback_query:
await update.callback_query.answer()
if force_new:
await context.bot.send_message(chat_id=update.effective_chat.id, text=text, reply_markup=reply_markup, parse_mode=ParseMode.HTML)
else:
await update.callback_query.edit_message_text(text=text, reply_markup=reply_markup, parse_mode=ParseMode.HTML)
else:
await update.message.reply_text(text, reply_markup=reply_markup, parse_mode=ParseMode.HTML)
return SELECTING_ACTION

# --- LAPORAN PENDAPATAN (FIXED WIB) ---
def ascii_bar(value, max_val, width=10):
if max_val == 0: return "░" * width
filled = int((value / max_val) * width)
return "█" * filled + "░" * (width - filled)

async def action_income_report(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
if not is_admin(update.effective_user.id):
await query.message.reply_text("⛔ Hanya admin yang bisa mengakses.")
return SELECTING_ACTION

# LOGIKA WAKTU WIB
now_wib = get_now_wib()

today_wib = now_wib.replace(hour=0, minute=0, second=0, microsecond=0)
today_start = (today_wib - datetime.timedelta(hours=7)).timestamp()

week_wib = (now_wib - datetime.timedelta(days=now_wib.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
week_start = (week_wib - datetime.timedelta(hours=7)).timestamp()

month_wib = now_wib.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
month_start = (month_wib - datetime.timedelta(hours=7)).timestamp()

all_data = get_income_summary(0)
today_data = get_income_summary(today_start)
week_data = get_income_summary(week_start)
month_data = get_income_summary(month_start)

max_income = max(week_data["total"], month_data["total"], 1)
bar_week = ascii_bar(week_data["total"], max_income)
bar_month = ascii_bar(month_data["total"], max_income)

has_reseller_transactions = False
if os.path.exists(INCOME_DB):
logs = load_json(INCOME_DB)
resellers = load_resellers_data()
for log in logs:
if log["user_id"] in resellers:
has_reseller_transactions = True
break

msg = (
"📈 <b>LAPORAN PENDAPATAN LENGKAP (WIB)</b>\n\n"
f"📆 <b>Hari Ini</b>\n"
f"   💰 Total: {format_rupiah(today_data['total'])}\n"
f"   🧾 Transaksi: {today_data['count']}\n\n"
f"📅 <b>Minggu Ini</b>\n"
f"   💰 Total: {format_rupiah(week_data['total'])}\n"
f"   🧾 Transaksi: {week_data['count']}\n"
f"   📊 Grafik: <code>{bar_week}</code>\n\n"
f"🗓️ <b>Bulan Ini</b>\n"
f"   💰 Total: {format_rupiah(month_data['total'])}\n"
f"   🧾 Transaksi: {month_data['count']}\n"
f"   📊 Grafik: <code>{bar_month}</code>\n\n"
f"💼 <b>Seumur Hidup</b>\n"
f"   💰 Total: {format_rupiah(all_data['total'])}\n"
f"   🧾 Transaksi: {all_data['count']}\n"
f"   📈 Rata-rata: {format_rupiah(all_data['avg'])}\n"
f"   🥇 Transaksi Terbesar: {format_rupiah(all_data['max'])}\n\n"
f"📁 File: <code>{INCOME_DB}</code>"
)

buttons = [[InlineKeyboardButton("🔙 Kembali", callback_data='menu_back')]]
if has_reseller_transactions:
buttons.insert(0, [InlineKeyboardButton("🔍 Filter per Reseller", callback_data='income_filter_reseller')])

await query.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup(buttons))
return SELECTING_ACTION

async def action_income_filter_reseller(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()

resellers = load_resellers_data()
logs = load_json(INCOME_DB) if os.path.exists(INCOME_DB) else []
seen = set()
reseller_buttons = []

for log in logs:
uid = log["user_id"]
if uid not in seen and uid in resellers:
try:
chat = await context.bot.get_chat(uid)
name = html.escape(chat.first_name)
reseller_buttons.append([InlineKeyboardButton(f"{name} (ID: {uid})", callback_data=f'income_reseller_{uid}')])
seen.add(uid)
except:
reseller_buttons.append([InlineKeyboardButton(f"ID {uid}", callback_data=f'income_reseller_{uid}')])
seen.add(uid)

if not reseller_buttons:
await query.edit_message_text("🔍 Tidak ada reseller dengan transaksi.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali ke Laporan", callback_data='menu_income')]]))
return SELECTING_ACTION

reseller_buttons.append([InlineKeyboardButton("🔚 Batal", callback_data='menu_income')])
await query.edit_message_text("🧑‍💼 Pilih reseller untuk melihat laporan:", reply_markup=InlineKeyboardMarkup(reseller_buttons))
return SELECTING_ACTION

async def action_income_view_reseller(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
user_id = query.data.split('_')[-1]

try: chat = await context.bot.get_chat(user_id); name = html.escape(chat.first_name)
except: name = f"ID {user_id}"

# LOGIKA WIB
now_wib = get_now_wib()
today_wib = now_wib.replace(hour=0, minute=0, second=0, microsecond=0)
today_start = (today_wib - datetime.timedelta(hours=7)).timestamp()
week_wib = (now_wib - datetime.timedelta(days=now_wib.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
week_start = (week_wib - datetime.timedelta(hours=7)).timestamp()
month_wib = now_wib.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
month_start = (month_wib - datetime.timedelta(hours=7)).timestamp()

today_data = get_income_summary(today_start, user_id)
week_data = get_income_summary(week_start, user_id)
month_data = get_income_summary(month_start, user_id)
all_data = get_income_summary(0, user_id)

msg = (
f"🧑‍💼 <b>Laporan: {name}</b>\n"
f"🆔 ID: <code>{user_id}</code>\n\n"
f"📆 Hari Ini: {format_rupiah(today_data['total'])} ({today_data['count']} trxs)\n"
f"📅 Minggu Ini: {format_rupiah(week_data['total'])} ({week_data['count']} trxs)\n"
f"🗓️ Bulan Ini: {format_rupiah(month_data['total'])} ({month_data['count']} trxs)\n"
f"💼 Total: {format_rupiah(all_data['total'])} ({all_data['count']} trxs)\n"
f"📈 Rata-rata: {format_rupiah(all_data['avg'])}"
)

await query.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("⬅️ Kembali ke Daftar", callback_data='income_filter_reseller')]]))
return SELECTING_ACTION

# --- Fungsi Lainnya ---
async def action_topup(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
admin_uname = "@Dark_System2x"
msg_text = (
"💳 <b>Topup Saldo</b>\n\nSilakan scan QRIS di atas untuk melakukan pembayaran.\n\n"
"📝 <b>Instruksi:</b>\n1. Scan QRIS dan transfer sesuai nominal yang diinginkan.\n"
f"2. Screenshot bukti pembayaran.\n3. Kirim bukti ke Admin: {admin_uname}\n"
f"4. Sertakan ID Anda saat konfirmasi.\n\n🆔 ID Anda: <code>{update.effective_user.id}</code>"
)
if os.path.exists(QRIS_IMAGE):
await context.bot.send_photo(chat_id=update.effective_chat.id, photo=open(QRIS_IMAGE, 'rb'), caption=msg_text, parse_mode=ParseMode.HTML)
else:
await context.bot.send_message(chat_id=update.effective_chat.id, text="⚠️ <b>Info:</b> Foto QRIS belum disetting.\n\n" + msg_text, parse_mode=ParseMode.HTML)
keyboard = [[InlineKeyboardButton("🔙 Menu Utama", callback_data='menu_back_new')]]
await context.bot.send_message(chat_id=update.effective_chat.id, text="Klik tombol di bawah untuk kembali:", reply_markup=InlineKeyboardMarkup(keyboard))
return SELECTING_ACTION

async def reseller_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
if not is_admin(update.effective_user.id):
await query.message.reply_text("⛔ Admin only area.")
return SELECTING_ACTION
acc_price = format_rupiah(get_account_price())
res_price = format_rupiah(get_reseller_price())
text = f"👥 <b>Manajemen Saldo & Member</b>\n\nHarga Member: <code>{acc_price}</code> / Hari\nHarga Reseller: <code>{res_price}</code> / Hari"
buttons = [
[InlineKeyboardButton("➕ Tambah Reseller", callback_data='reseller_add'), InlineKeyboardButton("➖ Hapus Reseller", callback_data='reseller_del')],
[InlineKeyboardButton("💰 Isi Saldo", callback_data='reseller_balance_add'),
InlineKeyboardButton("💸 Kurang Saldo", callback_data='reseller_balance_sub')],
[InlineKeyboardButton("🏷️ Set Harga Member", callback_data='reseller_set_price')],
[InlineKeyboardButton("🏷️ Set Harga Reseller", callback_data='reseller_set_reseller_price')],
[InlineKeyboardButton("📜 List Saldo Member", callback_data='reseller_list')],
[InlineKeyboardButton("🔙 Kembali", callback_data='menu_back')]
]
await query.edit_message_text(text=text, reply_markup=InlineKeyboardMarkup(buttons), parse_mode=ParseMode.HTML)
return SELECTING_ACTION

async def action_list_resellers(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()

try: await query.edit_message_text("⏳ <b>Mengambil data database...</b>\nMohon tunggu...", parse_mode=ParseMode.HTML)
except: pass

resellers = load_resellers_data()
msg = f"📋 <b>Daftar Saldo Member ({len(resellers)})</b>\n\n"

if not resellers: msg += "Belum ada data."
else:
sorted_ids = sorted(resellers.keys(), key=lambda x: resellers[x].get('balance', 0), reverse=True)
for r_id in sorted_ids:
data = resellers[r_id]
balance = format_rupiah(data.get('balance', 0))
role_type = data.get('role', 'member')
role_tag = "👑 Reseller" if role_type == 'reseller' else "👤 Member"

try:
chat = await context.bot.get_chat(chat_id=r_id)
name = html.escape(chat.first_name)
user_display = f"@{chat.username}" if chat.username else "<i>(No Username)</i>"
msg += f"{role_tag} | <b>{name}</b>\n🆔 <code>{r_id}</code>\n👤 {user_display}\n💰 {balance}\n━━━━━━━━━━━━\n"
except:
msg += f"{role_tag} | <i>(User Not Found)</i>\n🆔 <code>{r_id}</code>\n💰 {balance}\n━━━━━━━━━━━━\n"
await asyncio.sleep(0.05)

keyboard = [[InlineKeyboardButton("🔙 Back", callback_data='menu_resellers')]]
if len(msg) > 4000: msg = msg[:4000] + "\n\n<i>...list terpotong</i>"
await query.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup(keyboard))
return SELECTING_ACTION

async def start_add_balance(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
await query.edit_message_text("💰 <b>Isi Saldo Member</b>\nMasukkan ID Telegram Member/Reseller:", parse_mode=ParseMode.HTML)
return ADD_BALANCE_ID

async def add_balance_id_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
r_id = update.message.text.strip()
context.user_data['bal_id'] = r_id
await update.message.reply_text(f"✅ Target ID: <code>{r_id}</code>\nMasukkan Nominal Saldo (tanpa titik/koma):", parse_mode=ParseMode.HTML)
return ADD_BALANCE_AMOUNT

async def add_balance_amount_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
try: amount = int(update.message.text.strip())
except ValueError: return ADD_BALANCE_AMOUNT
r_id = context.user_data['bal_id']
new_bal = update_reseller_balance(r_id, amount)
await update.message.reply_text(f"✅ Berhasil.\n💰 Saldo Sekarang: <code>{format_rupiah(new_bal)}</code>", parse_mode=ParseMode.HTML)
keyboard = [[InlineKeyboardButton("🔙 Menu Reseller", callback_data='menu_resellers')]]
await update.message.reply_text("Kembali:", reply_markup=InlineKeyboardMarkup(keyboard))
return SELECTING_ACTION

async def start_set_price(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
curr = format_rupiah(get_account_price())
await query.edit_message_text(f"🏷️ <b>Set Harga Member per Hari</b>\nHarga saat ini: <code>{curr}</code> / Hari\n\nMasukkan harga baru (angka saja):", parse_mode=ParseMode.HTML)
return SET_PRICE_INPUT

async def set_price_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
try: price = int(update.message.text.strip())
except ValueError: return SET_PRICE_INPUT
set_account_price(price)
await update.message.reply_text(f"✅ Harga member diubah menjadi: <code>{format_rupiah(price)}</code>", parse_mode=ParseMode.HTML)
keyboard = [[InlineKeyboardButton("🔙 Menu Reseller", callback_data='menu_resellers')]]
await update.message.reply_text("Kembali:", reply_markup=InlineKeyboardMarkup(keyboard))
return SELECTING_ACTION

async def start_set_reseller_price(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
curr = format_rupiah(get_reseller_price())
await query.edit_message_text(f"🏷️ <b>Set Harga Reseller per Hari</b>\nHarga saat ini: <code>{curr}</code> / Hari\n\nMasukkan harga baru (angka saja):", parse_mode=ParseMode.HTML)
return SET_RESELLER_PRICE_INPUT

async def set_reseller_price_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
try: price = int(update.message.text.strip())
except ValueError: return SET_RESELLER_PRICE_INPUT
data = load_json(SETTINGS_DB)
if not isinstance(data, dict): data = {}
data["reseller_price"] = int(price)
save_json(SETTINGS_DB, data)
await update.message.reply_text(f"✅ Harga reseller diubah menjadi: <code>{format_rupiah(price)}</code>", parse_mode=ParseMode.HTML)
keyboard = [[InlineKeyboardButton("🔙 Menu Reseller", callback_data='menu_resellers')]]
await update.message.reply_text("Kembali:", reply_markup=InlineKeyboardMarkup(keyboard))
return SELECTING_ACTION

# --- FUNGSI KURANG SALDO ---
async def start_sub_balance(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
if not is_admin(update.effective_user.id): return
await query.edit_message_text("➖ <b>Kurangi Saldo Member</b>\nMasukkan ID Telegram Member:", parse_mode=ParseMode.HTML)
return SUB_BALANCE_ID

async def sub_balance_id_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
r_id = update.message.text.strip()
context.user_data['sub_bal_id'] = r_id
await update.message.reply_text(f"✅ Target ID: <code>{r_id}</code>\nMasukkan Nominal yang akan DIKURANGI:", parse_mode=ParseMode.HTML)
return SUB_BALANCE_AMOUNT

async def sub_balance_amount_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
try: amount = int(update.message.text.strip())
except: return SUB_BALANCE_AMOUNT
r_id = context.user_data['sub_bal_id']
new_bal = update_reseller_balance(r_id, -amount)
await update.message.reply_text(f"✅ Berhasil dikurangi {format_rupiah(amount)}.\n💰 Saldo Sekarang: <code>{format_rupiah(new_bal)}</code>", parse_mode=ParseMode.HTML)
await update.message.reply_text("Kembali:", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu Reseller", callback_data='menu_resellers')]]))
return SELECTING_ACTION

# --- Generate Account ---
async def start_gen(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
user_id = update.effective_user.id
if not is_admin(user_id):
is_reseller = check_is_reseller(user_id)
price_per_day = get_reseller_price() if is_reseller else get_account_price()
balance = get_reseller_balance(user_id)
if balance < price_per_day:
await query.edit_message_text(
f"🚫 <b>Saldo Tidak Cukup!</b>\nSaldo: <code>{format_rupiah(balance)}</code>\nHarga Per Hari: <code>{format_rupiah(price_per_day)}</code>",
parse_mode=ParseMode.HTML,
reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("💳 Topup", callback_data='menu_topup'), InlineKeyboardButton("🔙 Kembali", callback_data='menu_back')]])
)
return SELECTING_ACTION
await query.edit_message_text("📝 <b>New Account</b>\nMasukkan Username:", parse_mode=ParseMode.HTML)
return GEN_USER

async def gen_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
username = update.message.text.strip()
users = load_json(USER_DB)
if any(u['username'] == username for u in users):
await update.message.reply_text("❌ Username already exists. Try another:")
return GEN_USER
context.user_data['gen_username'] = username
await update.message.reply_text("🔑 Masukkan Password:")
return GEN_PASS

async def gen_pass(update: Update, context: ContextTypes.DEFAULT_TYPE):
context.user_data['gen_password'] = update.message.text.strip()
await update.message.reply_text("📅 Masukkan Durasi (hari):")
return GEN_DAYS

async def gen_days(update: Update, context: ContextTypes.DEFAULT_TYPE):
user_id = update.effective_user.id
try: days = int(update.message.text.strip())
except ValueError: return GEN_DAYS

is_adm = is_admin(user_id)
is_reseller = check_is_reseller(user_id)

if is_adm: price_per_day = 0; role = "Admin"
elif is_reseller: price_per_day = get_reseller_price(); role = "Reseller"
else: price_per_day = get_account_price(); role = "Member"

total_cost = price_per_day * days

if not is_adm:
balance = get_reseller_balance(user_id)
if balance < total_cost:
await update.message.reply_text(f"🚫 Saldo tidak cukup!\nTotal Harga: <code>{format_rupiah(total_cost)}</code>\nSaldo Anda: <code>{format_rupiah(balance)}</code>", parse_mode=ParseMode.HTML)
return SELECTING_ACTION

username = context.user_data['gen_username']
password = context.user_data['gen_password']
users = load_json(USER_DB)
expiry_timestamp = int(time.time()) + (days * 86400)
users.append({"username": username, "password": password, "expiry_timestamp": expiry_timestamp, "created_at": int(time.time())})
save_json(USER_DB, users)
sync_config()

if not is_adm:
record_income(user_id, update.effective_user.username or update.effective_user.first_name, total_cost, f"Buat akun {username} ({days} hari)")

new_bal = 0
if not is_adm:
new_bal = update_reseller_balance(user_id, -total_cost)
msg_price = f"\n💰 Total Bayar: <code>{format_rupiah(total_cost)}</code>\n💳 Sisa Saldo: <code>{format_rupiah(new_bal)}</code>"
else:
new_bal = "Unlimited"
msg_price = "\n💰 Total Bayar: Gratis (Admin)\n💳 Sisa Saldo: ∞"

domain = get_domain()
public_ip = get_public_ip()
expiry_date = datetime.datetime.fromtimestamp(expiry_timestamp).strftime('%d-%m-%Y')

msg = (f"────────────────────\n    ☘ NEW ACCOUNT DETAIL ☘\n────────────────────\nUser      : <code>{username}</code>\nPassword  : <code>{password}</code>\nHOST      : <code>{domain}</code>\nIP VPS    : <code>{public_ip}</code>\nEXP       : <code>{expiry_date}</code> / <code>{days}</code> HARI\n────────────────────\n{msg_price}\nNote: Auto notif from your script...")
keyboard = [[InlineKeyboardButton("🔙 Main Menu", callback_data='menu_back_new')]]
await update.message.reply_text(msg, parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup(keyboard))

u_info = {"telegram_username": update.effective_user.username if update.effective_user.username else "-", "telegram_id": user_id, "first_name": update.effective_user.first_name}
p_info = {"name": "AKUN ZIVPN", "type": "Buat Akun", "days": days, "price": total_cost, "remaining_balance": new_bal}
await send_log_to_channel(context, u_info, p_info, "SUCCESS", role)
return SELECTING_ACTION

# --- Trial Account ---
async def action_trial(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
user_id = update.effective_user.id

# --- CEK LIMIT ---
allowed, status = check_trial_limit(user_id)
if not allowed:
await query.edit_message_text(
f"🚫 <b>LIMIT TRIAL TERCAPAI!</b>\n\nJatah trial harian Anda (2x) sudah habis.\nSilakan coba lagi besok atau beli saldo untuk membuat akun premium.",
parse_mode=ParseMode.HTML,
reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("💳 Topup Saldo", callback_data='menu_topup')], [InlineKeyboardButton("🔙 Kembali", callback_data='menu_back')]])
)
return SELECTING_ACTION
# -----------------

username = "trial" + ''.join(random.choices(string.digits, k=4))
password = ''.join(random.choices(string.ascii_letters + string.digits, k=8))
minutes = 60
users = load_json(USER_DB)
existing = [u['username'] for u in users]
while username in existing:
username = "trial" + ''.join(random.choices(string.digits, k=4))

expiry = int(time.time()) + (minutes * 60)
users.append({"username": username, "password": password, "expiry_timestamp": expiry, "created_at": int(time.time())})
save_json(USER_DB, users)
sync_config()

# --- UPDATE LIMIT SETELAH BERHASIL ---
update_trial_count(user_id)
# -------------------------------------

domain = get_domain()
public_ip = get_public_ip()

info_limit = "♾ Unlimited (Reseller/Admin)" if status == "unlimited" else f"{status + 1}/2 Hari ini"

msg = (
f"────────────────────\n"
f"    ☘ NEW TRIAL ACCOUNT ☘\n"
f"────────────────────\n"
f"User      : <code>{username}</code>\n"
f"Password  : <code>{password}</code>\n"
f"HOST      : <code>{domain}</code>\n"
f"IP VPS    : <code>{public_ip}</code>\n"
f"EXP       : {minutes} MENIT\n"
f"────────────────────\n"
f"📊 Kuota Trial: {info_limit}\n"
f"────────────────────"
)
keyboard = [[InlineKeyboardButton("🔙 Main Menu", callback_data='menu_back_new')]]
await query.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup(keyboard))
return SELECTING_ACTION

# --- Server Status ---
async def action_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
ram = subprocess.getoutput("free -m | awk 'NR==2{printf \"%.2f%%\", $3*100/$2 }'")
t1, i1 = read_cpu_stats()
await asyncio.sleep(0.5)
t2, i2 = read_cpu_stats()
delta_total, delta_idle = t2 - t1, i2 - i1
cpu = f"{100 * (1 - delta_idle / delta_total):.2f}%" if delta_total > 0 else "0.00%"
uptime = subprocess.getoutput("uptime -p")
total_users = len(load_json(USER_DB))
msg = f"🖥 <b>Server Status</b>\n🧠 RAM: <code>{ram}</code>\n⚡ CPU: <code>{cpu}</code>\n⏱ Uptime: <code>{uptime}</code>\n👥 Total Users: <code>{total_users}</code>"
keyboard = [[InlineKeyboardButton("🔙 Back", callback_data='menu_back')]]
await query.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup(keyboard))
return SELECTING_ACTION

# --- Check Users ---
async def action_check(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
users = load_json(USER_DB)
msg = "No users found." if not users else "📜 <b>User List</b>\n"
now = int(time.time())
for u in users:
exp = u.get('expiry_timestamp', 0)
days = (exp - now) // 86400
if days < 0: status, time_str = "🔴", "Expired"
elif days == 0: status, time_str = "🟡", f"{(exp - now) // 60}m"
else: status, time_str = "🟢", f"{days}d"
msg += f"{status} <code>{u['username']}</code> ({time_str})\n"
keyboard = [[InlineKeyboardButton("🔙 Back", callback_data='menu_back')]]
if len(msg) > 4000: msg = msg[:4000] + "..."
await query.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup(keyboard))
return SELECTING_ACTION

# --- Renew Account ---
async def start_renew(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
await query.edit_message_text("🔄 <b>Renew Account</b>\nMasukkan Username:", parse_mode=ParseMode.HTML)
return RENEW_USER

async def renew_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
context.user_data['renew_username'] = update.message.text.strip()
await update.message.reply_text("📅 Tambah durasi (hari):")
return RENEW_DAYS

async def renew_days(update: Update, context: ContextTypes.DEFAULT_TYPE):
user_id = update.effective_user.id
try: days = int(update.message.text.strip())
except: return RENEW_DAYS

is_adm = is_admin(user_id)
is_reseller = check_is_reseller(user_id)

if is_adm: price_per_day = 0; role = "Admin"
elif is_reseller: price_per_day = get_reseller_price(); role = "Reseller"
else: price_per_day = get_account_price(); role = "Member"

total_cost = price_per_day * days

if not is_adm:
balance = get_reseller_balance(user_id)
if balance < total_cost:
await update.message.reply_text(f"🚫 Saldo tidak cukup!\nTotal Harga: <code>{format_rupiah(total_cost)}</code>\nSaldo Anda: <code>{format_rupiah(balance)}</code>", parse_mode=ParseMode.HTML)
return SELECTING_ACTION

username = context.user_data['renew_username']
users = load_json(USER_DB)
now = int(time.time())
target_user = None

for u in users:
if u['username'] == username:
target_user = u
curr = u.get('expiry_timestamp', 0)
start_time = curr if curr > now else now
new_expiry = start_time + (days * 86400)
u['expiry_timestamp'] = new_expiry
break

if not target_user:
await update.message.reply_text("❌ Username tidak ditemukan.")
return SELECTING_ACTION

save_json(USER_DB, users)
sync_config()

if not is_adm:
record_income(user_id, update.effective_user.username or update.effective_user.first_name, total_cost, f"Perpanjang {username} ({days} hari)")

new_bal = 0
if not is_adm:
new_bal = update_reseller_balance(user_id, -total_cost)
msg_price = f"\n💰 Total Bayar: <code>{format_rupiah(total_cost)}</code>\n💳 Sisa Saldo: <code>{format_rupiah(new_bal)}</code>"
else:
new_bal = "Unlimited"
msg_price = "\n💰 Total Bayar: Gratis (Admin)\n💳 Sisa Saldo: ∞"

domain = get_domain()
public_ip = get_public_ip()
expiry_date = datetime.datetime.fromtimestamp(new_expiry).strftime('%d-%m-%Y')
user_pass = target_user.get('password', '****')

msg = (f"────────────────────\n   ☘ RENEW ACCOUNT DETAIL ☘\n────────────────────\nUser      : <code>{username}</code>\nPassword  : <code>{user_pass}</code>\nHOST      : <code>{domain}</code>\nIP VPS    : <code>{public_ip}</code>\nEXP       : <code>{expiry_date}</code> / <code>{days}</code> HARI\n────────────────────\n{msg_price}\nNote: Auto notif from your script...")
await update.message.reply_text(msg, parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Main Menu", callback_data='menu_back_new')]]))

u_info = {"telegram_username": update.effective_user.username if update.effective_user.username else "-", "telegram_id": user_id, "first_name": update.effective_user.first_name}
p_info = {"name": "AKUN ZIVPN (Renew)", "type": "Perpanjang", "days": days, "price": total_cost, "remaining_balance": new_bal}
await send_log_to_channel(context, u_info, p_info, "SUCCESS", role)
return SELECTING_ACTION

# --- Delete Account (FIXED PERMISSION) ---
async def start_del(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()

user_id = update.effective_user.id

# --- LOGIC KEAMANAN TAMBAHAN ---
if not is_admin(user_id) and not check_is_reseller(user_id):
await query.edit_message_text(
"⛔ <b>Akses Ditolak!</b>\nFitur ini hanya untuk Admin dan Reseller.",
parse_mode=ParseMode.HTML,
reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data='menu_back')]])
)
return SELECTING_ACTION
# -------------------------------

await query.edit_message_text("🗑 <b>Delete Account</b>\nMasukkan Username:", parse_mode=ParseMode.HTML)
return DEL_USER

async def del_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
user_id = update.effective_user.id

# --- LOGIC KEAMANAN LAPIS KEDUA ---
if not is_admin(user_id) and not check_is_reseller(user_id):
await update.message.reply_text("⛔ Anda tidak memiliki izin.")
return SELECTING_ACTION
# ----------------------------------

username = update.message.text.strip()
users = load_json(USER_DB)
new_users = [u for u in users if u['username'] != username]
if len(new_users) == len(users):
await update.message.reply_text("❌ Username not found.")
return DEL_USER
save_json(USER_DB, new_users)
sync_config()
await update.message.reply_text(f"✅ User <code>{username}</code> deleted.", parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Main Menu", callback_data='menu_back_new')]]))
return SELECTING_ACTION

# --- Manage Reseller ---
async def start_add_reseller(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
await query.edit_message_text("➕ <b>Add Reseller</b>\nMasukkan Telegram ID (angka):", parse_mode=ParseMode.HTML)
return ADD_RESELLER

async def add_reseller_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
r_id = update.message.text.strip()
data = load_resellers_data()
if r_id in data:
data[r_id]["role"] = "reseller"
save_resellers_data(data)
await update.message.reply_text(f"✅ User <code>{r_id}</code> telah di-upgrade menjadi Reseller.", parse_mode=ParseMode.HTML)
else:
data[r_id] = {"balance": 0, "role": "reseller"}
save_resellers_data(data)
await update.message.reply_text(f"✅ Reseller baru <code>{r_id}</code> ditambahkan.", parse_mode=ParseMode.HTML)
await update.message.reply_text("Kembali:", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu Reseller", callback_data='menu_resellers')]]))
return SELECTING_ACTION

async def start_del_reseller(update: Update, context: ContextTypes.DEFAULT_TYPE):
query = update.callback_query
await query.answer()
await query.edit_message_text("➖ <b>Hapus/Downgrade Reseller</b>\nMasukkan Telegram ID:", parse_mode=ParseMode.HTML)
return DEL_RESELLER

async def del_reseller_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
r_id = update.message.text.strip()
data = load_resellers_data()
if r_id in data:
data[r_id]["role"] = "member"
save_resellers_data(data)
await update.message.reply_text(f"✅ Status Reseller <code>{r_id}</code> dicabut (menjadi Member).", parse_mode=ParseMode.HTML)
else: await update.message.reply_text("❌ Tidak ditemukan.")
await update.message.reply_text("Kembali:", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu Reseller", callback_data='menu_resellers')]]))
return SELECTING_ACTION

# --- Broadcast ---
async def start_broadcast(update: Update, context: ContextTypes.DEFAULT_TYPE):
await update.callback_query.edit_message_text("📢 <b>Broadcast Message</b>\n\nSilakan kirim pesan (Teks/Gambar) yang ingin Anda sebarkan ke semua member:", parse_mode=ParseMode.HTML)
return BROADCAST_MSG

async def process_broadcast(update: Update, context: ContextTypes.DEFAULT_TYPE):
members = load_json(MEMBER_DB)
count = 0
await update.message.reply_text("⏳ Sedang mengirim broadcast...")
for uid in members:
try:
await update.message.copy(chat_id=uid)
count += 1
except: pass
await asyncio.sleep(0.1)
await update.message.reply_text(f"✅ <b>Broadcast Selesai</b>\n\nPesan berhasil terkirim ke: {count} member.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data='menu_back_new')]]), parse_mode=ParseMode.HTML)
return SELECTING_ACTION

# --- Navigation ---
async def back_to_main(update: Update, context: ContextTypes.DEFAULT_TYPE): return await start(update, context)
async def back_to_main_new(update: Update, context: ContextTypes.DEFAULT_TYPE): return await start(update, context, force_new=True)
async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
await update.message.reply_text("🚫 Cancelled.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Main Menu", callback_data='menu_back')]]))
return SELECTING_ACTION

# --- Main Function ---
def main():
try:
token = get_config_value("BOT_TOKEN")
logger.info("--- Starting ZIVPN Bot (Fixed WIB & Security) ---")
if not token:
logger.critical("BOT_TOKEN missing in /etc/zivpn/bot_config.sh")
return
app = ApplicationBuilder().token(token).build()

conv_handler = ConversationHandler(
entry_points=[CommandHandler("start", start), CommandHandler("menu", start), CallbackQueryHandler(back_to_main, pattern='^menu_back$')],
states={
SELECTING_ACTION: [
CallbackQueryHandler(start_gen, pattern='^menu_generate$'), CallbackQueryHandler(action_trial, pattern='^menu_trial$'),
CallbackQueryHandler(start_renew, pattern='^menu_renew$'), CallbackQueryHandler(start_del, pattern='^menu_delete$'),
CallbackQueryHandler(action_check, pattern='^menu_check$'), CallbackQueryHandler(action_status, pattern='^menu_status$'),
CallbackQueryHandler(action_topup, pattern='^menu_topup$'), CallbackQueryHandler(reseller_menu, pattern='^menu_resellers$'),
CallbackQueryHandler(start_add_reseller, pattern='^reseller_add$'), CallbackQueryHandler(start_del_reseller, pattern='^reseller_del$'),
CallbackQueryHandler(action_list_resellers, pattern='^reseller_list$'), CallbackQueryHandler(start_add_balance, pattern='^reseller_balance_add$'),
CallbackQueryHandler(start_sub_balance, pattern='^reseller_balance_sub$'),
CallbackQueryHandler(start_set_price, pattern='^reseller_set_price$'), CallbackQueryHandler(start_set_reseller_price, pattern='^reseller_set_reseller_price$'),
CallbackQueryHandler(start_broadcast, pattern='^menu_broadcast$'), CallbackQueryHandler(action_income_report, pattern='^menu_income$'),
CallbackQueryHandler(action_income_filter_reseller, pattern='^income_filter_reseller$'), CallbackQueryHandler(action_income_view_reseller, pattern='^income_reseller_'),
CallbackQueryHandler(action_backup, pattern='^menu_backup$'), CallbackQueryHandler(back_to_main, pattern='^menu_back$'),
CallbackQueryHandler(back_to_main_new, pattern='^menu_back_new$')
],
GEN_USER: [MessageHandler(filters.TEXT & ~filters.COMMAND, gen_user)],
GEN_PASS: [MessageHandler(filters.TEXT & ~filters.COMMAND, gen_pass)],
GEN_DAYS: [MessageHandler(filters.TEXT & ~filters.COMMAND, gen_days)],
RENEW_USER: [MessageHandler(filters.TEXT & ~filters.COMMAND, renew_user)],
RENEW_DAYS: [MessageHandler(filters.TEXT & ~filters.COMMAND, renew_days)],
DEL_USER: [MessageHandler(filters.TEXT & ~filters.COMMAND, del_user)],
ADD_RESELLER: [MessageHandler(filters.TEXT & ~filters.COMMAND, add_reseller_input)],
DEL_RESELLER: [MessageHandler(filters.TEXT & ~filters.COMMAND, del_reseller_input)],
ADD_BALANCE_ID: [MessageHandler(filters.TEXT & ~filters.COMMAND, add_balance_id_input)],
ADD_BALANCE_AMOUNT: [MessageHandler(filters.TEXT & ~filters.COMMAND, add_balance_amount_input)],
SET_PRICE_INPUT: [MessageHandler(filters.TEXT & ~filters.COMMAND, set_price_input)],
SET_RESELLER_PRICE_INPUT: [MessageHandler(filters.TEXT & ~filters.COMMAND, set_reseller_price_input)],
SUB_BALANCE_ID: [MessageHandler(filters.TEXT & ~filters.COMMAND, sub_balance_id_input)],
SUB_BALANCE_AMOUNT: [MessageHandler(filters.TEXT & ~filters.COMMAND, sub_balance_amount_input)],
BROADCAST_MSG: [MessageHandler(filters.ALL & ~filters.COMMAND, process_broadcast)],
},
fallbacks=[CommandHandler("cancel", cancel), CommandHandler("start", start), CommandHandler("menu", start)]
)
app.add_handler(conv_handler)
logger.info("Bot is polling...")
app.run_polling()
except Exception as e:
logger.critical(f"Error: {e}")
time.sleep(30)

if __name__ == '__main__':
main()