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

.PHONY: help run live build dev single release test test-fast analyze icon nvim timings measure configure release-configure snappy snappy-app snappy-baseline snapshot

# `make help` prints the `##@` lines as section headers and `target: ## text` as entries: one short
# line each. Paths, options and why go in plain comments above the target.
.DEFAULT_GOAL := help

##@ run

# Neovim listens on 127.0.0.1:$(port) with the relay plugin from ../nvimos-relay, put on the rtp after
# the config (which may reset rtp).
nvim: ## Neovim with the relay plugin (port=6666)
	nvim --listen 127.0.0.1:$(port) -c 'set rtp^=$(CURDIR)/../nvimos-relay | runtime plugin/nvimos.lua'

run: ## run the app (debug)
	$(flutter) run -d windows

# restart=1: a hot restart on save instead of a hot reload.
live: ## run the app, hot-reload on save (restart=1)
	pwsh -NoProfile -File tool/live.ps1 -Flutter "$(flutter)" $(if $(restart),-Restart,)

##@ build

# Everyday builds have PDF off (fast); single and release turn every option on (release_config) and
# switch PDF back off when done (everyday_config). The release workflow does the same.

# build/windows/x64/runner/Debug, the exe run and live use.
dev: ## debug exe (fast, PDF off)
	$(flutter) build windows --debug

version ?= $(shell pwsh -NoProfile -Command "Get-Date -Format yyyy-MM-dd")

# dist/ops-windows-x64-<version>-single.exe (version= defaults to today), copied to
# ~/.local/bin/ops.exe; needs Enigma Virtual Box. A bare Release ops.exe would need its dll and data/.
single: release-configure build
single: ## one-file exe, all options, installed to ~/.local/bin
	pwsh -NoProfile -File tool/dist.ps1 -Single -Version '$(version)'
	Copy-Item -Force 'dist/ops-windows-x64-$(version)-single.exe' "$$env:USERPROFILE/.local/bin/ops.exe"
	@'installed {0}\.local\bin\ops.exe' -f $$env:USERPROFILE
	pwsh -NoProfile -File tool/configure.ps1 $(everyday_config) -Flutter "$(flutter)"

# The zip and the one-file exe from one build, uploaded as GitHub release v<version> of nvimos/ops.
release: release-configure build
release: ## GitHub release: zip + one-file exe, all options
	pwsh -NoProfile -File tool/dist.ps1 -Zip -Single -Version '$(version)'
	gh release create 'v$(version)' dist/ops-windows-x64-$(version).zip dist/ops-windows-x64-$(version)-single.exe --repo nvimos/ops --title 'ops $(version)' --generate-notes
	pwsh -NoProfile -File tool/configure.ps1 $(everyday_config) -Flutter "$(flutter)"

# Steps of single and release, not in the help: the Release folder (build/windows/x64/runner/Release)
# and the option sets.
build:
	$(flutter) build windows --release

release_config := -Pdf on -Markdown on -Html on
everyday_config := -Pdf off

release-configure:
	pwsh -NoProfile -File tool/configure.ps1 $(release_config) -Flutter "$(flutter)"

##@ test

# test_timeout=Ns per test (keep dart_test.yaml equal), test_concurrency=N files at a time.
test: ## all tests (headless Neovim)
	$(flutter) test --timeout $(test_timeout) --concurrency=$(test_concurrency)

test-fast: ## all tests, stop at the first failure
	$(flutter) test --timeout $(test_timeout) --concurrency=$(test_concurrency) --fail-fast

analyze: ## static analysis
	$(flutter) analyze

##@ timing

which  ?= last
filter ?=

# Milliseconds per action the app recorded; which=last|totals|<n sessions back>, filter=tasks.
timings: ## UI timings the app recorded
	@pwsh -NoProfile -File tool/timings.ps1 -Which '$(which)' -Filter '$(filter)'

# Tasks checkbox clicks in a 300-task repo with a headless Neovim.
measure: ## time Tasks checkbox clicks
	$(flutter) test test/timing_measure_test.dart

# The widget test on the snapshot, a table per view; also part of make test.
snappy: ## Tasks responsiveness checks
	$(flutter) test test/snappy_tasks_test.dart

strict ?=

# The profile app on Windows (a window opens for a few minutes): frame timings per view, recorded in
# out/snappy-app and compared with test/fixtures/snappy_app_baseline.json; strict=1: drift fails too.
snappy-app: ## frame timings in the profile app (strict=1)
	pwsh -NoProfile -File tool/snappy_app.ps1 -Flutter "$(flutter)" $(if $(strict),-Strict,)

# The slowest of the last 3 snappy-app runs per key; commit the file by hand.
snappy-baseline: ## new snappy-app baseline
	$(flutter_root)/bin/dart.bat run tool/snappy_baseline.dart

from ?= ../nvimos-meta

# test/fixtures/tasks_snappy.json from a planning repo (from=<path>, default ../nvimos-meta), read only.
snapshot: ## refresh the snappy snapshot (from=)
	$(flutter_root)/bin/dart.bat run tool/snappy_fixture.dart '$(from)'

##@ other

# pdf=on|off (pdfrx + PDFium, slow; default off), markdown=on|off, html=on|off (default on); kept
# until changed; none given: prints them.
configure: ## build options: pdf, markdown, html = on|off
	pwsh -NoProfile -File tool/configure.ps1 $(configure_args) -Flutter "$(flutter)"

# Only the options given on the command line; the rest keep what is configured.
configure_args = $(strip $(if $(pdf),-Pdf '$(pdf)') $(if $(markdown),-Markdown '$(markdown)') $(if $(html),-Html '$(html)'))

# windows/runner/resources/app_icon.ico from assets/icon/ops.svg.
icon: ## redraw the app icon
	pwsh -NoProfile -File tool/icon.ps1

help: ## this list
	@Select-String -Path Makefile -Pattern '^##@ (.*)', '^([a-z-]+):.*## (.*)' | ForEach-Object { $$g = $$_.Matches[0].Groups; if ($$_.Line.StartsWith('##@')) { ''; $$g[1].Value } else { '  {0,-16} {1}' -f $$g[1].Value, $$g[2].Value } }


