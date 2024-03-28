PLENARY_GIT = https://github.com/nvim-lua/plenary.nvim.git
PLENARY_VERSION = v0.1.4

CACHE_DIR = .cache
PLENARY = $(CACHE_DIR)/plenary/$(PLENARY_VERSION)

export PLENARY


.PHONY: all
all: test

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
	nvim \
		--noplugin \
		--headless \
		-u tests/init.lua \
		-c "PlenaryBustedDirectory tests/specs { minimal_init = './tests/init.lua' }"
