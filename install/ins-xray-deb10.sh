#!/bin/bash
MYIP=$(curl -sS ipv4.icanhazip.com)
domain=$(cat /root/domain)
apt install iptables -y
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt install curl socat xz-utils wget apt-transport-https gnupg gnupg2 gnupg1 dnsutils lsb-release -y 
apt install socat cron bash-completion ntpdate -y
apt install ntpdate -y
ntpdate 0.my.pool.ntp.org
apt -y install chrony
timedatectl set-ntp true
systemctl enable chronyd && systemctl restart chronyd
systemctl enable chrony && systemctl restart chrony
timedatectl set-timezone Asia/Kuala_Lumpur
chronyc sourcestats -v
chronyc tracking -v
date

# Acc Trojan XRAY TCP TLS
mkdir -p /usr/local/etc/xray/
touch /usr/local/etc/xray/akunxtr.conf

# CHECK VERSION XRAY CORE
latest_version="$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)"

# Installation Xray Core
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v1.7.5/xray-linux-64.zip""

# Make Main Directory
mkdir -p /usr/bin/xray
mkdir -p /etc/xray

# Unzip Xray Linux 64
cd `mktemp -d`
curl -sL "$xraycore_link" -o xray.zip
unzip -q xray.zip && rm -rf xray.zip
mv xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray

# Make Folder XRay
mkdir -p /var/log/xray/

# Stop port 80
sudo lsof -t -i tcp:80 -s tcp:listen > /dev/null 2>&1
sudo xargs kill > /dev/null 2>&1

# Generate certificates
rm -rf /root/.acme.sh
mkdir /root/.acme.sh
curl https://acme-install.netlify.app/acme.sh -o /root/.acme.sh/acme.sh
chmod +x /root/.acme.sh/acme.sh
/root/.acme.sh/acme.sh --upgrade --auto-upgrade
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d $domain --standalone -k ec-256
~/.acme.sh/acme.sh --installcert -d $domain --fullchainpath /usr/local/etc/xray/xray.crt --keypath /usr/local/etc/xray/xray.key --ecc
uuid1=$(cat /proc/sys/kernel/random/uuid)
uuid2=$(cat /proc/sys/kernel/random/uuid)
uuid3=$(cat /proc/sys/kernel/random/uuid)
uuid4=$(cat /proc/sys/kernel/random/uuid)
uuid5=$(cat /proc/sys/kernel/random/uuid)
uuid6=$(cat /proc/sys/kernel/random/uuid)
cat> /usr/local/etc/xray/config.json << END
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
       },
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid1}",
                        "flow": "xtls-rprx-direct",
                        "level": 0
#xray-vless-xtls
                    }
                ],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": 1310,
                        "xver": 1
                    },
                    {
                        "path": "/vmess-ws",
                        "dest": 1311,
                        "xver": 1
                    },
                    {
                        "path": "/vless-ws",
                        "dest": 1312,
                        "xver": 1
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "xtls",
                "xtlsSettings": {
                    "alpn": [
                        "http/1.1"
                    ],
                    "certificates": [
                        {
                            "certificateFile": "/usr/local/etc/xray/xray.crt",
                            "keyFile": "/usr/local/etc/xray/xray.key"
                        }
                    ]
                }
            }
        },
        {
            "port": 1310,
            "listen": "127.0.0.1",
            "protocol": "trojan",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid2}",
                        "password": "xxxxxx"
#trojan
                    }
                ],
                "fallbacks": [
                    {
                        "dest": 80
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "none",
                "tcpSettings": {
                    "acceptProxyProtocol": true
                }
            }
        },
        {
            "port": 1311,
            "listen": "127.0.0.1",
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid3}",
                        "alterId": 0,
                        "level": 0
#xray-vmess-tls
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {
                    "acceptProxyProtocol": true,
                    "path": "/vmess-ws"
                }
            }
        },
        {
            "port": 1312,
            "listen": "127.0.0.1",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid5}",
                        "level": 0
#xray-vless-tls
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {
                    "acceptProxyProtocol": true,
                    "path": "/vless-ws"
                }
            }
        }
    ],
    "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "dns": {
    "servers": [
      "1.1.1.1",
      "8.8.8.8",
      "localhost"
    ]
  },
  "stats": {},
  "api": {
    "services": [
      "StatsService"
    ],
    "tag": "api"
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  }
}
END
cat> /usr/local/etc/xray/none.json << END
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
            "port": 8443,
            "protocol": "vmess",
            "settings": {
            "clients": [
                {
                  "id": "${uuid4}",
                  "alterId": 0,
                  "level": 0
#xray-vmess-nontls
                }
            ]
        },
        "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {
                "path": "/vmess-ws",
                "headers": {
                   "Host": ""
                 }
             },
             "quicSettings": {}
          },
          "sniffing": {
             "enabled": true,
             "destOverride": [
                "http",
                "tls"
                ]
            }
        },
        {
            "port": 8442,
            "protocol": "vless",
            "settings": {
            "clients": [
                {
                  "id": "${uuid6}"
#xray-vless-nontls
                }
            ],
            "decryption": "none"
         },
         "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {
            "path": "/vless-ws",
            "headers": {
                "Host": ""
               }
            },
            "quicSettings": {}
          },
          "sniffing": {
              "enabled": true,
              "destOverride": [
                 "http",
                 "tls"
             ]
          }
       }
    ],
    "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "dns": {
    "servers": [
      "1.1.1.1",
      "8.8.8.8",
      "localhost"
    ]
  },
  "stats": {},
  "api": {
    "services": [
      "StatsService"
    ],
    "tag": "api"
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  }
}
END
# starting xray vmess ws tls core on sytem startup
cat> /etc/systemd/system/xray.service << END
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target

END

# starting xray vmess ws tls core on sytem startup
cat> /etc/systemd/system/xray@.service << END
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/%i.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target

END

iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 443 -j ACCEPT
iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 8442 -j ACCEPT
iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 8443 -j ACCEPT
iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 1310 -j ACCEPT
iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 1311 -j ACCEPT
iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 1312 -j ACCEPT
iptables -I INPUT -m state --state NEW -m udp -p udp --dport 443 -j ACCEPT
iptables -I INPUT -m state --state NEW -m udp -p udp --dport 80 -j ACCEPT
iptables -I INPUT -m state --state NEW -m udp -p udp --dport 8443 -j ACCEPT
iptables -I INPUT -m state --state NEW -m udp -p udp --dport 1310 -j ACCEPT
iptables -I INPUT -m state --state NEW -m udp -p udp --dport 1311 -j ACCEPT
iptables -I INPUT -m state --state NEW -m udp -p udp --dport 1312 -j ACCEPT
iptables-save > /etc/iptables.up.rules
iptables-restore -t < /etc/iptables.up.rules
netfilter-persistent save
netfilter-persistent reload

# enable xray tls
systemctl daemon-reload
systemctl enable xray.service
systemctl start xray.service
systemctl restart xray

# enable xray none tls
systemctl daemon-reload
systemctl enable xray@none
systemctl start xray@none
systemctl restart xray@none

# download script
cd /usr/bin
wget -O port-xray "https://raw.githubusercontent.com/tryoo127/scvpnv2/main/install/port-xray.sh"
wget -O port-trojan "https://raw.githubusercontent.com/tryoo127/scvpnv2/main/install/port-trojan.sh"
wget -O cert "https://raw.githubusercontent.com/tryoo127/scvpnv2/main/system/cert.sh"
wget -O mtrojan "https://raw.githubusercontent.com/tryoo127/scvpnv2/main/menu/mtrojan.sh"
wget -O mxray "https://raw.githubusercontent.com/tryoo127/scvpnv2/main/menu/mxray.sh"
chmod +x port-xray
chmod +x port-trojan
chmod +x cert
chmod +x mtrojan
chmod +x mxray

cd
rm -f ins-xray-deb10.sh
mv /root/domain /usr/local/etc/xray/domain
