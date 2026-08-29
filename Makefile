ZIG ?= zig
OPTIMIZE ?= ReleaseSafe

.DEFAULT_GOAL := release

.PHONY: release run-release test

release:
	$(ZIG) build -Doptimize=$(OPTIMIZE)

run-release: release
	open -n "zig-out/Robine Studio.app"

test:
	$(ZIG) build test -Doptimize=$(OPTIMIZE)
