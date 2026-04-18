cat > /root/tunenx.sh << 'EOF'
#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

MODE="$1"

detect_os() {
  [ -f /etc/os-release ] || { echo "Unsupported OS"; exit 1; }
  . /etc/os-release

  case "$ID" in
    debian)
      [[ "$VERSION_ID" == "10" ]] || { echo "Debian 10 only"; exit 1; }
      ;;
    ubuntu)
      [[ "$VERSION_ID" == "20.04" || "$VERSION_ID" == "20.04."* ]] || { echo "Ubuntu 20.04 only"; exit 1; }
      ;;
    *)
      echo "Only Debian 10 and Ubuntu 20.04 supported"
      exit 1
      ;;
  esac
}

detect_ssh() {
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    SSH_SERVICE="ssh"
  elif systemctl list-unit-files | grep -q '^sshd\.service'; then
    SSH_SERVICE="sshd"
  else
    SSH_SERVICE="ssh"
  fi
}

install_pkg() {
  export DEBIAN_FRONTEND=noninteractive
  apt update -y
  apt install -y nginx openssh-server curl ca-certificates procps irqbalance
}

install_all() {
  echo "[+] Install mode"

  command -v nginx >/dev/null 2>&1 || install_pkg

  mkdir -p /etc/nginx/conf.d

  cat > /etc/nginx/nginx.conf << 'NGINXEOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    multi_accept on;
    worker_connections 1024;
    use epoll;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    include /etc/nginx/conf.d/*.conf;
}
NGINXEOF

  cat > /etc/nginx/conf.d/xray.conf << 'XRAYEOF'
server {
    listen 80;
    server_name _;

    location /vmess-ws {
        proxy_pass http://127.0.0.1:8443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /vless-ws {
        proxy_pass http://127.0.0.1:2086;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
XRAYEOF

  for GOV in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$GOV" ] && echo performance > "$GOV" 2>/dev/null || true
  done

  systemctl enable irqbalance >/dev/null 2>&1 || true
  systemctl restart irqbalance >/dev/null 2>&1 || true

  swapoff -a 2>/dev/null || true
  sed -i '\|/swapfile|d' /etc/fstab 2>/dev/null || true
  rm -f /swapfile
  fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab

  sed -i '/^[#[:space:]]*Port[[:space:]]\+/d' /etc/ssh/sshd_config
  cat >> /etc/ssh/sshd_config << 'SSHEOF'
Port 2026
Port 6202
SSHEOF

  if sshd -t; then
    systemctl restart "$SSH_SERVICE"
  else
    echo "SSH config error"
    exit 1
  fi

  nginx -t && systemctl restart nginx

  echo "[✓] Install done"
}

uninstall_all() {
  echo "[+] Uninstall mode"

  swapoff /swapfile 2>/dev/null || true
  rm -f /swapfile
  sed -i '\|/swapfile|d' /etc/fstab 2>/dev/null || true

  rm -f /etc/nginx/conf.d/xray.conf

  sed -i '/^Port 2026$/d' /etc/ssh/sshd_config
  sed -i '/^Port 6202$/d' /etc/ssh/sshd_config
  grep -q '^Port 22$' /etc/ssh/sshd_config || echo "Port 22" >> /etc/ssh/sshd_config

  if sshd -t; then
    systemctl restart "$SSH_SERVICE" || true
  else
    echo "SSH config needs manual check"
  fi

  nginx -t && systemctl restart nginx || true

  echo "[✓] Uninstall done"
}

check_all() {
  pass() { echo -e "\e[1;32m[PASS]\e[0m $1"; }
  fail() { echo -e "\e[1;31m[FAIL]\e[0m $1"; }
  warn() { echo -e "\e[1;33m[SKIP]\e[0m $1"; }

  echo "===== TUNENX CHECK ====="

  if systemctl is-active --quiet nginx; then
    pass "Nginx running"
  else
    fail "Nginx not running"
  fi

  if nginx -t >/dev/null 2>&1; then
    pass "Nginx config valid"
  else
    fail "Nginx config error"
  fi

  if [ -f /etc/nginx/conf.d/xray.conf ]; then
    pass "xray.conf exists"
  else
    fail "xray.conf missing"
  fi

  if grep -q "^Port 2026" /etc/ssh/sshd_config && grep -q "^Port 6202" /etc/ssh/sshd_config; then
    pass "SSH ports configured"
  else
    fail "SSH ports not set"
  fi

  if ss -lntp 2>/dev/null | grep -qE ':2026|:6202'; then
    pass "SSH ports listening"
  else
    fail "SSH ports not listening"
  fi

  if swapon --show | grep -q "/swapfile"; then
    pass "Swap active"
  else
    fail "Swap not active"
  fi

  CPU_COUNT="$(nproc 2>/dev/null || echo 1)"
  if [ "$CPU_COUNT" -le 1 ]; then
    warn "IRQBalance skipped (single CPU)"
  else
    if systemctl is-active --quiet irqbalance; then
      pass "IRQBalance running"
    else
      fail "IRQBalance not running"
    fi
  fi

  echo "========================="
}

menu() {
  clear
  echo "=========================="
  echo "       TUNENX MENU"
  echo "=========================="
  echo "1) Install"
  echo "2) Uninstall"
  echo "3) Check"
  echo "0) Exit"
  echo "=========================="
  read -rp "Choose: " opt

  case "$opt" in
    1)
      install_all
      echo
      check_all
      ;;
    2)
      uninstall_all
      ;;
    3)
      check_all
      ;;
    0)
      exit 0
      ;;
    *)
      echo "Invalid choice"
      exit 1
      ;;
  esac
}

detect_os
detect_ssh

case "$MODE" in
  install)
    install_all
    echo
    check_all
    ;;
  uninstall)
    uninstall_all
    ;;
  check)
    check_all
    ;;
  ""|menu)
    menu
    ;;
  *)
    echo "Usage: bash /root/tunenx.sh [install|uninstall|check|menu]"
    exit 1
    ;;
esac
EOF

chmod +x /root/tunenx.sh
bash /root/tunenx.sh