TAG ?= v0.43.1

.PHONY: all build test clean

all: build

build:
	@./scripts/build.sh --tag $(TAG)

test:
	@./scripts/build.sh --tag $(TAG) --test-only

clean:
	@./scripts/build.sh --clean
