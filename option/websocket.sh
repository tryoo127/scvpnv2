#System Websocket
cd
cd /etc/systemd/system/
wget -O /etc/systemd/system/cdn-ssl.service https://raw.githubusercontent.com/tryoo127/scvpnv2/main/option/cdn-ssl.service

#System Websocket-Dropbear Service
cd /etc/systemd/system/
wget -O /etc/systemd/system/cdn-dropbear.service https://raw.githubusercontent.com/tryoo127/scvpnv2/main/option/cdn-dropbear.service

#Install WS-SSL
wget -q -O /usr/local/bin/cdn-ssl https://raw.githubusercontent.com/tryoo127/scvpnv2/main/option/cdn-ssl.py
chmod +x /usr/local/bin/cdn-ssl

#Install WS-Dropbear
wget -q -O /usr/local/bin/cdn-dropbear https://raw.githubusercontent.com/tryoo127/scvpnv2/main/option/cdn-dropbear.py
chmod +x /usr/local/bin/cdn-dropbear

#Enable & Start & Restart ws-stunnel service
systemctl daemon-reload
systemctl enable cdn-ssl
systemctl start cdn-ssl
systemctl restart cdn-ssl

#Enable & Start & Restart ws-dropbear service
systemctl daemon-reload
systemctl enable cdn-dropbear
systemctl start cdn-dropbear
systemctl restart cdn-dropbear