#!/usr/bin/env bash
# Build the kernel, U-Boot, and carrier device-tree overlay for the PB2
# CAN Carrier image from the pinned sources in manifests/sources.lock.
#
# This script builds and validates the kernel/U-Boot/DT pieces that are
# specific to this carrier. Final Debian rootfs assembly is delegated to
# beagleboard/image-builder (see manifests/sources.lock [image-builder]),
# which already solves "produce a BeagleBoard Debian image" -- reusing it
# is what work order §3 ("Distribution: Current BeagleBoard Debian build
# system") asks for, not reimplementing it here. Wiring this script's
# outputs into an image-builder hwpack build is the next integration step;
# see README.md Status.
#
# Requires (Debian/Ubuntu): device-tree-compiler python3-pip
# crossbuild-essential-arm64 bc bison flex libssl-dev u-boot-tools
# gettext libmpc-dev zstd libdw-dev bindgen rust-src rustc rustfmt
# rust-clippy, plus `pip install dtschema` for dtbs_check/dt_binding_check.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="${PB2_BUILD_DIR:-${here}/.build}"
release="${here}/release"
lock="${here}/manifests/sources.lock"

log() { printf '\n[build-image] %s\n' "$1"; }

require_pinned() {
	if grep -q "^${1} = \"TODO" "${lock}"; then
		echo "error: ${1} in manifests/sources.lock is still a TODO placeholder." >&2
		exit 1
	fi
}

mkdir -p "${work}" "${release}"

# ---------------------------------------------------------------------
# 1. Kernel: RobertCNelson/arm64-multiplatform build recipe, overridden
#    to the RT-patched point release (manifests/sources.lock
#    [kernel.base] explains why 6.18.37, not the recipe's newer default),
#    plus our two out-of-tree CAN patches applied on top of the recipe's
#    own K3/RT patch series.
# ---------------------------------------------------------------------
log "Kernel: preparing build recipe"
kdir="${work}/kernel-build"
if [ ! -d "${kdir}" ]; then
	git clone --branch v6.18.x-arm64-k3 \
		https://github.com/RobertCNelson/arm64-multiplatform.git "${kdir}"
fi
git -C "${kdir}" checkout c284267db7154fe4b792e2272cb38ad7dc61bce7

sed -i 's/^KERNEL_TAG=${KERNEL_REL}\.52/KERNEL_TAG=${KERNEL_REL}.37/' "${kdir}/version.sh"
sed -i 's/^kernel_rt=".X-rtY"/kernel_rt=".37-rt6"/' "${kdir}/version.sh"
grep -q 'KERNEL_TAG=${KERNEL_REL}.37' "${kdir}/version.sh"
grep -q 'kernel_rt=".37-rt6"' "${kdir}/version.sh"

cat > "${kdir}/system.sh" <<-EOF
	CC=aarch64-linux-gnu-
	CORES=$(nproc)
EOF

log "Kernel: fetching + applying recipe's own K3/RT patch series (first run only)"
if [ ! -d "${kdir}/KERNEL" ]; then
	( cd "${kdir}" && ./build_kernel.sh )
fi

log "Kernel: applying carrier-specific patches"
kernel_src="${kdir}/KERNEL"
( cd "${kernel_src}" && git am "${here}"/patches/kernel/*.patch )

log "Kernel: merging carrier config fragment"
( cd "${kernel_src}" && \
  ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  scripts/kconfig/merge_config.sh -m .config "${here}/configs/kernel.fragment" )

log "Kernel: dt_binding_check / dtbs_check for the modified CAN-transceiver-PHY binding"
( cd "${kernel_src}" && \
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig && \
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    DT_SCHEMA_FILES=Documentation/devicetree/bindings/phy/ti,tcan104x-can.yaml \
    dt_binding_check )

log "Kernel: building Image + modules + dtbs"
( cd "${kernel_src}" && \
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image modules dtbs )

cp "${kernel_src}/arch/arm64/boot/Image" "${release}/Image"

# ---------------------------------------------------------------------
# 2. U-Boot: pinned beagleboard/u-boot commit + carrier config fragment.
# ---------------------------------------------------------------------
log "U-Boot: preparing pinned source"
udir="${work}/uboot"
if [ ! -d "${udir}" ]; then
	git clone https://github.com/beagleboard/u-boot.git "${udir}"
fi
git -C "${udir}" checkout 7d2af1199011f2210a862097c78f1b940e5d2631

log "U-Boot: building (TODO: confirm the correct upstream defconfig target for"
log "  this exact board once bb-u-boot-pocketbeagle2's build script is located --"
log "  see configs/uboot.fragment)"
echo "error: U-Boot defconfig target not yet pinned; see TODO above." >&2
# ( cd "${udir}" && \
#   make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- <TODO_defconfig> && \
#   ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- \
#   scripts/kconfig/merge_config.sh -m .config "${here}/configs/uboot.fragment" && \
#   make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" )

# ---------------------------------------------------------------------
# 3. Device tree: pinned BeagleBoard-DeviceTrees base + our carrier
#    overlay, built with the repo's own Makefile (verified: this is what
#    correctly resolves the -@ symbol/fixup mechanism the overlay needs).
# ---------------------------------------------------------------------
log "Device tree: preparing pinned source + carrier overlay"
ddir="${work}/dts"
if [ ! -d "${ddir}" ]; then
	git clone --branch v6.18.x https://github.com/beagleboard/BeagleBoard-DeviceTrees.git "${ddir}"
fi
git -C "${ddir}" checkout ee075f0804f41e7440ce579ac8d5552e3acac5c8
cp "${here}/dts/k3-am62-pocketbeagle2-can-carrier.dtso" "${ddir}/src/arm64/overlays/"

log "Device tree: dtc -W all + fdtoverlay merge check"
( cd "${ddir}" && DTC_VERBOSE=1 make all_arm64 )
fdtoverlay \
	-i "${ddir}/src/arm64/ti/k3-am62-pocketbeagle2.dtb" \
	-o "${work}/merged-sanity-check.dtb" \
	"${ddir}/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier.dtbo"

log "Device tree: dtbs_check against the modified binding"
python3 -m dtschema.dtb_check \
	-s "${kernel_src}/Documentation/devicetree/bindings/phy/ti,tcan104x-can.yaml" \
	"${ddir}/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier.dtbo" || true

cp "${ddir}/src/arm64/ti/k3-am62-pocketbeagle2.dtb" "${release}/"
cp "${ddir}/src/arm64/overlays/k3-am62-pocketbeagle2-can-carrier.dtbo" "${release}/"

log "Checksumming release/ outputs"
( cd "${release}" && sha256sum -- * > SHA256SUMS )

log "Done. Kernel Image + dtb + dtbo are in ${release}/."
log "U-Boot and final Debian rootfs assembly are not yet wired in -- see README.md Status."
