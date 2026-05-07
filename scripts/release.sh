#!/usr/bin/env bash
#
# Local two-step release driver. Mirrors what Buildkite does:
#   1. Build all 4 release binaries via cargo-zigbuild into dist/{os}_{arch}/sccache
#   2. Run goreleaser with `builder: prebuilt` against those binaries
#
# Real releases are cut by Buildkite (auto-version + gh-authenticator
# plugin). This script is for local validation only.
#
# Usage:
#   scripts/release.sh build      # just compile binaries (Step 1)
#   scripts/release.sh snapshot   # full dry-run: build + archive + brew formula, no publish
#
set -o nounset
set -o errexit
set -o pipefail

GORELEASER_VERSION="${GORELEASER_VERSION:-v2.15.4}"
GORELEASER_IMAGE="${GORELEASER_IMAGE:-goreleaser/goreleaser:${GORELEASER_VERSION}}"
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

run_goreleaser() {
  docker run \
    --rm \
    -v "${PWD}:/build" \
    -w /build \
    "${GORELEASER_IMAGE}" \
    "$@"
}

build_binaries() {
  echo "--- Step 1: cargo-zigbuild all targets"
  run_in_zigbuild bash .buildkite/scripts/build-rust
}

case "${cmd}" in
  build)
    build_binaries
    ;;

  snapshot)
    build_binaries
    echo "--- Step 2: goreleaser snapshot (no publish)"
    run_goreleaser release --snapshot --clean --skip=publish
    ;;

  *)
    echo "usage: scripts/release.sh [build|snapshot]" >&2
    echo "Real releases are cut by Buildkite. This script is for local validation only." >&2
    exit 2
    ;;
esac
