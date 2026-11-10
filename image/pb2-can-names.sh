#!/bin/sh
# Name the three CAN interfaces after the connectors: can0 = CAN A, can1 = CAN B,
# can2 = CAN C. The kernel numbers them in probe order, which here is the
# reverse (the MCU controllers probe before the main-domain one), so the
# names are swapped once, early in boot, before anything uses them.
#
# The controllers are told apart by their platform device (the address of the
# controller), so this stays correct whatever the probe order is.
#   20701000.can (main_mcan0) = CAN A
#   4e18000.can  (mcu_mcan1)  = CAN B
#   4e08000.can  (mcu_mcan0)  = CAN C
# An interface that is already up is left alone (it cannot be renamed).
set -u

want_name() {
	case "$1" in
	20701000.can) echo can0 ;;
	4e18000.can) echo can1 ;;
	4e08000.can) echo can2 ;;
	esac
}

# Give interface $1 the final name $2. While the names are being swapped the
# kernel hands out free "canN" names to any CAN interface that appears at that
# moment (a USB adapter such as the PCAN-USB FD registers a few seconds after
# the controllers), so the wanted name may be taken by such a foreign
# interface. It is moved to the next free name from can3 up, and the rename is
# retried because another interface may appear in between.
give_name() {
	k=0
	while [ "$k" -lt 5 ]; do
		if [ -e "/sys/class/net/$2" ]; then
			n=3
			while [ -e "/sys/class/net/can$n" ]; do n=$((n + 1)); done
			ip link set "$2" name "can$n" 2>/dev/null
		fi
		ip link set "$1" name "$2" 2>/dev/null && return 0
		k=$((k + 1))
	done
	echo "pb2-can-names: cannot rename $1 to $2" >&2
}

# The controllers are built into the kernel, so they exist at boot; the short
# wait only covers a build where they are modules.
i=0
while [ "$i" -lt 50 ]; do
	n=0
	for dev in 20701000.can 4e18000.can 4e08000.can; do
		for d in /sys/class/net/*/device; do
			[ "$(basename "$(readlink -f "$d")")" = "$dev" ] && n=$((n + 1))
		done
	done
	[ "$n" -ge 3 ] && break
	i=$((i + 1))
	sleep 0.2
done

# Pass 1: move every interface that has to change to a temporary name, so that
# the swap (can0 <-> can2) cannot collide. Pass 2: give the final names.
for pass in 1 2; do
	for d in /sys/class/net/*/device; do
		cur=$(basename "$(dirname "$d")")
		dev=$(basename "$(readlink -f "$d")")
		new=$(want_name "$dev")
		[ -n "$new" ] || continue
		if [ "$pass" = 1 ]; then
			[ "$cur" = "$new" ] && continue
			ip link set "$cur" name "pb2tmp-$new" ||
				echo "pb2-can-names: cannot rename $cur (is it up?)" >&2
		else
			case "$cur" in
			pb2tmp-*) give_name "$cur" "$new" ;;
			esac
		fi
	done
done
exit 0
