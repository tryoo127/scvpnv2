#!/bin/bash
set -e

clear

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

if [ ! -f /etc/os-release ]; then
  echo "Unsupported OS"
  exit 1
fi

. /etc/os-release
OS_ID="$ID"
OS_VER="$VERSION_ID"
CODENAME="${VERSION_CODENAME:-}"

case "$OS_ID:$OS_VER" in
  debian:10|ubuntu:20.04) ;;
  *)
    echo "This script supports Debian 10 and Ubuntu 20.04 only"
    echo "Detected: $OS_ID $OS_VER"
    exit 1
    ;;
esac

if [ -z "$CODENAME" ]; then
  echo "Could not detect distro codename"
  exit 1
fi

install_warp_proxy() {
  echo "===== INSTALL DEPENDENCIES ====="
  apt update -y
  apt install -y curl gnupg2 ca-certificates lsb-release

  echo "===== ADD CLOUDFLARE REPO ====="
  mkdir -p /usr/share/keyrings
  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

  cat > /etc/apt/sources.list.d/cloudflare-client.list <<EOF
deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${CODENAME} main
EOF

  echo "===== INSTALL CLOUDFLARE WARP ====="
  apt update -y
  apt install -y cloudflare-warp

  echo "===== START DAEMON ====="
  systemctl daemon-reload || true
  systemctl enable warp-svc >/dev/null 2>&1 || true
  systemctl start warp-svc >/dev/null 2>&1 || true

  sleep 2

  if ! systemctl is-active --quiet warp-svc; then
    echo "warp-svc is not running"
    systemctl status warp-svc --no-pager || true
    exit 1
  fi

  echo "===== REGISTER CLIENT ====="
  warp-cli --accept-tos registration new || true

  echo "===== CHECK PROXY MODE SUPPORT ====="
  if warp-cli mode --help 2>/dev/null | grep -qi proxy; then
    echo "Proxy mode detected via: warp-cli mode proxy"
    warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
    warp-cli --accept-tos mode proxy
    warp-cli --accept-tos connect
  elif warp-cli --help 2>/dev/null | grep -qi "set-mode"; then
    echo "Legacy proxy mode detected via: warp-cli set-mode proxy"
    warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
    warp-cli --accept-tos set-mode proxy
    warp-cli --accept-tos connect
  else
    echo
    echo "ERROR: Current warp-cli build does not expose CLI proxy mode on this server."
    echo "WARP installed and daemon is running, but proxy-only mode is not available from CLI."
    echo
    echo "Run these checks:"
    echo "  warp-cli --version"
    echo "  warp-cli --help"
    echo "  warp-cli mode --help"
    echo
    exit 2
  fi

  echo
  echo "===== STATUS ====="
  warp-cli --accept-tos status || true

  echo
  echo "===== TRY LOCAL PROXY PORT CHECK ====="
  ss -lntp 2>/dev/null | grep -E 'warp|40000|4000' || true

  echo
  echo "Done."
}

uninstall_warp_proxy() {
  echo "===== REMOVE WARP ====="
  warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
  systemctl stop warp-svc >/dev/null 2>&1 || true
  systemctl disable warp-svc >/dev/null 2>&1 || true

  apt purge -y cloudflare-warp || true
  apt autoremove -y || true

  rm -f /etc/apt/sources.list.d/cloudflare-client.list
  rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

  echo "Removed."
}

echo "Detected OS: $OS_ID $OS_VER ($CODENAME)"
echo "=============================="
echo "  WARP PROXY INSTALLER"
echo "=============================="
echo "1. Install WARP Proxy"
echo "2. Uninstall WARP"
echo "3. Exit"
echo "=============================="
read -rp "Choose option: " opt

case "$opt" in
  1) install_warp_proxy ;;
  2) uninstall_warp_proxy ;;
  3) exit 0 ;;
  *) echo "Invalid option"; exit 1 ;;
esac