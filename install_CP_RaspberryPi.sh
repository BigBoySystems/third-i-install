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

{ # Prevent execution if this script was only partially downloaded
set -e -x
export DEBIAN_FRONTEND=noninteractive
mount -o remount,rw /
mount -o remount,rw /boot

# disable mandb
rm -f /var/lib/man-db/auto-update
# we want to make sure all of these services are stopped
systemctl disable dnsmasq
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



sync
reboot
} # End of wrapping
SSHEOF