#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail

CREATE_RELEASE="${CREATE_RELEASE:-false}"
GORELEASER_VERSION="${GORELEASER_VERSION:-v2.14.3}"
# messense/cargo-zigbuild ships rust + zig + cargo-zigbuild and is the de-facto
# image for cross-compiling Rust to linux/darwin from a Linux host.
ZIGBUILD_IMAGE="${ZIGBUILD_IMAGE:-ghcr.io/rust-cross/cargo-zigbuild:0.20.0}"

run_goreleaser() {
  local goreleaser_args=("$@")

  docker run \
    --rm \
    -v "${PWD}:/app" \
    -w /app \
    -e GITHUB_TOKEN \
    -e CARGO_HOME=/app/.cargo \
    -e CARGO_TARGET_DIR=/app/target \
    "${ZIGBUILD_IMAGE}" \
    bash -euo pipefail -c "
      curl -sSfL \
        'https://github.com/goreleaser/goreleaser/releases/download/${GORELEASER_VERSION}/goreleaser_Linux_x86_64.tar.gz' \
        | tar -xzC /usr/local/bin goreleaser
      rustup target add \
        x86_64-unknown-linux-musl \
        aarch64-unknown-linux-musl \
        x86_64-apple-darwin \
        aarch64-apple-darwin
      goreleaser ${goreleaser_args[*]}
    "
}

if [ "${CREATE_RELEASE}" == "true" ]; then
  GITHUB_TOKEN=$(aws secretsmanager get-secret-value \
    --secret-id buildkite_agent/hub_github_token \
    --region us-east-2 \
    --output text \
    --query SecretString)
  export GITHUB_TOKEN

  VERSION=$(tr -d '[:space:]' < ./VERSION.txt)

  echo "--- Creating Release: ${VERSION}"

  if [[ -n $(git ls-remote origin "refs/tags/${VERSION}") ]]; then
    echo "Release ${VERSION} already exists. Skipping..."
    buildkite-agent annotate --style "warning" \
      "No Release Created! VERSION.txt must be updated!"
    exit 1
  fi

  git tag "${VERSION}"

  run_goreleaser release --clean

  buildkite-agent annotate --style "success" "New Release Available: ${VERSION}"
else
  # Snapshot build on PRs validates that the cross-compile works
  run_goreleaser build --snapshot --clean
fi
