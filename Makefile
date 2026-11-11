# nvimos frontend: Flutter Windows app for reviewing branches, staging, and OpenSpec/Backlog tasks.
# Recipes run in pwsh (native Windows GNU make). Start with:  make help

SHELL       := pwsh.exe
.SHELLFLAGS := -NoProfile -NoLogo -Command

FLUTTER_ROOT ?= C:/tools/flutter
export PUB_CACHE ?= C:/tools/pub-cache
FLUTTER := $(FLUTTER_ROOT)/bin/flutter.bat
PORT    ?= 6666

.PHONY: help run live build test analyze nvim timings measure

# `make help` prints the `##@` lines as section headers and `target: ## text` as entries.
.DEFAULT_GOAL := help

##@ run

nvim: ## start Neovim on 127.0.0.1:6666 (PORT=) with the backend plugin (added after the config, which may reset rtp)
	nvim --listen 127.0.0.1:$(PORT) -c 'set rtp^=$(CURDIR)/../nvimos-poc-backend | runtime plugin/nvimos.lua'

run: ## run the app (debug); connects to 127.0.0.1:6666
	$(FLUTTER) run -d windows

live: ## run the app (debug) and hot-reload it on every save under lib/ (RESTART=1: hot restart)
	pwsh -NoProfile -File tool/live.ps1 -Flutter '$(FLUTTER)' $(if $(RESTART),-Restart,)

build: ## build the release exe (build/windows/x64/runner/Release)
	$(FLUTTER) build windows --release

##@ test

test: ## unit and integration tests (the RPC tests start a headless Neovim); 45 s per test
	$(FLUTTER) test --timeout 45s

analyze: ## static analysis
	$(FLUTTER) analyze

##@ timing

WHICH  ?= last
FILTER ?=

timings: ## UI timings the app recorded, ms per action (WHICH=last|totals|<n back>, FILTER=tasks)
	@pwsh -NoProfile -File tool/timings.ps1 -Which '$(WHICH)' -Filter '$(FILTER)'

measure: ## time Tasks checkbox clicks in a 300-task repo with a headless Neovim
	$(FLUTTER) test test/timing_measure_test.dart

##@ other

help: ## this list
	@Select-String -Path Makefile -Pattern '^##@ (.*)', '^([a-z-]+):.*## (.*)' | ForEach-Object { $$g = $$_.Matches[0].Groups; if ($$_.Line.StartsWith('##@')) { ''; $$g[1].Value } else { '  {0,-8} {1}' -f $$g[1].Value, $$g[2].Value } }
