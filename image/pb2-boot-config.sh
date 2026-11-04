#!/bin/bash
# Apply /boot/firmware/pb2-config.txt (SD card FAT partition) to the running system.
#
# Runs at every boot from pb2-boot-config.service, ordered before ssh.service.
# Can also be run by hand after editing the file; with --apply-now it starts,
# stops or reloads ssh.service immediately instead of waiting for the next boot.
#
# Keys (see image/pb2-config.txt for the user-facing documentation):
#   ssh=enabled|disabled              default enabled (also when file/key missing)
#   ssh_password_auth=yes|no          default yes; "no" is ignored without an authorized key
#
# Mechanisms used: Debian's /etc/ssh/sshd_not_to_be_run (ssh.service has
# ConditionPathExists=!/etc/ssh/sshd_not_to_be_run) and an sshd_config.d drop-in.
set -u

CONF=${PB2_CONFIG:-/boot/firmware/pb2-config.txt}
NOT_TO_BE_RUN=/etc/ssh/sshd_not_to_be_run
DROPIN=/etc/ssh/sshd_config.d/10-pb2-boot-config.conf
APPLY_NOW=0
[ "${1:-}" = "--apply-now" ] && APPLY_NOW=1

# stdout only: under systemd it goes to the journal, from a shell to the terminal
log() { echo "pb2-boot-config: $*"; }

# value of KEY from CONF: last assignment wins, '#' comments and CRs stripped, lower-cased
get() {
	[ -r "$CONF" ] || return 0
	sed -e 's/\r$//' -e 's/#.*//' "$CONF" | awk -F= -v k="$1" '
		{ key=$1; gsub(/^[ \t]+|[ \t]+$/, "", key)
		  if (tolower(key) == k) { v=substr($0, index($0, "=")+1); gsub(/^[ \t]+|[ \t]+$/, "", v); val=tolower(v) } }
		END { print val }'
}
is_true()  { case "$1" in 1|yes|y|true|on|enable|enabled) return 0;; esac; return 1; }
is_false() { case "$1" in 0|no|n|false|off|disable|disabled) return 0;; esac; return 1; }

if [ -r "$CONF" ]; then log "reading $CONF"; else log "$CONF not found, using defaults"; fi

# ---------------------------------------------------------------- ssh on/off
ssh_val=$(get ssh)
ssh_on=1
if [ -z "$ssh_val" ]; then
	:
elif is_true "$ssh_val"; then
	:
elif is_false "$ssh_val"; then
	ssh_on=0
else
	log "WARNING: unrecognised ssh='$ssh_val' (use enabled|disabled), keeping the default: enabled"
fi
if [ "$ssh_on" = 1 ]; then
	rm -f "$NOT_TO_BE_RUN"
	log "ssh: enabled"
else
	touch "$NOT_TO_BE_RUN"
	log "ssh: disabled"
fi

# ----------------------------------------------------- ssh password logins
pw_val=$(get ssh_password_auth)
pw_off=0
if [ -z "$pw_val" ] || is_true "$pw_val"; then
	:
elif is_false "$pw_val"; then
	pw_off=1
else
	log "WARNING: unrecognised ssh_password_auth='$pw_val' (use yes|no), keeping the default: yes"
fi
has_key=0
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
	[ -s "$f" ] && has_key=1
done
mkdir -p /etc/ssh/sshd_config.d
if [ "$pw_off" = 1 ] && [ "$has_key" = 1 ]; then
	printf '# written by pb2-boot-config from %s\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' "$CONF" > "$DROPIN"
	if ! /usr/sbin/sshd -t 2>/dev/null; then
		log "WARNING: sshd -t rejected the drop-in, removing it (password logins stay enabled)"
		rm -f "$DROPIN"
	else
		log "ssh password logins: disabled (public key only)"
	fi
else
	[ "$pw_off" = 1 ] && log "WARNING: ssh_password_auth=no ignored: no authorized_keys found (would lock you out)"
	rm -f "$DROPIN"
	log "ssh password logins: enabled"
fi

# ----------------------------------------------------------- apply right now
if [ "$APPLY_NOW" = 1 ]; then
	if [ "$ssh_on" = 1 ]; then
		systemctl restart ssh.service && log "ssh.service (re)started"
	else
		systemctl stop ssh.service && log "ssh.service stopped"
	fi
fi
exit 0
