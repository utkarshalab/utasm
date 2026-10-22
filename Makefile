NASM      := nasm
LD        := ld
NASM_FLAGS := -d__NASM__=1 -f elf64 -I./
GEN0      := build/gen0/utasm
GEN1      := build/gen1/utasm

# every source under src/, in one fixed order (the link order: the same
# binary on every machine)
SOURCES   := $(shell find src -name '*.s' | LC_ALL=C sort)

GEN0_OBJS := $(patsubst %.s, build/gen0/%.o, $(SOURCES))
GEN1_OBJS := $(patsubst %.s, build/gen1/%.o, $(SOURCES))

# a file cut into parts (src/.../parser.s and its parser/*.inc) is rebuilt
# when one of them changes
$(foreach s,$(SOURCES),$(eval build/gen0/$(s:.s=.o) build/gen1/$(s:.s=.o): $(wildcard $(s:.s=)/*.inc)))

.PHONY: all gen0 gen1 test test-unit test-integration clean doc bootstrap help

all: gen1

## Stage 0: build using NASM
gen0: $(GEN0)

# linked as scripts/build/bootstrap.sh links it: plain ld, no linker script (an
# empty one, given with -T, produced a binary that crashed on every command)
$(GEN0): $(GEN0_OBJS)
	@mkdir -p $(dir $@)
	$(LD) -o $@ $^
	@echo "[gen0] $(GEN0) ready"

build/gen0/%.o: %.s
	@mkdir -p $(dir $@)
	$(NASM) $(NASM_FLAGS) $< -o $@

## Stage 1: self-host using Gen0
gen1: gen0 $(GEN1)
	@cmp --silent $(GEN0) $(GEN1) && echo "[parity] gen0 == gen1 OK" || echo "[parity] MISMATCH — gen0 != gen1"

$(GEN1): $(GEN1_OBJS)
	@mkdir -p $(dir $@)
	$(LD) -o $@ $^
	@echo "[gen1] $(GEN1) ready"

build/gen1/%.o: %.s $(GEN0)
	@mkdir -p $(dir $@)
	$(GEN0) -f elf64 $< -o $@

## Run full bootstrap script (3-stage with strict parity)
bootstrap:
	bash scripts/build/bootstrap.sh

## Run all tests against Gen1
test: gen1
	bash tests/run.sh

## Run only unit tests
test-unit: gen1
	bash tests/run.sh unit

## Run only integration tests
test-integration: gen1
	bash tests/run.sh integration

## Clean all build artifacts
clean:
	rm -rf build/

## Generate docs (placeholder — extend as tooling matures)
doc:
	@echo "Docs are in docs/ — no generator yet."

## Print help
help:
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
	    awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
