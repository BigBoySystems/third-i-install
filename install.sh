#!/bin/bash

set -e

mkdir -p src
mkdir -p pkg

# prepare installation of captive portal
if ! [ -e pkg/captive-portal ]; then
	(cd src && git clone git@github.com:BigBoySystems/captive-portal.git || true)
	(
		cd src/captive-portal && \
		cp -Rf . ../../pkg/captive-portal && \
		pipenv lock -r > ../../pkg/captive-portal/requirements.txt
	)
fi

# prepare installation of third-i backend
if ! [ -e pkg/third-i-backend ]; then
	(cd src && git clone git@github.com:BigBoySystems/third-i-backend.git || true)
	(
		cd src/third-i-backend && \
		cp -Rf . ../../pkg/third-i-backend && \
		pipenv lock -r > ../../pkg/third-i-backend/requirements.txt
	)
fi

# prepare installation of third-i frontend
if ! [ -e pkg/third-i-frontend ]; then
	(cd src && git clone git@github.com:BigBoySystems/third-i-frontend.git || true)
	(
		cd src/third-i-frontend && \
		npm install && \
		npm run build && \
		cp -Rf build ../../pkg/third-i-frontend
	)
fi

# copy stuff to stereopi
scp -r pkg "$@":/tmp/

ssh "$@" <<SSHEOF
{ # Prevent execution if this script was only partially downloaded

set -e -x

export DEBIAN_FRONTEND=noninteractive

mount -o remount,rw /
mount -o remount,rw /boot

# disable mandb
rm -f /var/lib/man-db/auto-update

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
TimeoutSec=10

[Install]
WantedBy=multi-user.target
EOF

# activate dhcpcd only for ethernet interface
# this is because we want complete control of the wifi interface
systemctl enable dhcpcd@eth0

# disable a few background processes we don't need
perl -p -i -e 's!^(?=
	./scripts/wlan-switch.php |
	./scripts/loop-mpegts-skybox.sh |
	./scripts/record-watcher.sh
)!#!mx' /opt/StereoPi/run.sh

# tweak config
perl -p -i -e 's!^(ws_enabled|usb_enabled)=0!\$1=1!m' \
	/boot/stereopi.conf
perl -p -i -e 's!^(video_width)=.*!\$1=1920!m' /boot/stereopi.conf
perl -p -i -e 's!^(video_height)=.*!\$1=1080!m' /boot/stereopi.conf

# re-activate journald logs
perl -p -i -e 's!^#?(Storage)=.*!\$1=volatile!m' /etc/systemd/journald.conf

# tweak recording
perl -p -i -e 's!"Mic" 100!"Mic" "50%"!m' \
	/opt/StereoPi/scripts/loop-record.sh
perl -p -i -e 's!voaacenc bitrate=128000!voaacenc bitrate=320000!m' \
	/opt/StereoPi/scripts/loop-record.sh
perl -p -i -e 's!audio/x-raw,channels=1,depth=16,width=16,rate=44100!audio/x-raw,channels=2,depth=16,width=16,rate=48000!m' \
	/opt/StereoPi/scripts/loop-record.sh
perl -p -i -e 's!date \+%Y%m%d%-H%M%S!date \+%Y%m%d-%H%M%S!m' \
	/opt/StereoPi/scripts/loop-record.sh
perl -p -i -e 's!record-!experience-!m' \
	/opt/StereoPi/scripts/loop-record.sh
perl -p -i -e 's!echo "Recording with audio"!\$&;RECPATH=\\\$(date +"/media/DCIM/%Y/%m/%d");mkdir -p "\\\$RECPATH";killall -9 arecord opusenc!m' \
	/opt/StereoPi/scripts/loop-record.sh

# tweak photo shooting
perl -p -i -e "s#'/media/DCIM/';#'/media/DCIM/'.date('Y').'/'.date('m').'/'.date('d').'/';shell_exec('mkdir -p '.\\\\\\\$path);#m" \
	/var/www/html/make_photo.php

# change timezone
echo Europe/Brussels > /etc/timezone
ln -sf /usr/share/zoneinfo/Europe/Brussels /etc/localtime

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

	#log_format  main  '\\\$remote_addr - \\\$remote_user [\\\$time_local] "\\\$request" '
	#                  '\\\$status \\\$body_bytes_sent "\\\$http_referer" '
	#                  '"\\\$http_user_agent" "\\\$http_x_forwarded_for"';

	#access_log logs/access.log main;

	sendfile on;
	#tcp_nopush on;

	#keepalive_timeout 0;
	keepalive_timeout 65;

	#gzip on;

	server {
		listen 80;
		listen [::]:80;
		server_name third-i.local;

		location / {
			root /var/www/html;
		}

		location /api/sound {
			rewrite ^/api/(.*)$ /\\\$1 break;
			proxy_pass http://localhost:8000;
			proxy_set_header Upgrade \\\$http_upgrade;
			proxy_set_header Connection "Upgrade";
			proxy_set_header Host \\\$host;
		}

		location /api {
			rewrite ^/api/(.*)$ /\\\$1 break;
			proxy_pass http://localhost:8000;
		}

		location /media/ {
			internal;
			alias /media/;
		}

		location /files {
			proxy_pass http://localhost:8000;
		}
	}

	server {
		listen 80 default_server;
		listen [::]:80 default_server;
		server_name _;

		return 301 http://third-i.local;
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

		return 301 http://third-i.local;
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
	's/^<\?php/$&\nif (!isset(\\\$_SERVER["HTTP_HOST"])) {parse_str(\\\$argv[1], \\\$_POST);}/g' \
	/var/www/html/saveconfig.php

# we need extra space
mount -t tmpfs none /var/lib/apt/lists

# install opus-tools
if ! which pip3 &> /dev/null; then
	apt-get update
	apt-get install -y --no-install-recommends opus-tools
	apt-get -q clean
fi

# install pip
if ! which pip3 &> /dev/null; then
	apt-get update
	apt-get install -y --no-install-recommends python3-pip python3-dev python3-setuptools
	apt-get -q clean
fi

# install captive portal
if ! which captive-portal &> /dev/null; then
	cd /tmp/pkg/captive-portal
	pip3 install -r requirements.txt
	cp -fv captive-portal.py /usr/local/sbin/captive-portal
	cat - > /lib/systemd/system/captive-portal@.service <<EOF
[Unit]
Description=Third-I Captive Portal on %I
Wants=network.target
Before=network.target
After=sys-subsystem-net-devices-%i.device

[Service]
ExecStart=/usr/local/sbin/captive-portal --unix /run/captive-portal-%I.sock %I
KillMode=process
Restart=always

[Install]
WantedBy=multi-user.target
EOF
	chmod 644 /lib/systemd/system/captive-portal@.service
	systemctl enable captive-portal@wlan0
fi

# install third-i backend
if ! which third-i-backend &> /dev/null; then
	cd /tmp/pkg/third-i-backend
	pip3 install -r requirements.txt
	cp -fv third-i-backend.py /usr/local/sbin/third-i-backend
	cat - > /lib/systemd/system/third-i-backend@.service <<EOF
[Unit]
Description=Third-I Backend on %I
Requires=network.target
After=network.target captive-portal@%i.service

[Service]
ExecStart=/usr/local/sbin/third-i-backend --host 127.0.0.1 --port 8000 --serial /dev/ttyAMA0 --bauds 1200 /run/captive-portal-%I.sock
KillMode=process
Restart=always

[Install]
WantedBy=multi-user.target
EOF
	chmod 644 /lib/systemd/system/third-i-backend@.service
	systemctl enable third-i-backend@wlan0
fi

# install frontend
if ! [ -e /var/www/html/index.html ]; then
	cp -fvR /tmp/pkg/third-i-frontend/* /var/www/html/
fi

# change hostname
echo -n third-i > /etc/hostname

sync
reboot

} # End of wrapping
SSHEOF
