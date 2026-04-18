#!/bin/bash

clear

# ===== DETECT OS =====
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "OS not supported"
    exit 1
fi

if [[ "$OS" != "debian" && "$OS" != "ubuntu" ]]; then
    echo "Only Debian & Ubuntu supported"
    exit 1
fi

echo "Detected: $OS $VER"
sleep 1

# ===== MENU =====
echo "=============================="
echo "   WARP PROXY INSTALLER"
echo "=============================="
echo "1. Install WARP Proxy"
echo "2. Uninstall WARP Proxy"
echo "3. Exit"
echo "=============================="
read -p "Choose option: " opt

install_warp() {
    echo "Installing dependencies..."
    apt update -y
    apt install -y curl gnupg lsb-release

    echo "Adding Cloudflare repo..."
    curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor > /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflare-client.list

    apt update -y
    apt install -y cloudflare-warp

    echo "Register WARP..."
    warp-cli register

    echo "Set mode proxy..."
    warp-cli set-mode proxy

    echo "Start WARP..."
    warp-cli connect

    echo
    echo "===== DONE ====="
    warp-cli status
}

uninstall_warp() {
    echo "Removing WARP..."
    warp-cli disconnect 2>/dev/null || true
    apt purge -y cloudflare-warp
    rm -f /etc/apt/sources.list.d/cloudflare-client.list
    rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    apt autoremove -y

    echo "===== REMOVED ====="
}

case $opt in
    1) install_warp ;;
    2) uninstall_warp ;;
    3) exit ;;
    *) echo "Invalid option" ;;
esac