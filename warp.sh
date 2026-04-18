#!/usr/bin/env bash
set -e

clear
printf '===== CLOUDFLARE WARP MENU =====\n'
printf '1) Install WARP Proxy (Port 40000)\n'
printf '2) Uninstall WARP\n\n'
read -rp 'Select option [1-2]: ' opt

# Detect OS
if [ ! -f /etc/os-release ]; then
  echo 'Unsupported OS: /etc/os-release not found'
  exit 1
fi

. /etc/os-release
OS_ID="$ID"
OS_VER="$VERSION_ID"

if [[ "$OS_ID" == "ubuntu" && "$OS_VER" == "20.04" ]]; then
  DIST="focal"
elif [[ "$OS_ID" == "debian" && "$OS_VER" == "10" ]]; then
  DIST="buster"
else
  echo "Unsupported OS: $OS_ID $OS_VER"
  exit 1
fi

echo "Detected: $OS_ID $OS_VER ($DIST)"

install_warp() {
  echo '===== INSTALL DEP ====='
  apt update -y
  apt install -y curl gnupg lsb-release ca-certificates

  echo '===== ADD CLOUDFLARE REPO ====='
  mkdir -p /usr/share/keyrings
  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $DIST main" > /etc/apt/sources.list.d/cloudflare-client.list

  echo '===== UPDATE APT ====='
  apt update -y

  echo '===== INSTALL WARP ====='
  apt install -y cloudflare-warp

  echo '===== START SERVICE ====='
  systemctl daemon-reload
  systemctl enable warp-svc
  systemctl restart warp-svc
  sleep 5

  echo '===== SETUP WARP ====='
  warp-cli --accept-tos registration new
  warp-cli --accept-tos tunnel protocol set MASQUE
  warp-cli --accept-tos mode proxy
  warp-cli --accept-tos proxy port 40000
  warp-cli --accept-tos connect
  sleep 5

  echo
  echo '===== STATUS ====='
  warp-cli --accept-tos status || true
  ss -tulpn | grep 40000 || echo 'Port 40000 not listening'
}

uninstall_warp() {
  echo '===== STOP SERVICE ====='
  systemctl stop warp-svc 2>/dev/null || true
  systemctl disable warp-svc 2>/dev/null || true

  echo '===== REMOVE PACKAGE ====='
  apt purge -y cloudflare-warp 2>/dev/null || true
  apt autoremove -y 2>/dev/null || true

  echo '===== REMOVE FILE ====='
  rm -f /usr/bin/warp-cli /usr/bin/warp-svc /usr/bin/warp 2>/dev/null || true
  rm -rf /var/lib/cloudflare-warp
  rm -rf /etc/cloudflare-warp
  rm -rf /run/cloudflare-warp
  rm -rf /var/run/cloudflare-warp

  echo '===== REMOVE REPO ====='
  rm -f /etc/apt/sources.list.d/cloudflare-client.list
  rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

  echo '===== CLEAN SYSTEMD ====='
  rm -rf /etc/systemd/system/warp-svc.service.d
  systemctl daemon-reload

  echo
  echo '===== VERIFY ====='
  systemctl status warp-svc --no-pager -l 2>/dev/null || echo 'warp-svc removed'
  command -v warp-cli >/dev/null 2>&1 && echo 'warp-cli still exists' || echo 'warp-cli removed'
  ss -tulpn | grep 40000 || echo 'port 40000 not listening'
}

case "$opt" in
  1) install_warp ;;
  2) uninstall_warp ;;
  *)
    echo 'Invalid option'
    exit 1
    ;;
esac
