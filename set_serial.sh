#!/bin/bash

device=$1
serial=$2

if [ -z "$serial" ]; then
	echo "Missing argument: serial number"
	exit 1
fi

if [ -z "$device" ]; then
	echo "Missing argument: device path"
	exit 1
fi

set -e -x

mount_dir=$(mktemp -d set_serial."$serial".XXXX)
mount "$device" "$mount_dir"
echo "$serial" > "$mount_dir"/serial
umount "$mount_dir"
