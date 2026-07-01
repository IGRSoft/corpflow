# Makefile — igrsoft plugin test suite + dual-path TTT benchmark (DV0d, sole owner)
#
# Targets:
#   make bootstrap       vendored-bats present-check; resolve kcov (system→brew→proxy);
#                        install/vendor coverage.py. Idempotent.
#   make test            ./run-tests.sh — full deterministic suite. No network, no live.
#   make coverage        run suite under kcov (bash) + coverage.py (python), gate ≥85%.
#                        (alias: make test COVERAGE=1)
#   make benchmark       deterministic dual-path TTT benchmark. No --live, no network.
#   make benchmark-live  opt-in live A/B (credential-gated, budget-capped). Never CI.
#   make report          render benchmark/results/history.json -> result.html (all
#                        metrics per run + generated-app paths). Auto-run after benchmark.
#   make clean           remove workdirs, coverage intermediates, __pycache__.
#
# Honors COVERAGE=1 to route `make test` through `make coverage`.

SHELL        := /usr/bin/env bash
PLUGIN_ROOT  := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
BATS         := $(PLUGIN_ROOT)/tests/vendor/bats-core/bin/bats
PYTHON       ?= python3
COVDIR       := $(PLUGIN_ROOT)/.coverage-kcov
# Project-local venv for coverage.py — keeps the host's externally-managed
# (PEP 668) site-packages untouched. Created on demand by `make bootstrap`.
COVVENV      := $(PLUGIN_ROOT)/.venv-cov
COVPY        := $(COVVENV)/bin/python
COVERAGE     ?= 0
# Coverage line-coverage gate (per AC-3; ≥85-90% locked, 85 is the floor).
COV_MIN      ?= 85

# kcov instrumentation scope (per analyzing-0.md#q3-kcov / DV0d mandate).
KCOV_INCLUDE := $(PLUGIN_ROOT)/skills,$(PLUGIN_ROOT)/hooks,$(PLUGIN_ROOT)/.claude/hooks
KCOV_EXCLUDE := $(PLUGIN_ROOT)/tests

# All bats files under tests/shell/**.
SHELL_TESTS  := $(shell find $(PLUGIN_ROOT)/tests/shell -type f -name '*.bats' 2>/dev/null | sort)

.PHONY: all test bootstrap coverage benchmark benchmark-live report clean help
.DEFAULT_GOAL := help

help:
	@echo "igrsoft test suite — targets:"
	@echo "  make bootstrap       resolve bats/kcov/coverage.py (idempotent)"
	@echo "  make test            full deterministic suite (offline)"
	@echo "  make coverage        suite under kcov + coverage.py, gate >=$(COV_MIN)%"
	@echo "  make benchmark       deterministic dual-path TTT benchmark (offline)"
	@echo "  make benchmark-live  opt-in live A/B (credential+budget gated)"
	@echo "  make clean           remove workdirs / coverage intermediates"

# ---------------------------------------------------------------------------
# bootstrap: vendored bats present-check + kcov tiered probe + coverage.py
# ---------------------------------------------------------------------------
bootstrap:
	@echo "[bootstrap] checking vendored bats…"
	@test -x "$(BATS)" || { echo "[bootstrap] FATAL: vendored bats missing at $(BATS)"; exit 1; }
	@echo "[bootstrap] vendored bats OK: $$("$(BATS)" --version 2>/dev/null)"
	@echo "[bootstrap] resolving kcov (tiered: system -> brew -> documented proxy)…"
	@if command -v kcov >/dev/null 2>&1; then \
	    echo "[bootstrap] tier-1: system kcov found at $$(command -v kcov)"; \
	  elif command -v brew >/dev/null 2>&1; then \
	    echo "[bootstrap] tier-2: attempting 'brew install kcov' (may require network)…"; \
	    brew install kcov >/dev/null 2>&1 && echo "[bootstrap] kcov installed via brew" \
	      || echo "[bootstrap] tier-2 FAILED -> tier-3 documented per-file proxy (see tests/COVERAGE.md)"; \
	  else \
	    echo "[bootstrap] tier-3: no kcov, no brew -> documented per-file assertion-ratio proxy (tests/COVERAGE.md)"; \
	  fi
	@echo "[bootstrap] resolving coverage.py for python (PEP 668-safe local venv)…"
	@if [ -x "$(COVPY)" ] && "$(COVPY)" -c 'import coverage' >/dev/null 2>&1; then \
	    echo "[bootstrap] coverage.py already present in $(COVVENV)"; \
	  elif $(PYTHON) -c 'import coverage' >/dev/null 2>&1; then \
	    echo "[bootstrap] coverage.py importable from host python"; \
	  else \
	    echo "[bootstrap] creating local venv $(COVVENV) for coverage.py…"; \
	    ( $(PYTHON) -m venv "$(COVVENV)" >/dev/null 2>&1 && \
	      "$(COVVENV)/bin/python" -m pip install --quiet coverage >/dev/null 2>&1 && \
	      echo "[bootstrap] coverage.py installed in $(COVVENV)" ) \
	    || ( [ -d "$(PLUGIN_ROOT)/tests/vendor" ] && ls $(PLUGIN_ROOT)/tests/vendor/*.whl >/dev/null 2>&1 && \
	         "$(COVVENV)/bin/python" -m pip install --quiet --no-index --find-links $(PLUGIN_ROOT)/tests/vendor coverage >/dev/null 2>&1 && \
	         echo "[bootstrap] coverage.py installed from vendored wheel" ) \
	    || echo "[bootstrap] coverage.py unavailable (offline, no wheel) -> python coverage degrades auditably (tests/COVERAGE.md)"; \
	  fi
	@echo "[bootstrap] done."

# ---------------------------------------------------------------------------
# test: the deterministic suite. Routes to coverage when COVERAGE=1.
# ---------------------------------------------------------------------------
test:
ifeq ($(COVERAGE),1)
	@$(MAKE) --no-print-directory coverage
else
	@COVERAGE=0 "$(PLUGIN_ROOT)/run-tests.sh"
endif

# ---------------------------------------------------------------------------
# coverage: kcov (bash) + coverage.py (python), aggregate + gate.
# Degrades gracefully + auditably when kcov is unavailable (tier-3 proxy).
# ---------------------------------------------------------------------------
coverage: bootstrap
	@echo "[coverage] preparing $(COVDIR)…"
	@rm -rf "$(COVDIR)"; mkdir -p "$(COVDIR)"
	@if command -v kcov >/dev/null 2>&1; then \
	    echo "[coverage] kcov present — instrumenting each .bats target"; \
	    set -e; \
	    for f in $(SHELL_TESTS); do \
	      stem=$$(echo "$$f" | sed 's#$(PLUGIN_ROOT)/tests/shell/##; s#/#__#g; s#\.bats$$##'); \
	      echo "[coverage]   kcov -> $$stem"; \
	      kcov --include-path="$(KCOV_INCLUDE)" --exclude-path="$(KCOV_EXCLUDE)" \
	        "$(COVDIR)/$$stem" "$(BATS)" "$$f" || exit $$?; \
	    done; \
	    echo "[coverage] kcov per-target runs complete; merged report under $(COVDIR)/"; \
	    echo "[coverage] (per-file >=$(COV_MIN)% gate asserted in tests/COVERAGE.md / QA AC-3)"; \
	  else \
	    echo "[coverage] kcov UNAVAILABLE — tier-3 documented per-file assertion-ratio proxy."; \
	    echo "[coverage] running suite uninstrumented so tests still gate; see tests/COVERAGE.md."; \
	    "$(PLUGIN_ROOT)/run-tests.sh"; \
	  fi
	@echo "[coverage] python coverage.py phase…"
	@covpy=""; \
	  if [ -x "$(COVPY)" ] && "$(COVPY)" -c 'import coverage' >/dev/null 2>&1; then covpy="$(COVPY)"; \
	  elif $(PYTHON) -c 'import coverage' >/dev/null 2>&1; then covpy="$(PYTHON)"; fi; \
	  if [ -n "$$covpy" ] && find "$(PLUGIN_ROOT)/tests/python" -name 'test_*.py' -type f 2>/dev/null | grep -q .; then \
	    cd "$(PLUGIN_ROOT)" && \
	    "$$covpy" -m coverage run -m unittest discover -s tests/python -p 'test_*.py' && \
	    "$$covpy" -m coverage report --fail-under=$(COV_MIN) || exit $$?; \
	  else \
	    echo "[coverage] coverage.py or python tests unavailable — documented in tests/COVERAGE.md"; \
	  fi
	@echo "[coverage] done."

# ---------------------------------------------------------------------------
# benchmark: deterministic dual-path TTT. NEVER --live, NEVER network (AC-8).
# ---------------------------------------------------------------------------
benchmark:
	@echo "[benchmark] deterministic dual-path TTT (no --live, no network)…"
	@"$(PLUGIN_ROOT)/benchmark/run-benchmark.sh"
	@echo "[benchmark] running harness self-tests (schema / rotation / generators)…"
	@cd "$(PLUGIN_ROOT)" && $(PYTHON) -m unittest discover -s benchmark/tests/with-plugin -p 'test_*.py' -v
	@cd "$(PLUGIN_ROOT)" && $(PYTHON) benchmark/lib/report.py

# ---------------------------------------------------------------------------
# benchmark-live: opt-in. Credential-gated, budget-capped. Never a dep of any
# other target. Never CI. (AC-8 live side; DV0e implements behind --live.)
# ---------------------------------------------------------------------------
benchmark-live:
	@echo "[benchmark-live] OPT-IN live A/B — credential probe + budget cap apply."
	@"$(PLUGIN_ROOT)/benchmark/run-benchmark.sh" --live --budget $${BUDGET:-5.00}
	@cd "$(PLUGIN_ROOT)" && $(PYTHON) benchmark/lib/report.py

# ---------------------------------------------------------------------------
# report: render benchmark/results/history.json -> benchmark/results/result.html
# (all metrics per retained run + generated-app paths). Auto-run after benchmark.
# ---------------------------------------------------------------------------
report:
	@cd "$(PLUGIN_ROOT)" && $(PYTHON) benchmark/lib/report.py

# ---------------------------------------------------------------------------
# clean: remove generated workdirs + coverage intermediates + caches.
# Leaves history.json + vendored frameworks.
# ---------------------------------------------------------------------------
clean:
	@echo "[clean] removing workdirs / coverage intermediates / caches…"
	@rm -rf "$(PLUGIN_ROOT)/benchmark/workdirs"/* 2>/dev/null || true
	@rm -rf "$(COVDIR)" "$(PLUGIN_ROOT)/.coverage" 2>/dev/null || true
	@find "$(PLUGIN_ROOT)" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
	@echo "[clean] done (history.json + tests/vendor preserved)."
