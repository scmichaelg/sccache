#!/usr/bin/env bash
#
# Local release driver. Mirrors what Buildkite does:
#   - Both compilation (cargo-zigbuild) and packaging (goreleaser) run
#     inside the messense/cargo-zigbuild image. Goreleaser uses
#     `builder: rust`, so it invokes cargo-zigbuild itself.
#
# Real releases are cut by Buildkite (auto-version + gh-authenticator
# plugin). This script is for local validation only.
#
# Usage:
#   scripts/release.sh build      # just compile binaries (no goreleaser)
#   scripts/release.sh snapshot   # full dry-run via goreleaser, no publish
#
set -o nounset
set -o errexit
set -o pipefail

ZIGBUILD_IMAGE="${ZIGBUILD_IMAGE:-messense/cargo-zigbuild:0.20.0}"

cd "$(git rev-parse --show-toplevel)"

cmd="${1:-snapshot}"

run_in_zigbuild() {
  docker run \
    --rm \
    -v "${PWD}:/workdir" \
    -w /workdir \
    -e CARGO_HOME=/workdir/.cargo \
    -e CARGO_TARGET_DIR=/workdir/target \
    "${ZIGBUILD_IMAGE}" \
    "$@"
}

case "${cmd}" in
  build)
    echo "--- cargo-zigbuild all targets"
    run_in_zigbuild bash .buildkite/scripts/build-rust
    ;;

  snapshot)
    echo "--- goreleaser snapshot (no publish)"
    run_in_zigbuild bash .buildkite/scripts/run-goreleaser release --snapshot --clean --skip=publish
    ;;

  *)
    echo "usage: scripts/release.sh [build|snapshot]" >&2
    echo "Real releases are cut by Buildkite. This script is for local validation only." >&2
    exit 2
    ;;
esac
