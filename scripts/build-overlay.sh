#!/usr/bin/env bash
# Compile the carrier overlay and the optional child overlays
# (dts/optional-spi-children/*.dtso) against the pinned BeagleBoard
# device-tree commit (manifests/sources.lock), check that they merge into the
# PB2 base tree (carrier overlay first), and copy the .dtbo files to <outdir>.
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
ovdir="${work}/dts-repo/src/arm64/overlays"
cp "${overlay}" "${ovdir}/"
children=()
for f in "${here}"/dts/optional-spi-children/*.dtso; do
	[ -f "${f}" ] || continue
	cp "${f}" "${ovdir}/"
	children+=("${ovdir}/$(basename "${f%.dtso}").dtbo")
done
make -C "${work}/dts-repo" all_arm64 >/dev/null
fdtoverlay \
	-i "${work}/dts-repo/src/arm64/ti/k3-am62-pocketbeagle2.dtb" \
	-o "${work}/merged.dtb" \
	"${ovdir}/k3-am62-pocketbeagle2-can-carrier.dtbo" "${children[@]}"
mkdir -p "${outdir}"
cp "${ovdir}/k3-am62-pocketbeagle2-can-carrier.dtbo" "${children[@]}" "${outdir}/"
echo "${outdir}/k3-am62-pocketbeagle2-can-carrier.dtbo"
for c in "${children[@]}"; do
	echo "${outdir}/$(basename "${c}")"
done
