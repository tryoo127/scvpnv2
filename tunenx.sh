#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

detect_os() {
  if [ ! -f /etc/os-release ]; then
    echo "Unsupported OS"
    exit 1
  fi

  . /etc/os-release
  OS_ID="$ID"
  OS_VER="$VERSION_ID"

  case "$OS_ID" in
    debian)
      if [[ "$OS_VER" != "10" ]]; then
        echo "This script supports Debian 10 only"
        exit 1
      fi
      ;;
    ubuntu)
      if [[ "$OS_VER" != "20.04" && "$OS_VER" != "20.04."* ]]; then
        echo "This script supports Ubuntu 20.04 only"
        exit 1
      fi
      ;;
    *)
      echo "Only Debian 10 and Ubuntu 20.04 are supported"
      exit 1
      ;;
  esac

  echo "Detected OS: $OS_ID $OS_VER"
}

detect_ssh_service() {
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    SSH_SERVICE="ssh"
  elif systemctl list-unit-files | grep -q '^sshd\.service'; then
    SSH_SERVICE="sshd"
  else
    SSH_SERVICE="ssh"
  fi
}

install_needed_pkg() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y nginx openssh-server procps curl ca-certificates
  apt-get install -y irqbalance || true
}

apply_sysctl_if_exists() {
  local KEY="$1"
  local VALUE="$2"

  if sysctl -a 2>/dev/null | grep -q "^${KEY}[ =]"; then
    echo "${KEY}=${VALUE}" >> /etc/sysctl.d/99-tunenx.conf
  else
    echo "Skip unsupported sysctl: ${KEY}"
  fi
}

detect_os
detect_ssh_service

command -v nginx >/dev/null 2>&1 || {
  echo "nginx not installed, installing..."
  install_needed_pkg
}

NOW=$(date +%F-%H%M%S)

# Backup config
echo -e "\e[1;32mBackup config...\e[0m"
sleep 1

mkdir -p /root/backup-nginx /root/backup-ssh
cp /etc/nginx/nginx.conf /root/backup-nginx/nginx.conf.bak.$NOW 2>/dev/null || true
cp /etc/nginx/conf.d/xray.conf /root/backup-nginx/xray.conf.bak.$NOW 2>/dev/null || true
cp /etc/ssh/sshd_config /root/backup-ssh/sshd_config.bak.$NOW 2>/dev/null || true

# Set nginx config
echo -e "\e[1;32mSet Nginx config...\e[0m"
sleep 1

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
    gzip on;
    gzip_vary on;
    gzip_comp_level 5;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/x-javascript;

    autoindex on;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
    types_hash_max_size 2048;
    server_tokens off;
    reset_timedout_connection on;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    client_max_body_size 32M;
    client_header_buffer_size 8m;
    large_client_header_buffers 8 8m;

    fastcgi_buffer_size 8m;
    fastcgi_buffers 8 8m;
    fastcgi_read_timeout 600;

    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 60s;
    proxy_send_timeout 60s;

    include /etc/nginx/conf.d/*.conf;
}
EOF

# Set xray config
echo -e "\e[1;32mSet Xray config...\e[0m"
sleep 1

cat > /etc/nginx/conf.d/xray.conf << 'EOF'
server {
    listen 80;
    server_name _;

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    # VMESS
    location /vmess-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:8443;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # VLESS
    location /vless-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2086;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

# CPU Tuning
echo -e "\e[1;32mSet CPU Optimization...\e[0m"
sleep 1

CPU_GOV_OK=0
for GOV_FILE in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  [ -f "$GOV_FILE" ] || continue
  if echo performance > "$GOV_FILE" 2>/dev/null; then
    CPU_GOV_OK=1
  fi
done

if [ "$CPU_GOV_OK" -eq 1 ]; then
  echo -e "\e[1;32mCPU governor set to performance\e[0m"
else
  echo -e "\e[1;33mCPU governor tuning skipped (not supported on this VPS/kernel)\e[0m"
fi

if systemctl list-unit-files 2>/dev/null | grep -q '^irqbalance\.service'; then
  systemctl enable irqbalance >/dev/null 2>&1 || true
  systemctl restart irqbalance >/dev/null 2>&1 || true
  echo -e "\e[1;32mIRQBalance enabled\e[0m"
else
  echo -e "\e[1;33mIRQBalance not installed, skip\e[0m"
fi

# TCP BBR / BBRplus Optimization
echo -e "\e[1;32mSet TCP Optimization...\e[0m"
sleep 1

AVAILABLE_CC="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"

if echo "$AVAILABLE_CC" | grep -qw bbrplus; then
  CC_MODE="bbrplus"
elif echo "$AVAILABLE_CC" | grep -qw bbr; then
  CC_MODE="bbr"
else
  CC_MODE=""
fi

: > /etc/sysctl.d/99-tunenx.conf

apply_sysctl_if_exists "net.core.default_qdisc" "fq"
apply_sysctl_if_exists "net.ipv4.tcp_fastopen" "3"
apply_sysctl_if_exists "net.ipv4.tcp_mtu_probing" "1"
apply_sysctl_if_exists "net.ipv4.tcp_syncookies" "1"
apply_sysctl_if_exists "net.ipv4.tcp_low_latency" "1"
apply_sysctl_if_exists "net.ipv4.tcp_no_metrics_save" "1"
apply_sysctl_if_exists "net.core.rmem_max" "16777216"
apply_sysctl_if_exists "net.core.wmem_max" "16777216"
apply_sysctl_if_exists "net.ipv4.tcp_rmem" "4096 87380 16777216"
apply_sysctl_if_exists "net.ipv4.tcp_wmem" "4096 65536 16777216"
apply_sysctl_if_exists "net.core.netdev_max_backlog" "16384"
apply_sysctl_if_exists "net.core.somaxconn" "8192"
apply_sysctl_if_exists "net.ipv4.tcp_max_syn_backlog" "8192"
apply_sysctl_if_exists "vm.swappiness" "10"
apply_sysctl_if_exists "vm.vfs_cache_pressure" "50"
apply_sysctl_if_exists "vm.dirty_ratio" "10"
apply_sysctl_if_exists "vm.dirty_background_ratio" "5"
apply_sysctl_if_exists "kernel.sched_autogroup_enabled" "0"
apply_sysctl_if_exists "kernel.sched_migration_cost_ns" "5000000"
apply_sysctl_if_exists "kernel.sched_min_granularity_ns" "10000000"
apply_sysctl_if_exists "kernel.sched_wakeup_granularity_ns" "15000000"
apply_sysctl_if_exists "kernel.numa_balancing" "0"

if [ -n "$CC_MODE" ]; then
  echo "net.ipv4.tcp_congestion_control=$CC_MODE" >> /etc/sysctl.d/99-tunenx.conf
  echo -e "\e[1;32mDetected congestion control: $CC_MODE\e[0m"
else
  echo -e "\e[1;33mBBR / BBRplus not available on this kernel. Skip congestion control setting.\e[0m"
fi

sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-tunenx.conf || true
sleep 1

CURRENT_CC="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
echo -e "\e[1;32mAvailable CC:\e[0m $AVAILABLE_CC"
echo -e "\e[1;32mCurrent active CC:\e[0m $CURRENT_CC"

# CREATE & TUNE SWAP
echo -e "\e[1;32mSetup Swap...\e[0m"
sleep 1

SWAPSIZE=1G

swapoff -a 2>/dev/null || true
sed -i '\|^/swapfile none swap sw 0 0$|d' /etc/fstab 2>/dev/null || true
rm -f /swapfile

fallocate -l $SWAPSIZE /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress

chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
grep -q "^/swapfile " /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab

echo -e "\e[1;32mSwap configured!\e[0m"
sleep 1

# SSH Port Optimization
echo -e "\e[1;32mSet SSH ports...\e[0m"
sleep 1

sed -i '/^[#[:space:]]*Port[[:space:]]\+/d' /etc/ssh/sshd_config

cat >> /etc/ssh/sshd_config << 'EOF'
Port 2026
Port 6202
EOF

if sshd -t; then
  systemctl restart "$SSH_SERVICE"
  echo -e "\e[1;32mSSH ports updated to 2026 & 6202\e[0m"
else
  echo "SSH config error! Restoring backup..."
  cp /root/backup-ssh/sshd_config.bak.$NOW /etc/ssh/sshd_config
  exit 1
fi

echo "Test Nginx config..."
if nginx -t; then
  echo "Restart Nginx..."
  systemctl restart nginx
  sleep 1
  clear
  echo -e "\e[1;32mTune VPS Installations Successful!\e[0m"
else
  echo "Error config! Restoring nginx backup..."
  cp /root/backup-nginx/nginx.conf.bak.$NOW /etc/nginx/nginx.conf 2>/dev/null || true
  cp /root/backup-nginx/xray.conf.bak.$NOW /etc/nginx/conf.d/xray.conf 2>/dev/null || true
  exit 1
fi

rm -f tunenx.sh

echo
echo "Available congestion control : $AVAILABLE_CC"
echo "Current congestion control   : $CURRENT_CC"
echo "SSH service                  : $SSH_SERVICE"
echo "OS                           : $OS_ID $OS_VER"
echo
echo "Rebooting..."
reboot
