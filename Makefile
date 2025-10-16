# -------------------------
# Variables
# -------------------------

UI_VERSION := $(shell cat web/expose/package.json | grep version | head -1 | awk -F: '{ print $$2 }' | sed 's/[\",]//g' | tr -d '[[:space:]]')
VERSION_PATH := github.com/getExposed/expose/internal/version

VERSION ?= $(shell (git describe --tags --exact-match 2>/dev/null || git describe --tags --abbrev=0 2>/dev/null || echo dev))

GIT_COMMIT  := $(shell git rev-parse --short HEAD)
BUILD_DATE  := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
RELEASE_DIR := build/release

LDFLAGS := -ldflags "\
  -X $(VERSION_PATH).Version=$(VERSION) \
  -X $(VERSION_PATH).UIVersion=$(UI_VERSION) \
  -X $(VERSION_PATH).GitCommit=$(GIT_COMMIT) \
  -X $(VERSION_PATH).BuildDate=$(BUILD_DATE) \
"
# -------------------------
# Target matrices
# -------------------------

OS := darwin freebsd linux windows
ARCH := amd64 arm arm64
EXCLUDE := darwin/arm windows/arm

# Build list of allowed os/arch pairs (space-separated strings like darwin/amd64)
RELEASE_PAIRS := $(foreach os,$(OS),$(foreach arch,$(ARCH),\
	$(if $(filter $(os)/$(arch),$(EXCLUDE)),,$(os)/$(arch))\
))

# Release artifacts we will build
RELEASE_BINS := \
  $(foreach p,$(RELEASE_PAIRS),$(RELEASE_DIR)/expose_$(subst /,_,$(p))) \
  $(foreach p,$(RELEASE_PAIRS),$(RELEASE_DIR)/expose-server_$(subst /,_,$(p)))

# -------------------------
# Phony targets
# -------------------------

.PHONY: build build_server build_client build_ui_landing wire static_landing install_dependencies clean release

# -------------------------
# Default build (host platform)
# -------------------------

build: static_landing wire build_server build_client

build_server:
	@mkdir -p build
	@echo "→ building expose-server (server)"
	@CGO_ENABLED=0 go build $(LDFLAGS) -o ./build/expose-server ./cmd/expose-server

build_client:
	@mkdir -p build
	@echo "→ building expose (client)"
	@CGO_ENABLED=0 go build $(LDFLAGS) -o ./build/expose ./cmd/expose

# -------------------------
# UI / codegen / assets
# -------------------------

build_ui_landing:
	@if [ ! -d "web/expose/dist" ]; then \
		echo "→ building UI landing"; \
		cd web/expose && yarn build; \
	fi

wire:
	@echo "→ running wire"
	@wire ./cmd/expose-server

static_landing: build_ui_landing
	@if [ ! -r "internal/ui/landing/static.go" ]; then \
		echo "→ embedding static landing (statik)"; \
		statik -f -dest ./internal/ui -p landing -src ./web/expose/dist; \
	fi

install_dependencies:
	@echo "→ installing Go/YARN tools"
	@go get github.com/jkuri/statik github.com/google/wire/cmd/...
	@go install github.com/jkuri/statik
	@go install github.com/google/wire/cmd/...
	@cd web/expose && yarn install

clean:
	@echo "→ cleaning"
	@rm -rf build/ internal/ui web/expose/dist

# -------------------------
# Multi-arch release (no gox)
# -------------------------

release: static_landing wire $(RELEASE_BINS)
	@echo "✓ release artifacts in $(RELEASE_DIR)"

# -------- rules generator (no empty pairs, honors EXCLUDE) --------
define GEN_RULES
$(RELEASE_DIR)/expose_$(1)_$(2):
	@mkdir -p $(RELEASE_DIR)
	@echo "→ building expose for $(1)/$(2)"
	@CGO_ENABLED=0 GOOS=$(1) GOARCH=$(2) go build $(LDFLAGS) -o $$@ ./cmd/expose

$(RELEASE_DIR)/expose-server_$(1)_$(2):
	@mkdir -p $(RELEASE_DIR)
	@echo "→ building expose-server for $(1)/$(2)"
	@CGO_ENABLED=0 GOOS=$(1) GOARCH=$(2) go build $(LDFLAGS) -o $$@ ./cmd/expose-server
endef

# Instantiate for each allowed pair
$(foreach os,$(OS),$(foreach arch,$(ARCH),\
  $(if $(filter $(os)/$(arch),$(EXCLUDE)),,\
    $(eval $(call GEN_RULES,$(os),$(arch)))\
  )\
))