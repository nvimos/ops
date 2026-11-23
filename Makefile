# nvimos frontend: Flutter Windows app for reviewing branches, staging, and OpenSpec/Backlog tasks.
# Recipes run in pwsh (native Windows GNU make). Start with:  make help
# Variables are lowercase (make test test_timeout=30s); only the ones exported for other tools keep
# the names those tools read (PUB_CACHE, CMAKE_BUILD_PARALLEL_LEVEL).

SHELL       := pwsh.exe
.SHELLFLAGS := -NoProfile -NoLogo -Command

flutter_root ?= C:/tools/flutter
export PUB_CACHE ?= C:/tools/pub-cache
flutter := $(flutter_root)/bin/flutter.bat
port    ?= 6666
# Per-test timeout of make test; dart_test.yaml (plain flutter test) repeats it, keep the two equal.
test_timeout ?= 55s
test_concurrency ?= 2
# Parallel jobs of the native build (CMake / MSBuild); `cmake --build` reads CMAKE_BUILD_PARALLEL_LEVEL.
build_concurrency ?= 4
export CMAKE_BUILD_PARALLEL_LEVEL := $(build_concurrency)

.PHONY: help run live build dev all dist single bin-local release test test-fast analyze icon nvim timings measure configure release-configure

# `make help` prints the `##@` lines as section headers and `target: ## text` as entries.
.DEFAULT_GOAL := help

##@ run

nvim: ## start Neovim on 127.0.0.1:6666 (port=) with the backend plugin (added after the config, which may reset rtp)
	nvim --listen 127.0.0.1:$(port) -c 'set rtp^=$(CURDIR)/../nvimos-poc-backend | runtime plugin/nvimos.lua'

run: ## run the app (debug); connects to 127.0.0.1:6666
	$(flutter) run -d windows

live: ## run the app (debug) and hot-reload it on every save under lib/ (restart=1: hot restart)
	pwsh -NoProfile -File tool/live.ps1 -Flutter "$(flutter)" $(if $(restart),-Restart,)

##@ build

configure: ## build options, kept until changed: pdf=on|off (pdfrx + PDFium, slow; default off), markdown=on|off, html=on|off (rendered preview; default on); none given: print them
	pwsh -NoProfile -File tool/configure.ps1 $(configure_args) -Flutter "$(flutter)"

# Only the options given on the command line; the rest keep what is configured.
configure_args = $(strip $(if $(pdf),-Pdf '$(pdf)') $(if $(markdown),-Markdown '$(markdown)') $(if $(html),-Html '$(html)'))

build: ## build the release exe (build/windows/x64/runner/Release)
	$(flutter) build windows --release

dev: ## build the debug exe without starting it (build/windows/x64/runner/Debug, the build run and live use)
	$(flutter) build windows --debug

version ?= $(shell pwsh -NoProfile -Command "Get-Date -Format yyyy-MM-dd")

dist: build ## release build zipped as dist/ops-windows-x64-<version>.zip (version= defaults to today)
	pwsh -NoProfile -File tool/dist.ps1 -Zip -Version '$(version)'

single: build ## one-file exe dist/ops-windows-x64-<version>-single.exe (needs Enigma Virtual Box)
	pwsh -NoProfile -File tool/dist.ps1 -Single -Version '$(version)'

all: dev single ## every build: the debug exe, the release exe and the one-file exe

bin-local: single ## build the one-file exe and copy it to ~/.local/bin/ops.exe (a bare Release ops.exe needs its dll and data/)
	Copy-Item -Force 'dist/ops-windows-x64-$(version)-single.exe' "$$env:USERPROFILE/.local/bin/ops.exe"
	@'installed {0}\.local\bin\ops.exe' -f $$env:USERPROFILE

release: release-configure build ## zip and single exe from one build configured as release_config, uploaded as GitHub release v<version> (nvimos/ops)
	pwsh -NoProfile -File tool/dist.ps1 -Zip -Single -Version '$(version)'
	gh release create 'v$(version)' dist/ops-windows-x64-$(version).zip dist/ops-windows-x64-$(version)-single.exe --repo nvimos/ops --title 'ops $(version)' --generate-notes

release_config := -Pdf on -Markdown on -Html on

release-configure:
	pwsh -NoProfile -File tool/configure.ps1 $(release_config) -Flutter "$(flutter)"

icon: ## rebuild windows/runner/resources/app_icon.ico from assets/icon/ops.svg
	pwsh -NoProfile -File tool/icon.ps1

##@ test

test: ## unit and integration tests (headless Neovim); test_timeout=Ns (timeout per test)
	$(flutter) test --timeout $(test_timeout) --concurrency=$(test_concurrency)

test-fast: ## unit and integration tests, fail fast (test_concurrency=2 by default)
	$(flutter) test --timeout $(test_timeout) --concurrency=$(test_concurrency) --fail-fast

analyze: ## static analysis
	$(flutter) analyze

##@ timing

which  ?= last
filter ?=

timings: ## UI timings the app recorded, ms per action (which=last|totals|<n back>, filter=tasks)
	@pwsh -NoProfile -File tool/timings.ps1 -Which '$(which)' -Filter '$(filter)'

measure: ## time Tasks checkbox clicks in a 300-task repo with a headless Neovim
	$(flutter) test test/timing_measure_test.dart

##@ other

help: ## this list
	@Select-String -Path Makefile -Pattern '^##@ (.*)', '^([a-z-]+):.*## (.*)' | ForEach-Object { $$g = $$_.Matches[0].Groups; if ($$_.Line.StartsWith('##@')) { ''; $$g[1].Value } else { '  {0,-10} {1}' -f $$g[1].Value, $$g[2].Value } }


