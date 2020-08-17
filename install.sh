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

# we need extra space
mount -t tmpfs none /var/lib/apt/lists

# install pipenv
apt-get update
apt-get install -y --no-install-recommends python3-pip python3-dev
/usr/bin/pip3 install -U pip
apt-get remove -y --auto-remove python3-pip
apt-get -q clean
/usr/local/bin/pip install -U pipenv
# no idea what this is but seems required with Python 3.5
/usr/local/bin/pip install -U idna_ssl typing-extensions

# install captive portal
cd /tmp
git clone https://github.com/BigBoySystems/captive-portal.git
cd captive-portal
./install.sh
systemctl enable captive-portal@wlan0

sync
reboot

} # End of wrapping
