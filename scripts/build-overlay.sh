#!/usr/bin/env bash
# Compile the carrier overlay against the pinned BeagleBoard device-tree
# commit (manifests/sources.lock), check that it merges into the PB2 base
# tree, and copy the .dtbo to <outdir>.
#
# usage: scripts/build-overlay.sh <outdir> [workdir]
# needs: device-tree-compiler, git, make, a C compiler
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ $# -ge 1 ] || { echo "usage: $0 <outdir> [workdir]" >&2; exit 2; }
outdir="$1"
work="${2:-$(mktemp -d)}"
overlay="${here}/dts/k3-am62-pocketbeagle2-can-carrier.dtso"

commit=$(sed -n '/^\[device-tree\]/,/^\[/{/^commit = /p}' "${here}/manifests/sources.lock" \
	| head -1 | sed -E 's/^commit = "([0-9a-f]+)"/\1/')
[ -n "${commit}" ]

if [ ! -d "${work}/dts-repo/.git" ]; then
	git clone --branch v6.18.x https://github.com/beagleboard/BeagleBoard-DeviceTrees.git "${work}/dts-repo"
fi
git -C "${work}/dts-repo" checkout -q "${commit}"
cp "${overlay}" "${work}/dts-repo/src/arm64/overlays/"
make -C "${work}/dts-repo" all_arm64 >/dev/null
fdtoverlay \
	-i "${work}/dts-repo/src/arm64/ti/k3-am62-pocketbeagle2.dtb" \
	-o "${work}/merged.dtb" \
	"${work}/dts-repo/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier.dtbo"
mkdir -p "${outdir}"
cp "${work}/dts-repo/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier.dtbo" "${outdir}/"
echo "${outdir}/k3-am62-pocketbeagle2-can-carrier.dtbo"
