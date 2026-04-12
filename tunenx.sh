#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

command -v nginx >/dev/null 2>&1 || {
  echo "nginx not installed"
  exit 1
}

NOW=$(date +%F-%H%M%S)

#Backup config
echo -e "\e[1;32mBackup config...\e[0m"
sleep 2

mkdir -p /root/backup-nginx
cp /etc/nginx/nginx.conf /root/backup-nginx/nginx.conf.bak.$NOW 2>/dev/null
cp /etc/nginx/conf.d/xray.conf /root/backup-nginx/xray.conf.bak.$NOW 2>/dev/null

#Backup config
echo -e "\e[1;32mSet Nginx config...\e[0m"
sleep 2

cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;

worker_processes auto;
pid /var/run/nginx.pid;

events {
    multi_accept on;
    worker_connections 1024;
}

http {
    gzip on;
    gzip_vary on;
    gzip_comp_level 5;
    gzip_types text/plain application/x-javascript text/xml text/css;

    autoindex on;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

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

    # WebSocket optimize
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 60s;
    proxy_send_timeout 60s;

    include /etc/nginx/conf.d/*.conf;
}
EOF

#Set Xray config
echo -e "\e[1;32mSet Xray config...\e[0m"
sleep 2

mkdir -p /etc/nginx/conf.d

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
clear


echo "Test Nginx config..."
if nginx -t; then
echo "Restart Nginx..."
systemctl restart nginx
sleep 2
clear

#Set Xray config
echo -e "\e[1;32mTune Nginx & Xray config DONE!\e[0m"
sleep 2

rm -f /root/tunenx.sh

else
    echo "Error config! Please check."
    exit 1
fi