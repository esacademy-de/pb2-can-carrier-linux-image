# PB2 CAN Carrier: tell the kernel the real window size of a serial terminal.
#
# A serial line has no way to carry the terminal's size (SSH sends it with
# every window change), so tty rows/columns stay 0 and full-screen programs
# such as mc, htop or nano fall back to 24x80. This asks the terminal for its
# size with a cursor-position report (park the cursor in the far corner, ask
# where it is, put it back) and applies the answer with stty.
#
# Runs at every login on a serial tty. After resizing the terminal window,
# run "pb2-serial-size" again. Does nothing on SSH, on a non-tty, or when the
# terminal does not answer within 2 seconds.

pb2_serial_size() {
	[ -n "${BASH_VERSION:-}" ] || return 0
	[ -t 0 ] && [ -t 1 ] || return 0
	case "$(tty 2>/dev/null)" in
	/dev/ttyS* | /dev/ttyUSB* | /dev/ttyACM* | /dev/ttyAMA*) ;;
	*) return 0 ;;
	esac

	local saved reply rows cols
	saved=$(stty -g) || return 0
	stty -echo -icanon min 1 time 0
	printf '\0337\033[999;999H\033[6n\0338'
	reply=
	IFS= read -r -s -d R -t 2 reply
	stty "$saved"

	# reply is ESC [ rows ; cols
	reply=${reply#*[}
	rows=${reply%%;*}
	cols=${reply#*;}
	case "$rows$cols" in
	'' | *[!0-9]*) return 0 ;;
	esac
	[ "$rows" -gt 0 ] && [ "$cols" -gt 0 ] && stty rows "$rows" cols "$cols"
	return 0
}

alias pb2-serial-size=pb2_serial_size
pb2_serial_size
