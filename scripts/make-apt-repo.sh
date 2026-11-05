#!/usr/bin/env bash
# Turn a directory of packages into a signed flat apt repository.
#
# usage: scripts/make-apt-repo.sh <pool-dir> <out-dir>
#   <pool-dir>  *.deb and source packages (*.dsc plus the files it lists)
#   <out-dir>   becomes the repository (a static website)
# environment:
#   APT_SIGNING_KEY    ASCII-armored private signing key (required)
#   APT_KEEP_VERSIONS  newest versions kept per package (default 3)
# needs: apt-utils (apt-ftparchive), dpkg-dev, gnupg, xz-utils
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ $# -eq 2 ] || { echo "usage: $0 <pool-dir> <out-dir>" >&2; exit 2; }
pool="$(cd "$1" && pwd)"
out="$2"
keep="${APT_KEEP_VERSIONS:-3}"
[ -n "${APT_SIGNING_KEY:-}" ] || { echo "error: APT_SIGNING_KEY is not set" >&2; exit 1; }

rm -rf "${out}"
mkdir -p "${out}"
out="$(cd "${out}" && pwd)"
cp -a "${pool}/." "${out}/"

cd "${out}"

# keep only the newest versions of every binary package
python3 - "${keep}" <<'PYEOF'
import functools, glob, subprocess, sys, os
keep = int(sys.argv[1])
groups = {}
for f in glob.glob("*.deb"):
    name = subprocess.check_output(["dpkg-deb", "-f", f, "Package"], text=True).strip()
    ver = subprocess.check_output(["dpkg-deb", "-f", f, "Version"], text=True).strip()
    groups.setdefault(name, []).append((ver, f))
def newer_first(a, b):
    if subprocess.call(["dpkg", "--compare-versions", a[0], "gt", b[0]]) == 0:
        return -1
    if subprocess.call(["dpkg", "--compare-versions", a[0], "lt", b[0]]) == 0:
        return 1
    return 0
for name, items in groups.items():
    items.sort(key=functools.cmp_to_key(newer_first))
    for ver, f in items[keep:]:
        print("pruning old " + f)
        os.remove(f)
PYEOF

apt-ftparchive packages . > Packages
gzip -9kf Packages
xz -9kf Packages
if ls ./*.dsc >/dev/null 2>&1; then
	apt-ftparchive sources . > Sources
	gzip -9kf Sources
	xz -9kf Sources
fi

apt-ftparchive \
	-o APT::FTPArchive::Release::Origin="PB2 CAN Carrier" \
	-o APT::FTPArchive::Release::Label="PB2 CAN Carrier" \
	-o APT::FTPArchive::Release::Suite="stable" \
	-o APT::FTPArchive::Release::Codename="trixie" \
	-o APT::FTPArchive::Release::Architectures="arm64 all" \
	-o APT::FTPArchive::Release::Description="Packages for the PocketBeagle 2 CAN Carrier" \
	release . > Release

gnupg_home="$(mktemp -d)"
trap 'rm -rf "${gnupg_home}"' EXIT
export GNUPGHOME="${gnupg_home}"
printf '%s\n' "${APT_SIGNING_KEY}" | gpg --batch --quiet --import
fpr=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}')
[ -n "${fpr}" ] || { echo "error: no signing key imported" >&2; exit 1; }
gpg --batch --yes --pinentry-mode loopback --passphrase '' --default-key "${fpr}" --clearsign -o InRelease Release
gpg --batch --yes --pinentry-mode loopback --passphrase '' --default-key "${fpr}" --armor --detach-sign -o Release.gpg Release

# the published key and a landing page
cp "${here}/apt/pb2-can-carrier-archive-key.asc" "${here}/apt/pb2-can-carrier-archive-keyring.gpg" .
# the key the packages are installed with must be the key that signed
gpg --batch --quiet --no-default-keyring --keyring ./pb2-can-carrier-archive-keyring.gpg --verify InRelease 2>/dev/null \
	|| { echo "error: InRelease is not signed by apt/pb2-can-carrier-archive-keyring.gpg" >&2; exit 1; }

{
	echo '<!doctype html><meta charset="utf-8"><title>PB2 CAN Carrier packages</title>'
	echo '<h1>PB2 CAN Carrier package repository</h1>'
	echo '<p>Signed flat apt repository. Install pb2-can-carrier-support to configure a board; see the '
	echo '<a href="https://github.com/esacademy-de/pb2-can-carrier-linux-image/blob/master/apt/README.md">instructions</a>.</p><ul>'
	for f in *.deb *.dsc; do [ -e "$f" ] && echo "<li><a href=\"$f\">$f</a></li>"; done
	echo '</ul>'
} > index.html
touch .nojekyll
echo "repository ready in ${out}: $(find . -maxdepth 1 -name '*.deb' | wc -l) binary package file(s)"
