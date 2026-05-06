.DEFAULT_GOAL := help

SHELL := /usr/bin/env bash

VERSION_FILE := VERSION.txt
CARGO_TOML   := Cargo.toml
VERSION      := $(shell tr -d '[:space:]' < $(VERSION_FILE) 2>/dev/null)
VERSION_NO_V := $(patsubst v%,%,$(VERSION))

.PHONY: help
help:  ## Show this help
	@printf "sccache — make targets\n\n"
	@printf "Release flow:\n"
	@printf "  1. make bump-patch     # or bump-minor / bump-major\n"
	@printf "  2. git commit -am \"release \$$(make -s version)\" && open PR\n"
	@printf "  3. After merge to main, Buildkite cuts the release.\n"
	@printf "     For a one-off local release: GITHUB_TOKEN=... make release\n\n"
	@printf "Targets:\n"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z][a-zA-Z0-9_-]*:.*?## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\nCurrent version: %s (Cargo: %s)\n" "$(VERSION)" "$(shell awk -F' = ' '/^version = /{gsub(/"/, "", $$2); print $$2; exit}' $(CARGO_TOML))"

.PHONY: version
version:  ## Print the current release version from VERSION.txt
	@echo $(VERSION)

.PHONY: check-version
check-version:  ## Verify VERSION.txt, Cargo.toml, and Cargo.lock are in sync
	@cargo_v=$$(awk -F' = ' '/^version = /{gsub(/"/, "", $$2); print $$2; exit}' $(CARGO_TOML)); \
	lock_v=$$(awk '/^\[\[package\]\]/{p=1; n=""} p && /^name = "sccache"$$/{n="sccache"} p && n=="sccache" && /^version = /{gsub(/"/, "", $$3); print $$3; exit}' Cargo.lock); \
	if [ "$(VERSION_NO_V)" != "$$cargo_v" ] || [ "$(VERSION_NO_V)" != "$$lock_v" ]; then \
		printf "version drift detected:\n  VERSION.txt: %s\n  Cargo.toml:  %s\n  Cargo.lock:  %s\n" "$(VERSION_NO_V)" "$$cargo_v" "$$lock_v" >&2; \
		exit 1; \
	fi; \
	printf "OK: version is %s in all three files\n" "$$cargo_v"

.PHONY: test
test:  ## Run cargo test in a Rust Docker container
	@.buildkite/test.sh

.PHONY: build
build:  ## Cross-compile all release binaries (no archives, no publish)
	@scripts/release.sh build

.PHONY: snapshot
snapshot:  ## Full release dry-run — builds + archives + brew formula, no publish
	@scripts/release.sh snapshot

.PHONY: release
release: check-version  ## Tag, publish GitHub release, push formula to homebrew-tap (requires GITHUB_TOKEN)
	@scripts/release.sh release

.PHONY: bump-patch
bump-patch:  ## Bump VERSION.txt + Cargo.toml patch (x.y.Z+1)
	@$(MAKE) -s _bump KIND=patch

.PHONY: bump-minor
bump-minor:  ## Bump VERSION.txt + Cargo.toml minor (x.Y+1.0)
	@$(MAKE) -s _bump KIND=minor

.PHONY: bump-major
bump-major:  ## Bump VERSION.txt + Cargo.toml major (X+1.0.0)
	@$(MAKE) -s _bump KIND=major

.PHONY: _bump
_bump:
	@if [ -z "$(KIND)" ]; then echo "internal target — use bump-patch / bump-minor / bump-major" >&2; exit 2; fi
	@cur="$(VERSION_NO_V)"; \
	IFS=. read -r maj min pat <<<"$$cur"; \
	case "$(KIND)" in \
		patch) pat=$$((pat+1)) ;; \
		minor) min=$$((min+1)); pat=0 ;; \
		major) maj=$$((maj+1)); min=0; pat=0 ;; \
	esac; \
	new="$$maj.$$min.$$pat"; \
	printf "v%s\n" "$$new" > $(VERSION_FILE); \
	awk -v new="$$new" 'BEGIN{done=0} /^version = /{ if(!done){printf "version = \"%s\"\n", new; done=1; next} } {print}' $(CARGO_TOML) > $(CARGO_TOML).tmp && mv $(CARGO_TOML).tmp $(CARGO_TOML); \
	awk -v new="$$new" '\
	  /^\[\[package\]\]/ { in_pkg=1; is_sccache=0 } \
	  in_pkg && /^name = "sccache"$$/ { is_sccache=1 } \
	  in_pkg && is_sccache && /^version = / { printf "version = \"%s\"\n", new; in_pkg=0; is_sccache=0; next } \
	  /^$$/ { in_pkg=0; is_sccache=0 } \
	  { print } \
	' Cargo.lock > Cargo.lock.tmp && mv Cargo.lock.tmp Cargo.lock; \
	printf "Bumped %s -> %s\n" "$$cur" "$$new"; \
	printf "  $(VERSION_FILE):  v%s\n" "$$new"; \
	printf "  $(CARGO_TOML):    %s\n" "$$new"; \
	printf "  Cargo.lock:    %s\n" "$$new"; \
	printf "\nReview the diff, then commit:\n"; \
	printf "  git diff $(VERSION_FILE) $(CARGO_TOML) Cargo.lock\n"; \
	printf "  git commit -am \"release v%s\"\n" "$$new"

.PHONY: clean
clean:  ## Remove dist/ and goreleaser intermediate state
	@rm -rf dist
	@printf "Removed dist/. (target/ left intact — run 'cargo clean' to remove that.)\n"
