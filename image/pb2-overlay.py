#!/usr/bin/python3
"""pb2-overlay - switch the optional device-tree overlays of the PB2 CAN Carrier.

  pb2-overlay list
  pb2-overlay enable <name>      e.g. spidev
  pb2-overlay disable <name>

An optional overlay is the file k3-am62-pocketbeagle2-can-carrier-<name>.dtbo
in /boot/firmware/overlays/ (shipped by the pb2-can-carrier-support package).
"enable" appends it to the "fdtoverlays" line of the PB2 CAN Carrier boot entry
in /boot/firmware/extlinux/extlinux.conf (after the carrier overlay, which has
to come first), "disable" removes it again. U-Boot reads that file at boot, so
a change takes effect at the next reboot. The first change keeps a copy of the
original file as extlinux.conf.pb2-overlay.bak.
"""
import os
import re
import shutil
import sys

EXTLINUX = os.environ.get("PB2_EXTLINUX", "/boot/firmware/extlinux/extlinux.conf")
OVERLAYS = os.environ.get("PB2_OVERLAYS", "/boot/firmware/overlays")
PREFIX = "k3-am62-pocketbeagle2-can-carrier"
BASE = "/overlays/%s.dtbo" % PREFIX
LINE = re.compile(r"^(\s*fdtoverlays\s+)(.*?)(\s*)$")


def die(msg):
    sys.exit("pb2-overlay: " + msg)


def available():
    try:
        names = os.listdir(OVERLAYS)
    except OSError:
        return []
    out = []
    for f in sorted(names):
        m = re.fullmatch(re.escape(PREFIX) + r"-(.+)\.dtbo", f)
        if m:
            out.append(m.group(1))
    return out


def load():
    try:
        with open(EXTLINUX, newline="") as f:
            lines = f.read().split("\n")
    except OSError as e:
        die("cannot read %s: %s" % (EXTLINUX, e))
    for i, ln in enumerate(lines):
        m = LINE.match(ln)
        if m and BASE in m.group(2).split():
            return lines, i, m
    die("no boot entry with %s in the fdtoverlays line of %s; "
        "edit the file by hand" % (BASE, EXTLINUX))


def main(argv):
    if len(argv) < 2 or argv[1] not in ("list", "enable", "disable") \
            or (argv[1] != "list" and len(argv) != 3) or (argv[1] == "list" and len(argv) != 2):
        print(__doc__.strip().split("\n\n")[0])
        sys.exit(2)
    lines, idx, m = load()
    active = m.group(2).split()
    avail = available()
    cmd = argv[1]
    if cmd == "list":
        if not avail:
            print("no optional overlays installed")
        for name in avail:
            path = "/overlays/%s-%s.dtbo" % (PREFIX, name)
            print("%-12s %s" % (name, "enabled" if path in active else "disabled"))
        return
    name = argv[2]
    if name not in avail:
        die("unknown overlay '%s' (available: %s)" % (name, ", ".join(avail) or "none"))
    path = "/overlays/%s-%s.dtbo" % (PREFIX, name)
    if cmd == "enable":
        if path in active:
            print("%s is already enabled" % name)
            return
        new = active + [path]
    else:
        if path not in active:
            print("%s is already disabled" % name)
            return
        new = [p for p in active if p != path]
    if os.geteuid() != 0:
        die("must be run as root (sudo pb2-overlay %s %s)" % (cmd, name))
    bak = EXTLINUX + ".pb2-overlay.bak"
    if not os.path.exists(bak):
        shutil.copyfile(EXTLINUX, bak)
    lines[idx] = m.group(1) + " ".join(new) + m.group(3)
    tmp = EXTLINUX + ".pb2-new"
    with open(tmp, "w", newline="") as f:
        f.write("\n".join(lines))
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, EXTLINUX)
    print("%s %sd; takes effect at the next boot (sudo reboot)" % (name, cmd))


if __name__ == "__main__":
    main(sys.argv)
