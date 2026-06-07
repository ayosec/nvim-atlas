.PHONY: all
all: test lint fmt-check

.PHONY: test
test:
	tests/run.lua

.PHONY: lint
lint:
	luacheck lua tests \
	  --max-comment-line-length 200 \
	  --globals a vim

.PHONY: fmt
fmt:
	stylua lua tests

.PHONY: fmt-check
fmt-check:
	stylua --check lua tests
