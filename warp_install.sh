#!/bin/bash

# ==============================================================================
#  VPS-WARP PRO (Xray Edition) - Ultimate Production Installer (v3.2)
# ==============================================================================

APP_DIR="/opt/vps-warp"
SCRIPT_LANG="en"

# Bump on every release. Used by `vps-warp update` for version comparison.
SCRIPT_VERSION="3.2"
# Persistent state dir — NOT wiped by the cleanup step. Holds installed
# version and the saved WARP+ license so updates don't lose them.
STATE_DIR="/etc/vps-warp"
LICENSE_FILE="${STATE_DIR}/license"
VERSION_FILE="${STATE_DIR}/version"
# Source of truth for self-update.
RAW_URL="https://raw.githubusercontent.com/Dristal-Kakals/vps-warp/main/warp_install.sh"

# --- Colors & Styling ---
C_RST="\e[0m"
C_BLD="\e[1m"
C_CYN="\e[36m"
C_GRN="\e[32m"
C_YLW="\e[33m"
C_RED="\e[31m"
C_GRY="\e[90m"

# --- Helpers ---
function step()  { echo -e "\n${C_CYN}▶${C_RST} ${C_BLD}$1${C_RST}"; }
function done_() { echo -e "  ${C_GRN}✔${C_RST} ${C_GRY}$1${C_RST}"; }
function fail()  { echo -e "\n  ${C_RED}✖ Error:${C_RST} $1\n"; exit 1; }
function warn()  { echo -e "  ${C_YLW}⚠${C_RST} ${C_YLW}$1${C_RST}"; }

# --- Endpoint pool (Cloudflare WARP) ---
WARP_SUBNETS=(162.159.192 162.159.193 162.159.195 188.114.96 188.114.97 188.114.98 188.114.99)
WARP_PORTS=(2408 500 4500 1701)
ENDPOINT_CACHE="/etc/wireguard/warp-endpoints.txt"

# Probe a random sample of WARP IPs with ICMP, sort by RTT, cache the top-5
# "IP:PORT" (fastest first) into $ENDPOINT_CACHE. Echoes the single fastest
# "IP:PORT", or nothing if no candidate answered (caller falls back to random).
function scan_endpoints() {
    local tmp sub h ip
    tmp=$(mktemp) || return 1
    for sub in "${WARP_SUBNETS[@]}"; do
        for h in $(shuf -i 1-254 -n 6); do
            ip="$sub.$h"
            ( rtt=$(ping -c 1 -W 1 "$ip" 2>/dev/null | grep -oP 'time=\K[0-9.]+'); [[ -n "$rtt" ]] && echo "$rtt $ip" >> "$tmp" ) &
        done
    done
    wait
    [[ -s "$tmp" ]] || { rm -f "$tmp"; return 1; }
    mkdir -p "$(dirname "$ENDPOINT_CACHE")"
    sort -n "$tmp" | head -5 | while read -r _rtt ip; do
        echo "${ip}:${WARP_PORTS[$RANDOM % ${#WARP_PORTS[@]}]}"
    done > "$ENDPOINT_CACHE"
    rm -f "$tmp"
    chmod 600 "$ENDPOINT_CACHE"
    head -1 "$ENDPOINT_CACHE"
}

function print_logo() {
    clear
    echo -e "${C_CYN}"
    echo '  ██╗    ██╗ █████╗ ██████╗ ██████╗ '
    echo '  ██║    ██║██╔══██╗██╔══██╗██╔══██╗'
    echo '  ██║ █╗ ██║███████║██████╔╝██████╔╝'
    echo '  ██║███╗██║██╔══██║██╔══██╗██╔═══╝ '
    echo '  ╚███╔███╔╝██║  ██║██║  ██║██║     '
    echo '   ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     '
    echo -e "${C_GRN}    P R O   E D I T I O N  (Xray)   ${C_RST}"
    echo -e "${C_GRY}  ──────────────────────────────────${C_RST}\n"
}

# --- Language Selection ---
function select_language {
    print_logo
    echo -e "  🌍 ${C_BLD}Choose language / Выберите язык:${C_RST}"
    echo -e "     ${C_CYN}[1]${C_RST} English"
    echo -e "     ${C_CYN}[2]${C_RST} Русский\n"
    
    while true; do
        read -p "  > " choice
        case $choice in
            1) SCRIPT_LANG="en"; break ;;
            2) SCRIPT_LANG="ru"; break ;;
            *) warn "Please enter 1 or 2" ;;
        esac
    done
}

function t() {
    local key="$1"
    if [[ "$SCRIPT_LANG" == "ru" ]]; then
        case "$key" in
            "root_req") echo "Требуются права root (sudo)" ;;
            "clean") echo "Очистка старых версий..." ;;
            "clean_ok") echo "Система очищена" ;;
            "deps") echo "Установка зависимостей (WireGuard, iptables)..." ;;
            "deps_ok") echo "Зависимости установлены" ;;
            "wgcf") echo "Загрузка ядра wgcf..." ;;
            "wgcf_ok") echo "Ядро установлено" ;;
            "reg") echo "Регистрация в сети Cloudflare..." ;;
            "reg_ok") echo "Профиль готов" ;;
            "scan") echo "Поиск самого быстрого эндпоинта Cloudflare..." ;;
            "scan_ok") echo "Лучший эндпоинт выбран:" ;;
            "scan_fail") echo "Эндпоинты не ответили на ping, берём случайный." ;;
            "plus_ask") echo "🔑 Введите ключ WARP+ (или нажмите Enter для бесплатной версии):" ;;
            "plus_keep_hint") echo "(Enter — оставить сохранённый ключ)" ;;
            "plus_apply") echo "Активация WARP+..." ;;
            "plus_ok") echo "Лицензия активирована!" ;;
            "plus_err") echo "Ошибка ключа, используем базовый тариф." ;;
            "opt") echo "Глубокая оптимизация Xray (MTU, OUTPUT Clamping, IPv4)..." ;;
            "opt_ok") echo "Сетевой стек настроен" ;;
            "start") echo "Запуск туннеля..." ;;
            "start_ok") echo "Интерфейс поднят" ;;
            "handshake") echo "Ожидание ответа сети (Handshake)..." ;;
            "hs_ok") echo "Соединение установлено! Задержка:" ;;
            "watchdog") echo "Установка Smart Watchdog (Systemd)..." ;;
            "watchdog_ok") echo "Watchdog активирован" ;;
            "finish") echo "Установка завершена!" ;;
            "help") echo "Используйте команду vps-warp для управления" ;;
            *) echo "$key" ;;
        esac
    else
        case "$key" in
            "root_req") echo "Root privileges required (sudo)" ;;
            "clean") echo "Cleaning up old versions..." ;;
            "clean_ok") echo "System cleaned" ;;
            "deps") echo "Installing dependencies (WireGuard, iptables)..." ;;
            "deps_ok") echo "Dependencies installed" ;;
            "wgcf") echo "Downloading wgcf core..." ;;
            "wgcf_ok") echo "Core installed" ;;
            "reg") echo "Registering Cloudflare account..." ;;
            "reg_ok") echo "Profile ready" ;;
            "scan") echo "Probing for the fastest Cloudflare endpoint..." ;;
            "scan_ok") echo "Best endpoint selected:" ;;
            "scan_fail") echo "No endpoints answered ping, falling back to random." ;;
            "plus_ask") echo "🔑 Enter WARP+ key (or press Enter for free tier):" ;;
            "plus_keep_hint") echo "(Enter — keep the saved key)" ;;
            "plus_apply") echo "Activating WARP+..." ;;
            "plus_ok") echo "License activated!" ;;
            "plus_err") echo "Key error, using free tier." ;;
            "opt") echo "Deep Xray Optimization (MTU, OUTPUT Clamping, IPv4)..." ;;
            "opt_ok") echo "Network stack optimized" ;;
            "start") echo "Starting tunnel..." ;;
            "start_ok") echo "Interface is up" ;;
            "handshake") echo "Waiting for network handshake..." ;;
            "hs_ok") echo "Connection established! Latency:" ;;
            "watchdog") echo "Installing Smart Watchdog (Systemd)..." ;;
            "watchdog_ok") echo "Watchdog activated" ;;
            "finish") echo "Installation complete!" ;;
            "help") echo "Use vps-warp command to manage" ;;
            *) echo "$key" ;;
        esac
    fi
}

# --- Pre-flight Checks ---
[[ $EUID -ne 0 ]] && fail "$(t "root_req")"

# --- Start ---
select_language
print_logo

# 1. Cleanup
step "🗑️  $(t "clean")"
systemctl disable wg-quick@warp --now &>/dev/null || true
systemctl disable warp-watchdog.timer --now &>/dev/null || true
rm -rf /opt/warp-native /opt/vps-warp /etc/cron.d/warp-native /usr/local/bin/warp /etc/systemd/system/warp-watchdog.* &>/dev/null
systemctl daemon-reload
done_ "$(t "clean_ok")"

# 2. Dependencies
step "📦 $(t "deps")"
apt-get update -qq &>/dev/null
apt-get install -y wireguard iptables iproute2 curl wget &>/dev/null || fail "APT Error"
done_ "$(t "deps_ok")"

# 3. WGCF Download
# Security: pinned version + hardcoded SHA-256 to block supply-chain RCE.
# wgcf runs as root, so never trust "latest" or an unverified download.
# Update both version and checksums together from the release's checksums.txt.
WGCF_VERSION="v2.2.31"
WGCF_SHA256_amd64="69147e1a517c66129edd8ac8cb60484d6c9515178d7b4a2f95e3c925f225572a"
WGCF_SHA256_arm64="b9bdbdeaa3f9f4ba741ba55b8bd94c24f7166c27668eb7e8192ccf9746961182"

step "⚙️  $(t "wgcf")"
ARCH=$(uname -m)
[[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && WGCF_ARCH="arm64" || WGCF_ARCH="amd64"
WGCF_SHA256_VAR="WGCF_SHA256_${WGCF_ARCH}"
WGCF_SHA256="${!WGCF_SHA256_VAR}"
WGCF_DL="https://github.com/ViRb3/wgcf/releases/download/${WGCF_VERSION}/wgcf_${WGCF_VERSION#v}_linux_${WGCF_ARCH}"

# -f: fail on HTTP errors so a 404/5xx HTML page never lands as an executable.
WGCF_TMP=$(mktemp) || fail "mktemp failed"
curl -fSL "$WGCF_DL" -o "$WGCF_TMP" || { rm -f "$WGCF_TMP"; fail "Download failed"; }
echo "${WGCF_SHA256}  ${WGCF_TMP}" | sha256sum -c - &>/dev/null || { rm -f "$WGCF_TMP"; fail "Checksum mismatch — aborting (possible tampering)"; }
install -m 0755 "$WGCF_TMP" /usr/local/bin/wgcf || { rm -f "$WGCF_TMP"; fail "Install failed"; }
rm -f "$WGCF_TMP"
done_ "$(t "wgcf_ok") (v${WGCF_VERSION#v})"

# 4. Registration (Protected from Rate Limits)
step "🛡️  $(t "reg")"
cd "$HOME" || exit
if [[ ! -f wgcf-account.toml ]]; then
    for i in {1..3}; do
        timeout 40 bash -c 'yes | wgcf register' &>/dev/null && break
        sleep 3
    done
fi
wgcf generate &>/dev/null || fail "Config generation failed. Cloudflare might be blocking the IP temporarily."
done_ "$(t "reg_ok")"

# 5. WARP+
# Reuse a previously saved license on update so WARP+ survives a re-run.
SAVED_LICENSE=""
[[ -f "$LICENSE_FILE" ]] && SAVED_LICENSE=$(tr -cd 'a-zA-Z0-9-' < "$LICENSE_FILE")
echo ""
echo -e "  $(t "plus_ask")"
[[ -n "$SAVED_LICENSE" ]] && echo -e "  ${C_GRY}$(t "plus_keep_hint")${C_RST}"
read -p "  > " WARP_LICENSE
# Empty input + a saved key => keep the existing WARP+ license.
[[ -z "$WARP_LICENSE" && -n "$SAVED_LICENSE" ]] && WARP_LICENSE="$SAVED_LICENSE"
if [[ -n "$WARP_LICENSE" ]]; then
    # Security: Санитизация ввода (оставляем только буквы, цифры и дефисы)
    WARP_LICENSE=$(echo "$WARP_LICENSE" | tr -cd 'a-zA-Z0-9-')
    step "💎 $(t "plus_apply")"
    if wgcf update --license-key "$WARP_LICENSE" &>/dev/null; then
        wgcf generate &>/dev/null
        # Persist for future updates (root-only readable).
        mkdir -p "$STATE_DIR"
        printf '%s\n' "$WARP_LICENSE" > "$LICENSE_FILE"
        chmod 600 "$LICENSE_FILE"
        done_ "$(t "plus_ok")"
    else
        warn "$(t "plus_err")"
    fi
fi

# 6. Ultimate Xray Tweaks (Production Grade Injection)
step "🛠️  $(t "opt")"
CONF="wgcf-profile.conf"

# Очищаем конфиг от дефолтного мусора wgcf
sed -i '/^DNS =/d' "$CONF"
sed -i '/^MTU =/d' "$CONF"
sed -i '/^Table =/d' "$CONF"

# Blackhole Fix: Удаляем IPv6 полностью
sed -i 's/,\s*[0-9a-fA-F:]\+\/128//' "$CONF"
sed -i '/Address = [0-9a-fA-F:]\+\/128/d' "$CONF"
sed -i 's/,\s*::\/0//' "$CONF"
sed -i '/AllowedIPs = ::\/0/d' "$CONF"

# Жестко инжектим правила В СЕКЦИЮ [Interface]
sed -i '/^\[Interface\]/a\
MTU = 1280\
Table = 51820\
PostUp = ip rule add fwmark 255 table 51820 || true\
PostDown = ip rule del fwmark 255 table 51820 || true\
PostUp = iptables -t mangle -A POSTROUTING -o warp -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240 || true\
PostDown = iptables -t mangle -D POSTROUTING -o warp -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240 || true\
' "$CONF"

# Жестко инжектим Keepalive В СЕКЦИЮ [Peer]
sed -i '/^\[Peer\]/a\
PersistentKeepalive = 15\
' "$CONF"

# Fastest-endpoint selection: ICMP-probe the WARP pool, cache top-5, pick #1.
# Falls back to a random endpoint if nothing answered (blocked ICMP / DPI).
step "📡 $(t "scan")"
BEST_EP=$(scan_endpoints)
if [[ -z "$BEST_EP" ]]; then
    warn "$(t "scan_fail")"
    BEST_EP="$(shuf -e 188.114.96 188.114.97 -n 1).$(shuf -i 1-254 -n 1):$(shuf -e 2408 500 4500 1701 -n 1)"
fi
sed -i "s/^Endpoint = .*/Endpoint = ${BEST_EP}/" "$CONF"
done_ "$(t "scan_ok") ${BEST_EP}"

mkdir -p /etc/wireguard
mv "$CONF" /etc/wireguard/warp.conf
chmod 600 /etc/wireguard/warp.conf # Security: Защита приватного ключа WG
chmod 600 "$HOME/wgcf-account.toml" 2>/dev/null || true
done_ "$(t "opt_ok")"

WARP_LOCAL_IP=$(grep -oP '(?<=Address = )[0-9\.]+' /etc/wireguard/warp.conf)

# 7. Start Services
step "🚀 $(t "start")"
systemctl enable wg-quick@warp &>/dev/null
systemctl start wg-quick@warp &>/dev/null
done_ "$(t "start_ok")"

# 8. Handshake Check
step "📡 $(t "handshake")"
hs_ok=0
for i in {1..15}; do
    hs_ts=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
    if [[ -n "$hs_ts" && "$hs_ts" -gt 0 ]]; then
        age=$(( $(date +%s) - hs_ts ))
        done_ "$(t "hs_ok") ${age}s"
        hs_ok=1
        break
    fi
    sleep 1
done
[[ $hs_ok -eq 0 ]] && warn "Handshake timeout. Interface is up, but connection might be blocked."

# 9. Systemd Watchdog (Triple Ping System + Fixed PATH)
step "🤖 $(t "watchdog")"
mkdir -p "$APP_DIR"
chmod 700 "$APP_DIR" # Security: Защита от локального Privilege Escalation
cat > "$APP_DIR/watchdog.sh" << 'EOF'
#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if ! systemctl is-active --quiet wg-quick@warp; then exit 0; fi

hs_ts=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
now=$(date +%s)
age=$(( now - hs_ts ))

ping_ok=0
for ip in 1.1.1.1 8.8.8.8 9.9.9.9; do
    # Пингуем через маркировку пакетов (так же, как ходит Xray)
    if ping -m 255 -c 1 -W 2 $ip &>/dev/null; then
        ping_ok=1
        break
    fi
done

if [[ -z "$hs_ts" || "$hs_ts" -eq 0 || $age -gt 180 ]] || [[ $ping_ok -eq 0 ]]; then
    CACHE="/etc/wireguard/warp-endpoints.txt"
    NEXT_EP=""
    # Rotate to the next-fastest endpoint from the cached top-N (round-robin).
    if [[ -s "$CACHE" ]]; then
        cur=$(grep '^Endpoint' /etc/wireguard/warp.conf 2>/dev/null | awk '{print $3}')
        mapfile -t eps < "$CACHE"
        idx=-1
        for i in "${!eps[@]}"; do
            [[ "${eps[$i]}" == "$cur" ]] && { idx=$i; break; }
        done
        NEXT_EP="${eps[$(( (idx + 1) % ${#eps[@]} ))]}"
    fi
    # Fallback to a random endpoint if the cache is missing/empty.
    if [[ -z "$NEXT_EP" ]]; then
        RAND_SUBNET=$(shuf -e "188.114.96" "188.114.97" -n 1)
        RAND_HOST=$(shuf -i 1-254 -n 1)
        RAND_PORT=$(shuf -e 2408 500 4500 1701 -n 1)
        NEXT_EP="${RAND_SUBNET}.${RAND_HOST}:${RAND_PORT}"
    fi
    sed -i "s/^Endpoint = .*/Endpoint = ${NEXT_EP}/" /etc/wireguard/warp.conf
    systemctl restart wg-quick@warp
    echo "WARP Watchdog: Connection lost. Rotated to ${NEXT_EP}"
fi
EOF
chmod 700 "$APP_DIR/watchdog.sh"

cat > /etc/systemd/system/warp-watchdog.service << EOF
[Unit]
Description=VPS-WARP Smart Watchdog

[Service]
Type=oneshot
ExecStart=$APP_DIR/watchdog.sh
EOF

cat > /etc/systemd/system/warp-watchdog.timer << EOF
[Unit]
Description=Run VPS-WARP Watchdog every 3 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=3min

[Install]
WantedBy=timers.target
EOF

chmod 644 /etc/systemd/system/warp-watchdog.service
chmod 644 /etc/systemd/system/warp-watchdog.timer

systemctl daemon-reload
systemctl enable warp-watchdog.timer --now &>/dev/null
done_ "$(t "watchdog_ok")"

# 10. CLI Dashboard (Flat Design + Traffic Stats)
cat > /usr/local/bin/vps-warp <<'EOF'
#!/bin/bash
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31m✖ Error:\e[0m This command must be run as root or with sudo."
    exit 1
fi
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
C_RST="\e[0m"; C_BLD="\e[1m"; C_CYN="\e[36m"; C_GRN="\e[32m"; C_RED="\e[31m"; C_GRY="\e[90m"; C_YLW="\e[33m"

format_bytes() {
    local b=$1
    if [[ -z "$b" || "$b" == "0" ]]; then echo "0 KB"; return; fi
    if [[ $b -lt 1048576 ]]; then echo "$((b / 1024)) KB"
    elif [[ $b -lt 1073741824 ]]; then echo "$((b / 1048576)) MB"
    else echo "$(awk "BEGIN {printf \"%.1f\", $b/1073741824}") GB"
    fi
}

function show_status {
    clear
    
    if systemctl is-active --quiet wg-quick@warp; then 
        c_stat="${C_GRN}"
        t_stat="● ACTIVE"
    else 
        c_stat="${C_RED}"
        t_stat="○ INACTIVE"
    fi
    
    tunnel_ip=$(ip -4 addr show warp 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    endpoint=$(grep "^Endpoint" /etc/wireguard/warp.conf 2>/dev/null | awk '{print $3}')
    
    raw_stats=$(wg show warp transfer 2>/dev/null | awk '{print $2, $3}')
    rx_bytes=$(echo "$raw_stats" | awk '{print $1}')
    tx_bytes=$(echo "$raw_stats" | awk '{print $2}')
    rx_fmt=$(format_bytes "$rx_bytes")
    tx_fmt=$(format_bytes "$tx_bytes")

    hs_ts=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
    if [[ -n "$hs_ts" && "$hs_ts" -gt 0 ]]; then
        c_hs="${C_GRN}"
        t_hs="$(( $(date +%s) - hs_ts ))s ago"
    else 
        c_hs="${C_RED}"
        t_hs="No connection"
    fi

    echo -e "\n  ${C_BLD}⚡ VPS-WARP STATUS${C_RST}"
    echo -e "  ${C_GRY}───────────────────────────────────${C_RST}\n"
    
    echo -e "   ${C_GRY}Status:${C_RST}       ${c_stat}${t_stat}${C_RST}"
    echo -e "   ${C_GRY}Local IP:${C_RST}     ${C_CYN}${tunnel_ip:---}${C_RST}"
    echo -e "   ${C_GRY}Cloudflare:${C_RST}   ${C_CYN}${endpoint:---}${C_RST}"
    echo -e "   ${C_GRY}Handshake:${C_RST}    ${c_hs}${t_hs}${C_RST}"
    echo -e "   ${C_GRY}Traffic:${C_RST}      ${C_YLW}↓ ${rx_fmt}${C_RST}  ${C_GRY}|${C_RST}  ${C_YLW}↑ ${tx_fmt}${C_RST}"
    
    echo -e "\n  ${C_GRY}───────────────────────────────────${C_RST}"
    echo -e "   ${C_GRY}Commands:${C_RST} vps-warp ${C_BLD}start${C_RST} | ${C_BLD}stop${C_RST} | ${C_BLD}restart${C_RST} | ${C_BLD}log${C_RST} | ${C_BLD}update${C_RST}\n"
}

# Self-update: fetch the latest installer, compare versions, reinstall if newer.
# `vps-warp update --force` reinstalls even when versions match.
RAW_URL="https://raw.githubusercontent.com/Dristal-Kakals/vps-warp/main/warp_install.sh"
VERSION_FILE="/etc/vps-warp/version"

function update_self {
    local force="$1" tmp remote local_v newest
    echo -e "\n  ${C_CYN}▶${C_RST} ${C_BLD}Checking for updates...${C_RST}"
    tmp=$(mktemp) || { echo -e "  ${C_RED}✖ Error:${C_RST} mktemp failed"; exit 1; }
    # -f: fail on HTTP errors so we never run an error page as a script.
    curl -fsSL "$RAW_URL" -o "$tmp" || { rm -f "$tmp"; echo -e "  ${C_RED}✖ Error:${C_RST} download failed"; exit 1; }

    remote=$(grep -m1 -oP '^SCRIPT_VERSION="\K[^"]+' "$tmp")
    [[ -z "$remote" ]] && { rm -f "$tmp"; echo -e "  ${C_RED}✖ Error:${C_RST} cannot read remote version"; exit 1; }
    local_v=$(cat "$VERSION_FILE" 2>/dev/null || echo "0")

    newest=$(printf '%s\n%s\n' "$local_v" "$remote" | sort -V | tail -1)
    if [[ "$force" != "--force" && "$remote" == "$local_v" ]]; then
        rm -f "$tmp"
        echo -e "  ${C_GRN}✔${C_RST} Already up to date (v${local_v})"
        exit 0
    fi
    if [[ "$force" != "--force" && "$newest" == "$local_v" ]]; then
        rm -f "$tmp"
        echo -e "  ${C_YLW}⚠${C_RST} Installed v${local_v} is newer than remote v${remote}; use --force to reinstall"
        exit 0
    fi

    echo -e "  ${C_GRN}✔${C_RST} Updating v${local_v} → v${remote}"
    chmod +x "$tmp"
    bash "$tmp"
    local rc=$?
    rm -f "$tmp"
    exit $rc
}

case "$1" in
    start)   systemctl start wg-quick@warp; show_status ;;
    stop)    systemctl stop wg-quick@warp; show_status ;;
    restart) systemctl restart wg-quick@warp; show_status ;;
    log)     journalctl -u warp-watchdog.service -f ;;
    update)  update_self "$2" ;;
    *)       show_status ;;
esac
EOF
chmod +x /usr/local/bin/vps-warp

# Record installed version so `vps-warp update` can compare against the remote.
mkdir -p "$STATE_DIR"
printf '%s\n' "$SCRIPT_VERSION" > "$VERSION_FILE"

# Finish
echo -e "\n  🎉 ${C_GRN}${C_BLD}$(t "finish")${C_RST}"
echo -e "  📌 ${C_BLD}Xray / Remnawave Outbound IP:${C_RST} ${C_CYN}${WARP_LOCAL_IP}${C_RST} ${C_GRY}(use as 'sendThrough')${C_RST}"
echo -e "  👉 $(t "help"): ${C_CYN}vps-warp${C_RST}\n"