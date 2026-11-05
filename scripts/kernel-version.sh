#!/usr/bin/env bash
# Debian version of the carrier kernel package: 1xross<N>, N = number of
# commits that touched what goes into the kernel. Increases with every change
# to the kernel inputs and is the same locally and in CI (full git history).
# "1xross" (the first image) sorts below "1xross1", so boards upgrade.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
n=$(git -C "${here}" rev-list --count HEAD -- patches configs/kernel.fragment manifests/sources.lock \
	scripts/build-image.sh scripts/build-kernel-deb.sh 2>/dev/null || echo 0)
echo "1xross${n}"
