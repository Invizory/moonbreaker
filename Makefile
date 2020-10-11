.PHONY: build
build: # Build luarock
	luarocks --local make moonbreaker-*.rockspec

.PHONY: dev-deps
dev-deps: # Install development dependencies
	for package in busted luacheck luacov luacov-reporter-lcov; do \
		luarocks --local install "$$package"; \
	done
	luarocks --local build moonbreaker-*.rockspec --only-deps

.PHONY: test
test: lint # Run tests
	busted --verbose --coverage

.PHONY: lint
lint: # Lint with Luacheck
	luacheck .

.PHONY: coverage
coverage: clean test # Make test coverage report
	luacov -r lcov
	genhtml luacov.report.out -o coverage

.PHONY: clean
clean: # Clean
	$(RM) luacov.*.out
	$(RM) -r coverage

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?# .*$$' ./Makefile | sort | awk \
		'BEGIN {FS = ":.*?# "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
