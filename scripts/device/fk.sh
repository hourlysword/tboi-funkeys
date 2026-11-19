#!/bin/bash
# SPDX-License-Identifier: MIT
# Runs a command on the FunKey over SSH, or copies files to it, through the USB network (the usbnet OPK of my other FunKey S projects; launch
# "USB network" on the console after each boot). The FunKey's SSH server makes itself a new host key at every boot, so
# host keys aren't checked; BatchMode: never stop at a password prompt.
#
# usage: scripts/device/fk.sh <command...>            run a command (sh on the console)
#        scripts/device/fk.sh --push <file...> <dir>  copy files into a directory on the console
#        scripts/device/fk.sh --pull <path> <dir>     copy a file or directory from the console
# TFK_DEVICE (default 192.168.137.2), TFK_DEVICE_KEY (default ~/.ssh/funkey_claude).
set -euo pipefail

device="${TFK_DEVICE:-192.168.137.2}"
key="${TFK_DEVICE_KEY:-$HOME/.ssh/funkey_claude}"
options=(-i "$key" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
	-o ConnectTimeout=10)

case "${1:-}" in
	--push)
		shift
		[ $# -ge 2 ] || { echo "usage: fk.sh --push <file...> <dir>" >&2; exit 1; }
		dir="${!#}"
		files=("${@:1:$#-1}")
		ssh "${options[@]}" "root@$device" "mkdir -p '$dir'"
		# (The console has no sftp server: scp -O uses the old protocol, through ssh and scp on the console.)
		scp -O -q "${options[@]}" "${files[@]}" "root@$device:$dir/"
		;;
	--pull)
		[ $# -eq 3 ] || { echo "usage: fk.sh --pull <path> <dir>" >&2; exit 1; }
		mkdir -p "$3"
		scp -O -q -r "${options[@]}" "root@$device:$2" "$3/"
		;;
	"")
		echo "usage: fk.sh <command...> | --push <file...> <dir> | --pull <path> <dir>" >&2
		exit 1
		;;
	*)
		ssh "${options[@]}" "root@$device" "$*"
		;;
esac
