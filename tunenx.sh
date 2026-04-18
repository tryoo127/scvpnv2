#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

MODE="$1"

detect_os() {
  . /etc/os-release
  case "$ID" in
    debian)
      [[ "$VERSION_ID" == "10" ]] || exit 1
      ;;
    ubuntu)
      [[ "$VERSION_ID" == "20.04" || "$VERSION_ID" == "20.04."* ]] || exit 1
      ;;
    *)
      exit 1
      ;;
  esac
}

detect_ssh() {
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    SSH_SERVICE="ssh"
  else
    SSH_SERVICE="sshd"
  fi
}

install_pkg() {
  apt update -y
  apt install -y nginx openssh-server curl ca-certificates procps irqbalance
}

install_all() {
  echo "[+] Install mode"

  command -v nginx >/dev/null 2>&1 || install_pkg

  mkdir -p /etc/nginx/conf.d

  cat > /etc/nginx/nginx.conf << 'EOF'
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
EOF

  cat > /etc/nginx/conf.d/xray.conf << 'EOF'
server {
    listen 80;
    server_name _;

    location /vmess-ws {
        proxy_pass http://127.0.0.1:8443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /vless-ws {
        proxy_pass http://127.0.0.1:2086;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

  # CPU
  for GOV in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$GOV" ] && echo performance > "$GOV" 2>/dev/null || true
  done

  systemctl enable irqbalance >/dev/null 2>&1 || true
  systemctl restart irqbalance >/dev/null 2>&1 || true

  # Swap
  swapoff -a 2>/dev/null || true
  rm -f /swapfile
  fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q swapfile /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab

  # SSH
  sed -i '/^Port/d' /etc/ssh/sshd_config
  echo -e "Port 2026\nPort 6202" >> /etc/ssh/sshd_config
  systemctl restart "$SSH_SERVICE"

  nginx -t && systemctl restart nginx

  echo "[✓] Done"
}

uninstall_all() {
  echo "[+] Uninstall mode"

  swapoff /swapfile 2>/dev/null || true
  rm -f /swapfile
  sed -i '\|/swapfile|d' /etc/fstab

  rm -f /etc/nginx/conf.d/xray.conf

  sed -i '/^Port 2026/d' /etc/ssh/sshd_config
  sed -i '/^Port 6202/d' /etc/ssh/sshd_config
  grep -q '^Port 22' /etc/ssh/sshd_config || echo "Port 22" >> /etc/ssh/sshd_config

  systemctl restart "$SSH_SERVICE"
  nginx -t && systemctl restart nginx || true

  echo "[✓] Uninstalled"
}

detect_os
detect_ssh

case "$MODE" in
  install) install_all ;;
  uninstall) uninstall_all ;;
  *) echo "Usage: bash tunenx.sh install | uninstall" ;;
esac