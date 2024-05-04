.PHONY: all
all: test lint fmt-check

.PHONY: test
test:
	tests/run.lua

.PHONY: lint
lint:
	luacheck lua tests --globals a vim

.PHONY: fmt
fmt:
	stylua lua tests

.PHONY: fmt-check
fmt-check:
	stylua --check lua tests

.PHONY: lua-types
lua-types:
	git clone \
	    -c advice.detachedHead=false \
	    -b v2.5.2 \
	    --depth 1 \
	    https://github.com/folke/neodev.nvim.git \
	    .cache/neodev
	mv .cache/neodev/types/stable .cache/lua-types
	rm -fr .cache/neodev
