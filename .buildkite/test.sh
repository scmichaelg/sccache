#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail

RUST_IMAGE="${RUST_IMAGE:-rust:1.84-bookworm}"

docker run \
  --rm \
  -v "${PWD}:/app" \
  -w /app \
  -e CARGO_HOME=/app/.cargo \
  -e CARGO_TARGET_DIR=/app/target \
  "${RUST_IMAGE}" \
  bash -c 'cargo test --locked --no-default-features'
