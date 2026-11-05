#!/usr/bin/env bash
# Version of pb2-can-carrier-support: 1.0.<number of commits that touched the
# packaged files>. Increases with every change to them and stays the same
# otherwise, locally and in CI (needs the full git history).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
n=$(git -C "${here}" rev-list --count HEAD -- image dts apt scripts/build-support-deb.sh 2>/dev/null || echo 0)
echo "1.0.${n}"
