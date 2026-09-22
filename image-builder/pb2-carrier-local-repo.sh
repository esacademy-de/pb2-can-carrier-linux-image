#!/bin/bash -e

# Populates a small local flat apt repo inside the target rootfs with the
# PB2 CAN Carrier's own kernel .deb packages (built from
# patches/kernel/*.patch + configs/kernel.fragment against the pinned
# base -- see manifests/sources.lock), so scripts/chroot.sh's
# repo_external mechanism can install them in place of BeagleBoard's
# stock bbb.io-kernel-6.18-k3/bbb.io-headers-6.18-k3 packages. Runs
# between debootstrap.sh and chroot.sh (hooked from RootStock-NG.sh).

DIR=$PWD
. "${DIR}/.project"

if [ ! "${tempdir}" ] ; then
	echo "scripts/pb2-carrier-local-repo.sh: Error: tempdir undefined"
	exit 1
fi

carrier_deb_src="${PB2_CARRIER_DEB_DIR:-${HOME}/pb2-build/kernel-build/deploy}"
repo_dir="${tempdir}/opt/pb2-carrier-repo"

echo "Log: populating local carrier kernel repo from ${carrier_deb_src}"
sudo mkdir -p "${repo_dir}"
sudo cp -v "${carrier_deb_src}"/linux-image-*.deb "${repo_dir}/"
if ls "${carrier_deb_src}"/linux-headers-*.deb >/dev/null 2>&1 ; then
	sudo cp -v "${carrier_deb_src}"/linux-headers-*.deb "${repo_dir}/"
fi

( cd "${repo_dir}" && sudo bash -c "dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz" )

echo "Log: local carrier kernel repo contents"
ls -la "${repo_dir}"
