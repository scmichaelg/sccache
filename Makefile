.DEFAULT_GOAL := help

SHELL := /usr/bin/env bash

.PHONY: help
help:  ## Show this help
	@printf "sccache — make targets\n\n"
	@printf "Release flow:\n"
	@printf "  Releases are cut by Buildkite. The auto-version script computes\n"
	@printf "  the next semver from conventional commits since the last tag:\n"
	@printf "    feat: ...    -> minor bump\n"
	@printf "    fix: / chore -> patch bump\n"
	@printf "    BREAKING ... -> major bump\n"
	@printf "  Merge to main triggers a real release.\n"
	@printf "  Push to a feature branch triggers a gated preview release\n"
	@printf "  (tagged \033[3mvX.Y.Z-preview.<branch-slug>\033[0m).\n\n"
	@printf "Targets:\n"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z][a-zA-Z0-9_-]*:.*?## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: next-version
next-version:  ## Print what auto-version would compute for HEAD
	@.buildkite/scripts/auto-version

.PHONY: test
test:  ## Run cargo test in a Rust Docker container
	@docker run --rm -v "$(PWD):/app" -w /app \
		-e CARGO_HOME=/app/.cargo -e CARGO_TARGET_DIR=/app/target \
		messense/cargo-zigbuild:0.20.0 \
		cargo test --locked --no-default-features

.PHONY: build
build:  ## Cross-compile all release binaries to dist/{os}_{arch}/sccache
	@scripts/release.sh build

.PHONY: snapshot
snapshot:  ## Full release dry-run — build + archive + brew formula, no publish
	@scripts/release.sh snapshot

.PHONY: clean
clean:  ## Remove dist/
	@rm -rf dist
	@printf "Removed dist/. (target/ left intact — run 'cargo clean' to remove that.)\n"
