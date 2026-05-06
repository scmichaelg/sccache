#!/usr/bin/env bash
#
# Manual release driver — wraps the same goreleaser invocation that
# .buildkite/goreleaser.sh runs in CI, but reads GITHUB_TOKEN from the
# environment instead of AWS Secrets Manager.
#
# Usage:
#   scripts/release.sh snapshot          # local dry-run, no publish
#   scripts/release.sh build              # cross-compile only, no release
#   scripts/release.sh release            # tag + publish + push formula
#
# `release` mode requires:
#   - GITHUB_TOKEN  (PAT with repo scope on SafetyCulture/sccache and
#                    SafetyCulture/homebrew-tap)
#   - VERSION.txt   bumped to a new tag that does not yet exist on origin
#   - clean working tree
#
set -o nounset
set -o errexit
set -o pipefail

GORELEASER_VERSION="${GORELEASER_VERSION:-v2.14.3}"
ZIGBUILD_IMAGE="${ZIGBUILD_IMAGE:-ghcr.io/rust-cross/cargo-zigbuild:0.20.0}"

cd "$(git rev-parse --show-toplevel)"

cmd="${1:-snapshot}"

run_goreleaser() {
  local gr_args=("$@")

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
      goreleaser ${gr_args[*]}
    "
}

case "${cmd}" in
  snapshot)
    echo "--- goreleaser snapshot (no publish)"
    run_goreleaser release --snapshot --clean --skip=publish
    ;;

  build)
    echo "--- goreleaser build (cross-compile only)"
    run_goreleaser build --snapshot --clean
    ;;

  release)
    if [ -z "${GITHUB_TOKEN:-}" ]; then
      echo "GITHUB_TOKEN is required for 'release' mode." >&2
      echo "Export a PAT with 'repo' scope on SafetyCulture/sccache and SafetyCulture/homebrew-tap." >&2
      exit 1
    fi

    if ! git diff --quiet HEAD || ! git diff --quiet --cached HEAD; then
      echo "Working tree has uncommitted changes. Commit or stash before releasing." >&2
      exit 1
    fi

    VERSION=$(tr -d '[:space:]' < ./VERSION.txt)

    if [ -z "${VERSION}" ]; then
      echo "VERSION.txt is empty." >&2
      exit 1
    fi

    if [[ ! "${VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
      echo "VERSION.txt must contain a tag like v1.2.3 (got: '${VERSION}')." >&2
      exit 1
    fi

    if [[ -n $(git ls-remote origin "refs/tags/${VERSION}") ]]; then
      echo "Tag ${VERSION} already exists on origin. Bump VERSION.txt." >&2
      exit 1
    fi

    echo "--- Releasing ${VERSION}"
    echo "    repo:        $(git remote get-url origin)"
    echo "    branch:      $(git rev-parse --abbrev-ref HEAD)"
    echo "    commit:      $(git rev-parse --short HEAD)"
    echo "    tap:         SafetyCulture/homebrew-tap"
    echo
    read -r -p "Proceed? [y/N] " confirm
    case "${confirm}" in
      y|Y|yes|YES) ;;
      *) echo "Aborted."; exit 1 ;;
    esac

    git tag "${VERSION}"
    trap 'git tag -d "${VERSION}" 2>/dev/null || true' ERR

    run_goreleaser release --clean

    echo
    echo "Released ${VERSION}."
    echo "Push the tag to origin so the release ref is permanent:"
    echo "    git push origin ${VERSION}"
    ;;

  *)
    echo "usage: scripts/release.sh [snapshot|build|release]" >&2
    exit 2
    ;;
esac
