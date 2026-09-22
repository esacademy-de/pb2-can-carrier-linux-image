#!/usr/bin/env bash
# Flash the built image to microSD and run the automated §11 smoke tests.
# Intended to run on a self-hosted GitHub Actions runner (label: pb2-bench)
# with the PocketBeagle 2 + CAN carrier physically attached.
#
# Status: not yet implemented.
set -euo pipefail

echo "error: scripts/flash-and-verify.sh is not implemented yet." >&2
echo "See tests/README.md for the §11 validation matrix this must cover." >&2
exit 1
