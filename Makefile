ZIG ?= zig
OPTIMIZE ?= ReleaseSafe

.DEFAULT_GOAL := release

.PHONY: release run-release test audio-probe nam-bench

release:
	$(ZIG) build -Doptimize=$(OPTIMIZE)

run-release: release
	open -n "zig-out/Robine Studio.app"

test:
	$(ZIG) build test -Doptimize=$(OPTIMIZE)

audio-probe:
	$(ZIG) build audio-probe -Doptimize=$(OPTIMIZE)

nam-bench:
	$(ZIG) build nam-bench -Doptimize=$(OPTIMIZE)
