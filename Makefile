ZIG ?= zig
OPTIMIZE ?= ReleaseFast
TEST_OPTIMIZE ?= ReleaseSafe

.DEFAULT_GOAL := release

.PHONY: release run-release test audio-probe nam-bench a2-bench

release:
	$(ZIG) build -Doptimize=$(OPTIMIZE)

run-release: release
	$(ZIG) build run-studio -Doptimize=$(OPTIMIZE)

test:
	$(ZIG) build test -Doptimize=$(TEST_OPTIMIZE)

audio-probe:
	$(ZIG) build audio-probe -Doptimize=$(OPTIMIZE)

nam-bench:
	$(ZIG) build nam-bench -Doptimize=$(OPTIMIZE)

a2-bench:
	$(ZIG) build a2-bench -Doptimize=$(OPTIMIZE)
