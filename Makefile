# nvimos frontend: Flutter Windows app for reviewing branches, staging, and OpenSpec/Backlog tasks.
# Recipes run in pwsh (native Windows GNU make). Start with:  make help

SHELL       := pwsh.exe
.SHELLFLAGS := -NoProfile -NoLogo -Command

FLUTTER_ROOT ?= C:/tools/flutter
export PUB_CACHE ?= C:/tools/pub-cache
FLUTTER := $(FLUTTER_ROOT)/bin/flutter.bat
PORT    ?= 6666
# Per-test timeout of make test; dart_test.yaml (plain flutter test) repeats it, keep the two equal.
TEST_TIMEOUT ?= 55s
TEST_CONCURRENCY ?= 4
# Parallel jobs of the native build (CMake / MSBuild); `cmake --build` reads this variable.
BUILD_CONCURRENCY ?= 4
export CMAKE_BUILD_PARALLEL_LEVEL := $(BUILD_CONCURRENCY)

.PHONY: help run live build dist single bin-local release test analyze nvim timings measure pdf-on pdf-off pdf-status

# `make help` prints the `##@` lines as section headers and `target: ## text` as entries.
.DEFAULT_GOAL := help

##@ run

nvim: ## start Neovim on 127.0.0.1:6666 (PORT=) with the backend plugin (added after the config, which may reset rtp)
	nvim --listen 127.0.0.1:$(PORT) -c 'set rtp^=$(CURDIR)/../nvimos-poc-backend | runtime plugin/nvimos.lua'

run: ## run the app (debug); connects to 127.0.0.1:6666
	$(FLUTTER) run -d windows

live: ## run the app (debug) and hot-reload it on every save under lib/ (RESTART=1: hot restart)
	pwsh -NoProfile -File tool/live.ps1 -Flutter "$(FLUTTER)" $(if $(RESTART),-Restart,)

build: ## build the release exe (build/windows/x64/runner/Release)
	$(FLUTTER) build windows --release

VERSION ?= $(shell pwsh -NoProfile -Command "Get-Date -Format yyyy-MM-dd")

dist: build ## release build zipped as dist/ops-windows-x64-<VERSION>.zip (VERSION= defaults to today)
	pwsh -NoProfile -File tool/dist.ps1 -Zip -Version '$(VERSION)'

single: build ## one-file exe dist/ops-windows-x64-<VERSION>-single.exe (needs Enigma Virtual Box)
	pwsh -NoProfile -File tool/dist.ps1 -Single -Version '$(VERSION)'

bin-local: single ## build the one-file exe and copy it to ~/.local/bin/ops.exe (a bare Release ops.exe needs its dll and data/)
	Copy-Item -Force 'dist/ops-windows-x64-$(VERSION)-single.exe' "$$env:USERPROFILE/.local/bin/ops.exe"
	@'installed {0}\.local\bin\ops.exe' -f $$env:USERPROFILE

release: pdf-off build ## zip and single exe from one build without PDF, uploaded as GitHub release v<VERSION> (nvimos/ops)
	pwsh -NoProfile -File tool/dist.ps1 -Zip -Single -Version '$(VERSION)'
	gh release create 'v$(VERSION)' dist/ops-windows-x64-$(VERSION).zip dist/ops-windows-x64-$(VERSION)-single.exe --repo nvimos/ops --title 'ops $(VERSION)' --generate-notes

##@ test

test: ## unit and integration tests (headless Neovim); TEST_TIMEOUT=Ns (33s, timeout per test)
	$(FLUTTER) test --timeout $(TEST_TIMEOUT) --concurrency=$(TEST_CONCURRENCY)

test-fast: ## unit and integration tests, fail fast (default TEST_CONCURRENCY=4)
	$(FLUTTER) test --timeout $(TEST_TIMEOUT) --concurrency=$(TEST_CONCURRENCY) --fail-fast

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

pdf-on: ## draw PDF pages in the preview (pdfrx + PDFium: a slow first build); for testing PDF locally
	pwsh -NoProfile -File tool/pdf.ps1 -Mode on -Flutter "$(FLUTTER)"

pdf-off: ## the default: no PDF library, so a quick build; a PDF shows its facts and the Open button only
	pwsh -NoProfile -File tool/pdf.ps1 -Mode off -Flutter "$(FLUTTER)"

pdf-status: ## whether the PDF pages are on or off
	@pwsh -NoProfile -File tool/pdf.ps1 -Mode status

icon: ## rebuild windows/runner/resources/app_icon.ico from assets/icon/ops.svg
	pwsh -NoProfile -File tool/icon.ps1

help: ## this list
	@Select-String -Path Makefile -Pattern '^##@ (.*)', '^([a-z-]+):.*## (.*)' | ForEach-Object { $$g = $$_.Matches[0].Groups; if ($$_.Line.StartsWith('##@')) { ''; $$g[1].Value } else { '  {0,-9} {1}' -f $$g[1].Value, $$g[2].Value } }
