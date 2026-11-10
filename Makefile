# nvimos frontend: Flutter Windows app for reviewing branches, staging, and OpenSpec/Backlog tasks.
# Recipes run in pwsh (native Windows GNU make). Start with:  make help

SHELL       := pwsh.exe
.SHELLFLAGS := -NoProfile -NoLogo -Command

FLUTTER_ROOT ?= H:/flutter
export PUB_CACHE ?= H:/pub-cache
FLUTTER := $(FLUTTER_ROOT)/bin/flutter.bat
PORT    ?= 6666

.PHONY: help run build test analyze nvim

# `make help` prints the `##@` lines as section headers and `target: ## text` as entries.
.DEFAULT_GOAL := help

##@ run

nvim: ## start Neovim on 127.0.0.1:6666 (PORT=) with the backend plugin (added after the config, which may reset rtp)
	nvim --listen 127.0.0.1:$(PORT) --cmd 'set rtp^=$(CURDIR)/../nvimos-poc-backend'

run: ## run the app (debug); connects to 127.0.0.1:6666
	$(FLUTTER) run -d windows

build: ## build the release exe (build/windows/x64/runner/Release)
	$(FLUTTER) build windows --release

##@ test

test: ## unit and integration tests (the RPC tests start a headless Neovim)
	$(FLUTTER) test

analyze: ## static analysis
	$(FLUTTER) analyze

##@ other

help: ## this list
	@Select-String -Path Makefile -Pattern '^##@ (.*)', '^([a-z-]+):.*## (.*)' | ForEach-Object { $$g = $$_.Matches[0].Groups; if ($$_.Line.StartsWith('##@')) { ''; $$g[1].Value } else { '  {0,-8} {1}' -f $$g[1].Value, $$g[2].Value } }
