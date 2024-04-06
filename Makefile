PLENARY_GIT = https://github.com/nvim-lua/plenary.nvim.git
PLENARY_VERSION = v0.1.4

CACHE_DIR = .cache
PLENARY = $(CACHE_DIR)/plenary/$(PLENARY_VERSION)


.PHONY: all
all: test lint fmt-check

$(CACHE_DIR):
	mkdir -p $@
	touch $@/CACHEDIR.TAG

$(PLENARY): $(CACHE_DIR)
	git \
		-c advice.detachedHead=false \
		clone \
		--depth 1 \
		--branch $(PLENARY_VERSION) \
		$(PLENARY_GIT) \
		$@

.PHONY: test
test: | $(PLENARY)
	tests/run.sh $(PLENARY)

.PHONY: lint
lint:
	luacheck lua tests --globals a vim

.PHONY: fmt
fmt:
	stylua lua tests

.PHONY: fmt-check
fmt-check:
	stylua --check lua tests
