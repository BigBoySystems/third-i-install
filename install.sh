#!/bin/sh

{ # Prevent execution if this script was only partially downloaded

set -e -x

export DEBIAN_FRONTEND=noninteractive

mount -o remount,rw /

# we want to make sure all of these services are stopped
# not sure why dnsmasq is enabled... I think it's a leftover
systemctl disable dnsmasq
# this is the webapp hosted on port 80
systemctl disable nginx
# this is the fastcgi process for the php scripts (only used by the webapp)
systemctl disable php7.0-fpm
# this is the global dhcpcd, we don't want it to interfere with the wifi
# interfaces
systemctl disable dhcpcd

# a systemd service script of a modern dhcpcd I just copied and adapted
# this is different than dhcpcd.service as it allows selecting a specific
# interface
cat - > /lib/systemd/system/dhcpcd@.service <<EOF
[Unit]
Description=dhcpcd on %I
Wants=network.target
Before=network.target
BindsTo=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device

[Service]
Type=forking
PIDFile=/run/dhcpcd-%I.pid
ExecStart=/usr/lib/dhcpcd5/dhcpcd -q -w %I
ExecStop=/sbin/dhcpcd -x %I

[Install]
WantedBy=multi-user.target
EOF

# activate dhcpcd only for ethernet interface
# this is because we want complete control of the wifi interface
systemctl enable dhcpcd@eth0

# disable a few background processes we don't need
perl -p -i -e 's!^(?=
	./scripts/wlan-switch.php |
	./scripts/loop-mpegts-skybox.sh
)!#!mx' /opt/StereoPi/run.sh

# tweak config
perl -p -i -e 's!^(ws_enabled|audio_enabled|usb_enabled)=0!$1=1!mx' /opt/StereoPi/run.sh

# update nginx configuration
cat - > /etc/nginx/nginx.conf <<EOF
#user html;
worker_processes  1;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

#pid        logs/nginx.pid;


events {
	worker_connections  1024;
}


http {
	include mime.types;
	default_type application/octet-stream;

	#log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
	#                  '$status $body_bytes_sent "$http_referer" '
	#                  '"$http_user_agent" "$http_x_forwarded_for"';

	#access_log logs/access.log main;

	sendfile on;
	#tcp_nopush on;

	#keepalive_timeout 0;
	keepalive_timeout 65;

	#gzip on;

	server {
		listen 80;
		listen [::]:80;
		server_name stereopi.local;

		location / {
			root /var/www/html;
			try_files $uri $uri/ /index.html;
		}

		location /api {
			rewrite ^/api/(.*)$ /$1 break;
			proxy_pass http://localhost:8000/;
		}
	}

	server {
		listen 80 default_server;
		listen [::]:80 default_server;
		server_name _;

		return 301 http://stereopi.local;
	}

	server {
		listen 443 ssl;
		server_name localhost;

		ssl_certificate nginx-selfsigned.crt;
		ssl_certificate_key nginx-selfsigned.key;

		ssl_session_cache shared:SSL:1m;
		ssl_session_timeout 5m;

		ssl_ciphers HIGH:!aNULL:!MD5;
		ssl_prefer_server_ciphers on;

		return 301 http://stereopi.local;
	}
}
EOF
cat - > /etc/nginx/nginx-selfsigned.crt <<EOF
-----BEGIN CERTIFICATE-----
MIIDlzCCAn+gAwIBAgIUIDjURUkhbL577MVQQyCXu9zT+SYwDQYJKoZIhvcNAQEL
BQAwWzELMAkGA1UEBhMCQVUxEzARBgNVBAgMClNvbWUtU3RhdGUxITAfBgNVBAoM
GEludGVybmV0IFdpZGdpdHMgUHR5IEx0ZDEUMBIGA1UEAwwLMTkyLjE2OC4xLjEw
HhcNMjAwODI0MTU0NzQ2WhcNMjEwODI0MTU0NzQ2WjBbMQswCQYDVQQGEwJBVTET
MBEGA1UECAwKU29tZS1TdGF0ZTEhMB8GA1UECgwYSW50ZXJuZXQgV2lkZ2l0cyBQ
dHkgTHRkMRQwEgYDVQQDDAsxOTIuMTY4LjEuMTCCASIwDQYJKoZIhvcNAQEBBQAD
ggEPADCCAQoCggEBALVrC2asDOH66QXtIiumP7PJfIZpMTfVeyTYwQh4CAtgnDOI
OBFE2X+/78/RuAxvkdDBXY5PyOmb5qjLnBRmCjk4a6kZYLgsBHJNAtwvuYyNE0bF
gUR/b8nOplBHIlBjx+gslDpHZrEtiy8m3vyszv1HkS5dFnz+QkDOKrHx7WsOWxdh
8yfm7sEkuWKXnIV/qRgP8S+toNDEkAPKLZGL6lKA3C/Ktituj01W2QTrRxoU/79O
MD/ljsGKbT+EeZpizoItuFeUR/oAFtmacISQfG+gwOfn+1rfi6vt7xZ97qGLX41u
XO3Yj3sIxbWuisUdlwbmKD2yzpWI2C3japQ/VckCAwEAAaNTMFEwHQYDVR0OBBYE
FPW4I9YOeR3h3v9swXmf7Ikh4ntLMB8GA1UdIwQYMBaAFPW4I9YOeR3h3v9swXmf
7Ikh4ntLMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAC2A+4Gi
65Q0C0lLo/97Om3njLJo9xs39V8fAYpgaRzQDcakwThb75Ks2+gwW7lErnZ3zIU6
kg/u8WefzRjrsI257FAaxbrKl5uafZEjoV6JXTOsnj/aM4tqlLobViaZ8I7TITQ2
EqygicHBuHJS0gukb5vdVjEXbK1PJaEQgVjagMwVeyIqC/CoYKg3FhjUCF4g1OAP
OduF6mW+tcKBwJkN0K5sXQ47uzTXFq3qPYeSt5gGPOM/EqIRnPJ784DlZ5904DCM
NAuEaQJyB+v5M6mNgTu40YuF3WDH2ozKLFpJhZHg3FclSVkGscRuoJ+f2irpGYNH
eGx/TqYEZPS2B7E=
-----END CERTIFICATE-----
EOF
cat - > /etc/nginx/nginx-selfsigned.key <<EOF
-----BEGIN PRIVATE KEY-----
MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQC1awtmrAzh+ukF
7SIrpj+zyXyGaTE31Xsk2MEIeAgLYJwziDgRRNl/v+/P0bgMb5HQwV2OT8jpm+ao
y5wUZgo5OGupGWC4LARyTQLcL7mMjRNGxYFEf2/JzqZQRyJQY8foLJQ6R2axLYsv
Jt78rM79R5EuXRZ8/kJAziqx8e1rDlsXYfMn5u7BJLlil5yFf6kYD/EvraDQxJAD
yi2Ri+pSgNwvyrYrbo9NVtkE60caFP+/TjA/5Y7Bim0/hHmaYs6CLbhXlEf6ABbZ
mnCEkHxvoMDn5/ta34ur7e8Wfe6hi1+Nblzt2I97CMW1rorFHZcG5ig9ss6ViNgt
42qUP1XJAgMBAAECggEAFVCiYknMqbBlOIEIBsDdsy31J4WsdrbqZQXiiDAyIcQU
FinnDIBeXZgbgPtO+IcTRsexSkste+UJUMO7btoeUWLDo3aL2pexXgyWTXB+CHl6
zlHeQkIGzFsvRzdUXMWcczbpo39IHYEQXVXf1SgombGS6TOetMja1+phMc8O6gjv
HteSffYLWPR2Q2KJG+2Unn4mK1vYsPB16FzGAmEv7EavwjVumlnUgNtmLY8JP19H
GYWsVS8kWQH7acN3uIQwvN9eO6u5B+kwJxZ7wtMLQMfJpnXoIcRunelffh8tdrl/
myCrBZUq9UrdUJTmqgi3pdKxmmQPwrtkSJoj6qH/kQKBgQDX3zThOMqYYply/lo8
W86/TqcTKiOw4sOuqYlengrtlMz40zG93tVLhBkM20hhnG2/DX1m5q8OYPPoJU6D
ur2bSDF8DVcklWhd69W3TEieGp1GZZhkaaBZTfJDu8YOHI97jR3lIuf9jP3xWr09
DpYqNu4pVsDLA7v2zEV0b6CgNwKBgQDXJEV+zKYzj1tK6w/grex5JPIWfbEqrw/y
NuwmWhBFTaQPv+Y1WPO76sHivRQbq2ImeDTdM5hUOHs+XJvHdjCHXzfX6rBqJ3pU
g7CuRXx2V5J95FZJJ+LCDFRTM2X4huFZRmOt+gLFcm/QHjoSkbZQRMlWGwVbx7Aw
HB4CwEi5/wKBgQCH9yBZUunX/RJlaWrwZWrc9+8nlP0R5mIV2taY77Y2WeiYOH01
9+okPDmC7YKzaFF/akG31EgiKFK3vveq5K2T5m60kbp3Yltv/KCJaNS8MEsrEcZg
SF8koIGcw+JE9RwyV3mi3s971ZgEsoBKuqs+P4bWJrwbomh7U8HTSpPDFQKBgQCp
Y9WT0G3LisPGaO1HaakWeRBixPQJN2zGuJeWWrMU3dyeyejnd/HvsxaU/2olnvrY
byywPT9ikFX489FzaosrCr1dM1tTOWIHyOgDTpKAWtLsbCvDzbOsNSjvmThgRVKI
h/NTt9UWwNNoeWQf2rpA2Ofs87l0WfVO69R1NhAM4QKBgQCTwJ1C1zYy/4J8XpbC
91BqMlI0m812msS+0DN0lVT7dnt+dgVaTkDQJR1fHhK8Aksezh65IXKWCwQ7egfJ
LN5QWPG63lEWC2kAdhdgeH4OPYFgvPA9wbctffgx6O6cF2D3i0I3+zeSQ+tNuF/Q
GnX7zk8I3TSf3cyBKA2MuEztQQ==
-----END PRIVATE KEY-----
EOF
chmod 600 /etc/nginx/nginx-selfsigned.key

# hijack saveconfig.php to accept arguments from command line
perl -p -i -e \
	's/^<\?php/$&\nif (!isset(\$_SERVER["HTTP_HOST"])) {parse_str(\$argv[1], \$_POST);}/g' \
	/var/www/html/saveconfig.php

# we need extra space
mount -t tmpfs none /var/lib/apt/lists

# install pipenv
if ! which pipenv &> /dev/null; then
	apt-get update
	apt-get install -y --no-install-recommends python3-pip python3-dev
	/usr/bin/pip3 install -U pip
	apt-get remove -y --auto-remove python3-pip
	apt-get -q clean
	/usr/local/bin/pip install -U pipenv
	# no idea what this is but seems required with Python 3.5
	/usr/local/bin/pip install -U idna_ssl typing-extensions
fi

# install captive portal
if ! which captive-portal &> /dev/null; then
	cd /tmp
	git clone https://github.com/BigBoySystems/captive-portal.git
	cd captive-portal
	./install.sh
	systemctl enable captive-portal@wlan0
fi

# install third-i backend
if ! which third-i-backend &> /dev/null; then
	cd /tmp
	mkdir -p ~/.ssh
	ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
	git clone git@github.com:BigBoySystems/third-i-backend.git
	cd third-i-backend
	./install.sh
	systemctl enable third-i-backend@wlan0
fi

sync
reboot

} # End of wrapping
