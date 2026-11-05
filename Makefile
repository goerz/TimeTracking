# TimeTracking: build, install, and test (architecture.md §2.5).
# `make help` lists the targets. Personal settings live in local.mk (see
# local.mk.example). Works with GNU make 3.81 (macOS) and later.

-include local.mk

TEAM ?=
BUNDLE_ID ?= com.example.timetracking
APP_NAME ?= TimeTracking
PREFIX ?= $(HOME)/.local
ALIAS ?=
ARGS ?=
D ?=
FIXTURE ?= small
SHOTS ?=

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

SHELL := /bin/bash
.DEFAULT_GOAL := all

# Tools and folders; tests override them (scripts/test_make.sh).
XCODEBUILD ?= xcodebuild
LAUNCHCTL ?= launchctl
UV ?= uv
DERIVED ?= build.noindex
KEYCHAIN ?=
XCFLAGS ?=
PROJECT := TimeTracking.xcodeproj
XCB = $(XCODEBUILD) -quiet -project $(PROJECT) -derivedDataPath $(DERIVED) -skipPackagePluginValidation -skipMacroValidation $(XCFLAGS)
SIGN := -allowProvisioningUpdates -allowProvisioningDeviceRegistration

PRODUCTS = $(DERIVED)/Build/Products
MAC_RELEASE_APP = $(PRODUCTS)/Release/$(APP_NAME).app
# Debug Mac bundles carry " Debug" in their file names (architecture.md §2.2).
MAC_DEBUG_APP = $(PRODUCTS)/Debug/$(APP_NAME) Debug.app
DEBUG_AGENT = $(MAC_DEBUG_APP)/Contents/Library/LoginItems/TimeTrackingAgent Debug.app
# Debug products built before the rename; mac-debug-unregister cleans them up too.
LEGACY_DEBUG_APP = $(PRODUCTS)/Debug/$(APP_NAME).app
LEGACY_DEBUG_AGENT = $(LEGACY_DEBUG_APP)/Contents/Library/LoginItems/TimeTrackingAgent.app
IOS_RELEASE_APP = $(PRODUCTS)/Release-iphoneos/$(APP_NAME).app
SIM_APP = $(PRODUCTS)/Debug-iphonesimulator/$(APP_NAME).app
INSTALLED_APP = /Applications/$(APP_NAME).app
DEBUG_SUPPORT = $(HOME)/Library/Group Containers/$(TEAM).$(BUNDLE_ID).debug/Library/Application Support/TimeTracking

SIM_IPHONE := TimeTracking iPhone
SIM_IPAD := TimeTracking iPad
SIM_IPHONE_TYPE := com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
SIM_IPAD_TYPE := com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB
MAC_DEST := -destination 'platform=macOS,arch=arm64'
# The simulators by UDID, looked up by name in the recipe's shell (architecture.md
# §2.6, docs/xcode27.md): a `name=` destination implies OS=latest and misses a
# simulator on an older runtime. SIM_UDIDS starts a recipe line that uses the two.
SIMULATOR := scripts/simulator.sh
SIM_UDIDS = iphone=$$($(SIMULATOR) udid "$(SIM_IPHONE)") && ipad=$$($(SIMULATOR) udid "$(SIM_IPAD)") &&
IPHONE_DEST = -destination "platform=iOS Simulator,id=$$iphone"
IPAD_DEST = -destination "platform=iOS Simulator,id=$$ipad"

# Command lines that more than one target runs.
BUILD_MAC_DEBUG = $(XCB) build -scheme TimeTracking -configuration Debug $(MAC_DEST) $(SIGN)
BUILD_SIM_DEBUG = $(SIM_UDIDS) $(XCB) build -scheme TimeTrackingiOS -configuration Debug $(IPHONE_DEST) $(SIGN)
AGENT_TEST = $(XCB) test -scheme TimeTrackingAgent $(MAC_DEST) -only-testing:TimeTrackingAgentTests $(SIGN)

LOCAL_XCCONFIG := Config/Local.xcconfig

# The first line of every recipe that builds an app (architecture.md §2.3).
require_team = @if [ -z "$(TEAM)" ]; then echo "set TEAM in local.mk" >&2; exit 1; fi

.PHONY: all build build-mac build-ios build-sim docs sim sim-create stop mac-debug mac-debug-unregister demo \
	logs sim-logs sim-screenshots screenshots install mac uninstall apns-key device iphone ipad devices console \
	unit-test agent-test ui-test test test-sync lint check-behaviors check-citations check-private check hooks \
	secrets xcode skills clean distclean help

# The runtime lock (architecture.md §2.5): every checkout of the repository
# shares the Debug bundle ID, the Debug store and agent, the simulators, and
# /Applications, so the targets that run them hold one lock in the shared git
# directory. Outside the lock, each such target runs make again under lockf,
# whose kernel lock ends with the process; nested make calls inherit
# TT_RUNTIME_LOCKED and run directly. The real rules sit in ifdef blocks below.
RUNTIME_LOCK ?= $(shell git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$(CURDIR)/$(DERIVED)")/timetracking-runtime.lock
RUNTIME_TARGETS := sim mac-debug demo screenshots install unit-test agent-test ui-test test test-sync

ifndef TT_RUNTIME_LOCKED
$(RUNTIME_TARGETS):
	@mkdir -p "$$(dirname "$(RUNTIME_LOCK)")"
	@TT_RUNTIME_LOCKED=1 lockf -k -t 0 "$(RUNTIME_LOCK)" $(MAKE) --no-print-directory $@ || \
		{ s=$$?; [ $$s != 75 ] || echo "another checkout is running sim, mac-debug, demo, screenshots, install, or a test target; retry when it finishes ($(RUNTIME_LOCK))" >&2; exit $$s; }
endif

##@ Build

all build: build-mac build-ios ## build-mac and build-ios

build-mac: secrets ## Release Mac app with agent and tools; checks the products; unregisters build copies
	$(require_team)
	$(XCB) build -scheme TimeTracking -configuration Release -destination 'generic/platform=macOS' $(SIGN)
	scripts/check_products.sh mac "$(MAC_RELEASE_APP)" "$(BUNDLE_ID)" "$(TEAM)"
	@scripts/unregister_builds.sh "$(BUNDLE_ID)" "$(INSTALLED_APP)"

build-ios: secrets ## Release iOS app for generic/platform=iOS; checks the products
	$(require_team)
	$(XCB) build -scheme TimeTrackingiOS -configuration Release -destination 'generic/platform=iOS' $(SIGN)
	scripts/check_products.sh ios "$(IOS_RELEASE_APP)" "$(BUNDLE_ID)" "$(TEAM)"

build-sim: secrets ## Debug iOS app for the simulator
	$(require_team)
	@$(MAKE) --no-print-directory sim-create
	$(BUILD_SIM_DEBUG)

docs: ## The documentation site into build.noindex/docs/, with warnings as errors
	$(UV) run --project docs --locked sphinx-build -W --keep-going -q -b html docs "$(DERIVED)/docs"
	@echo "Built $(DERIVED)/docs/index.html"

##@ Develop

ifdef TT_RUNTIME_LOCKED
sim: build-sim ## Install and launch on "TimeTracking iPhone" and "TimeTracking iPad" with ARGS; show them in Device Hub
	@for name in "$(SIM_IPHONE)" "$(SIM_IPAD)"; do \
		udid=$$($(SIMULATOR) udid "$$name") || exit 1; \
		xcrun simctl bootstatus "$$udid" -b >/dev/null && \
		xcrun simctl install "$$udid" "$(SIM_APP)" && \
		xcrun simctl launch --terminate-running-process "$$udid" "$(BUNDLE_ID).debug" $(ARGS) || exit 1; \
	done
	@$(SIMULATOR) show "$(SIM_IPHONE)" "$(SIM_IPAD)"
endif

# Without a runtime argument, simctl picks the newest runtime that supports the
# device type, which skips device-specific runtimes such as "iOS 27.2 iPhone19-4".
sim-create: ## Create the two simulators unless they exist
	@xcrun simctl list runtimes available | grep -q '^iOS ' || { echo "no iOS simulator runtime installed" >&2; exit 1; }; \
	for pair in "$(SIM_IPHONE)=$(SIM_IPHONE_TYPE)" "$(SIM_IPAD)=$(SIM_IPAD_TYPE)"; do \
		name="$${pair%%=*}"; type="$${pair#*=}"; \
		if $(SIMULATOR) udid "$$name" >/dev/null 2>&1; then continue; fi; \
		xcrun simctl create "$$name" "$$type" >/dev/null && echo "Created $$name"; \
	done

stop: ## Quit the app on both simulators
	@for name in "$(SIM_IPHONE)" "$(SIM_IPAD)"; do \
		udid=$$($(SIMULATOR) udid "$$name" 2>/dev/null) || continue; \
		xcrun simctl terminate "$$udid" "$(BUNDLE_ID).debug" 2>/dev/null || true; \
	done

ifdef TT_RUNTIME_LOCKED
mac-debug: secrets ## Build the Debug Mac app in build.noindex/; quit a running Debug app; open the new one with ARGS
	$(require_team)
	$(BUILD_MAC_DEBUG)
	scripts/relaunch_mac_app.sh "$(MAC_DEBUG_APP)" "$(BUNDLE_ID).debug" $(ARGS)

demo: secrets ## Load FIXTURE (small, large, running) moved to today into the Debug stores; open the Mac app and simulators
	$(require_team)
	@[ -f "Fixtures/Store/$(FIXTURE).json" ] || { echo "no store fixture $(FIXTURE) (small, large, running)" >&2; exit 1; }
	$(BUILD_MAC_DEBUG)
	@$(MAKE) --no-print-directory sim-create
	$(BUILD_SIM_DEBUG)
	scripts/demo.sh "$(FIXTURE)" "$(MAC_DEBUG_APP)" "$(DEBUG_SUPPORT)" "$(BUNDLE_ID).debug" "$(SIM_APP)" "$(SIM_IPHONE)" "$(SIM_IPAD)"
endif

mac-debug-unregister: ## Quit the Debug app and agent, unregister the agent, reset its TCC grants
	@LAUNCHCTL="$(LAUNCHCTL)" scripts/debug_unregister.sh "$(BUNDLE_ID).debug" "$(DEBUG_AGENT)" "$(LEGACY_DEBUG_AGENT)" \
		"$(PRODUCTS)/Debug/TimeTrackingAgent Debug.app" "$(PRODUCTS)/Debug/TimeTrackingAgent.app"

logs: ## Stream the unified log of the installed Mac app, agent, and tools
	log stream --style compact --level info \
		--predicate 'subsystem BEGINSWITH "$(BUNDLE_ID)" AND NOT subsystem CONTAINS ".debug"'

sim-logs: ## Stream the unified log of the simulator app
	$(SIM_UDIDS) xcrun simctl spawn "$$iphone" log stream --style compact --level info \
		--predicate 'subsystem BEGINSWITH "$(BUNDLE_ID).debug"'

sim-screenshots: ## Simulator screenshots to build.noindex/sim-screenshots/
	@mkdir -p "$(DERIVED)/sim-screenshots"
	@stamp=$$(date +%Y%m%d-%H%M%S); for name in "$(SIM_IPHONE)" "$(SIM_IPAD)"; do \
		file="$(DERIVED)/sim-screenshots/$${name// /-}-$$stamp.png"; \
		udid=$$($(SIMULATOR) udid "$$name") || continue; \
		xcrun simctl io "$$udid" screenshot "$$file" >/dev/null 2>&1 && echo "$$file" || echo "$$name is not booted" >&2; \
	done

ifdef TT_RUNTIME_LOCKED
screenshots: secrets ## Retake the site's screenshots from the fixtures into docs/images/ (SHOTS=name... limits them)
	$(require_team)
	scripts/capture_screenshots.py "$(DERIVED)/screenshots" $(SHOTS)
	scripts/frame_screenshots.py "$(DERIVED)/screenshots" docs/images $(SHOTS)
endif

##@ Use

ifdef TT_RUNTIME_LOCKED
install: build-mac ## Install into /Applications; link the tools and completions into PREFIX
	scripts/install.sh install "$(MAC_RELEASE_APP)" "$(BUNDLE_ID)" "$(APP_NAME)" "$(PREFIX)" "$(ALIAS)"
endif

mac: install ## install, then open the app with ARGS
	open "$(INSTALLED_APP)" --args $(ARGS)

uninstall: ## Remove the app, links, and completions; keep data and the Keychain item
	scripts/install.sh uninstall "$(BUNDLE_ID)" "$(APP_NAME)" "$(PREFIX)" "$(ALIAS)"

apns-key: ## Store the APNs auth key: make apns-key P8=<path>/AuthKey_<KEYID>.p8 [KEY_ID=<id>]
	@scripts/apns_key.sh "$(P8)" "$(KEY_ID)" "$(TEAM)" "$(BUNDLE_ID)" "$(INSTALLED_APP)" "$(KEYCHAIN)"

device: secrets ## Release build for DEVICE_<D>, install and launch with devicectl
	$(require_team)
	@[ -n "$(DEVICE_$(D))" ] || { echo "set DEVICE_$(D) in local.mk (make devices lists UDIDs)" >&2; exit 1; }
	$(XCB) build -scheme TimeTrackingiOS -configuration Release -destination 'id=$(DEVICE_$(D))' $(SIGN)
	xcrun devicectl device install app --device "$(DEVICE_$(D))" "$(IOS_RELEASE_APP)"
	xcrun devicectl device process launch --terminate-existing --device "$(DEVICE_$(D))" "$(BUNDLE_ID)" $(ARGS)

iphone: ## make device D=iphone
	@$(MAKE) --no-print-directory device D=iphone

ipad: ## make device D=ipad
	@$(MAKE) --no-print-directory device D=ipad

devices: ## List known physical devices
	@xcrun devicectl list devices --filter "Reality = 'physical'"
	@echo; echo "Configured in local.mk:"; $(foreach v,$(filter DEVICE_%,$(.VARIABLES)),echo "  $(v:DEVICE_%=%) = $($(v))";) true

console: ## Relaunch on DEVICE_<D> and stream its console
	@[ -n "$(DEVICE_$(D))" ] || { echo "set DEVICE_$(D) in local.mk" >&2; exit 1; }
	xcrun devicectl device process launch --console --terminate-existing --device "$(DEVICE_$(D))" "$(BUNDLE_ID)" $(ARGS)

##@ Test

ifdef TT_RUNTIME_LOCKED
unit-test: secrets ## (3 min) swift test, then TimeTrackingTests, TimeTrackingAgentTests, TimeTrackingCLITests
	swift test --package-path Packages/TimeTrackingCore
	$(require_team)
	$(XCB) test -scheme TimeTracking $(MAC_DEST) -only-testing:TimeTrackingTests -only-testing:TimeTrackingCLITests $(SIGN)
	$(AGENT_TEST)

agent-test: secrets ## (1 min) TimeTrackingAgentTests
	$(require_team)
	$(AGENT_TEST)

ui-test: secrets ## (8 min) Mac UI tests, iOS UI tests on both simulators (UI_TESTS=Class[/method] runs only those Mac tests, IPAD_UI_TESTS those on the iPad simulator)
	$(require_team)
ifdef UI_TESTS
	$(XCB) test -scheme TimeTracking $(MAC_DEST) $(foreach t,$(UI_TESTS),-only-testing:TimeTrackingUITests/$(t)) $(SIGN)
else ifdef IPAD_UI_TESTS
	@$(MAKE) --no-print-directory sim-create
	$(SIM_UDIDS) $(XCB) test -scheme TimeTrackingiOS $(IPAD_DEST) $(foreach t,$(IPAD_UI_TESTS),-only-testing:TimeTrackingiOSUITests/$(t)) $(SIGN)
else
	@$(MAKE) --no-print-directory sim-create
	$(XCB) test -scheme TimeTracking $(MAC_DEST) -only-testing:TimeTrackingUITests $(SIGN)
	$(SIM_UDIDS) $(XCB) test -scheme TimeTrackingiOS $(IPHONE_DEST) $(IPAD_DEST) -only-testing:TimeTrackingiOSUITests $(SIGN)
endif

test: unit-test ## (15 min) unit-test, slow library tests, TimeTrackingiOSTests on the iPhone simulator, ui-test
	@# Timing targets hold for optimized builds, one test at a time (data_and_sync.md §7.5).
	TIMETRACKING_TEST_SLOW=1 swift test --package-path Packages/TimeTrackingCore -c release -Xswiftc -enable-testing --no-parallel --filter PerformanceTests
	@$(MAKE) --no-print-directory sim-create
	$(SIM_UDIDS) $(XCB) test -scheme TimeTrackingiOS $(IPHONE_DEST) -only-testing:TimeTrackingiOSTests $(SIGN)
	@$(MAKE) --no-print-directory ui-test

test-sync: secrets ## (3 min) CloudKit integration tests against iCloud.<BUNDLE_ID>.debug; never part of test
	$(require_team)
	TEST_RUNNER_TIMETRACKING_TEST_SYNC=1 $(XCB) test -scheme TimeTracking $(MAC_DEST) -only-testing:TimeTrackingTests $(SIGN)
endif

##@ Check

lint: ## SwiftFormat --lint and SwiftLint --strict from the package checkouts; no build
	@scripts/lint.sh "$(DERIVED)"

check-behaviors: ## Every testable behavior has a test (ONLY=ARCH,DATA limits the failures)
	@scripts/check_behaviors.sh $(if $(ONLY),--only $(ONLY))

check-citations: ## Every citation of a spec names an existing section
	@scripts/check_citations.py

check-private: ## Refuse tracked files with personal data
	@.githooks/check-private tree

check: lint check-behaviors check-citations check-private ## lint, check-behaviors, check-citations, check-private

hooks: ## Use the git hooks in .githooks/
	@if git rev-parse --git-dir >/dev/null 2>&1; then git config core.hooksPath .githooks; fi

##@ Project

secrets: hooks ## Write Config/Local.xcconfig from local.mk (only when it changes)
	@content=$$(printf '%s\n' \
		'// Written by `make secrets` from local.mk; git-ignored. Do not edit.' \
		'TT_BUNDLE_ID = $(BUNDLE_ID)' \
		'TT_APP_NAME = $(APP_NAME)' \
		'DEVELOPMENT_TEAM = $(TEAM)'); \
	if [ ! -f $(LOCAL_XCCONFIG) ] || [ "$$content" != "$$(cat $(LOCAL_XCCONFIG))" ]; then \
		printf '%s\n' "$$content" > $(LOCAL_XCCONFIG); echo "Wrote $(LOCAL_XCCONFIG)"; \
	fi

xcode: secrets ## Write the xcconfig and open the project
	open $(PROJECT)

skills: ## Export Xcode's agent skills into .claude/skills/ (git-ignored)
	@mkdir -p .claude/skills
	xcrun mcpbridge run-agent skills export --output-dir "$(CURDIR)/.claude/skills" --replace-existing

clean: ## Remove intermediates; keep build.noindex/Build/Products
	@if [ -d "$(DERIVED)" ]; then \
		find "$(DERIVED)" -mindepth 1 -maxdepth 1 ! -name Build ! -name SourcePackages ! -name LintTools ! -name screenshots ! -name sim-screenshots ! -name docs -exec rm -rf {} +; \
		[ ! -d "$(DERIVED)/Build" ] || find "$(DERIVED)/Build" -mindepth 1 -maxdepth 1 ! -name Products -exec rm -rf {} +; \
	fi
	@echo "Removed intermediates; kept $(PRODUCTS)"

distclean: ## Remove build.noindex/ (refuses while the Debug agent is registered)
	@if $(LAUNCHCTL) print "gui/$$(id -u)/$(BUNDLE_ID).debug.agent" >/dev/null 2>&1; then \
		echo "The Debug agent is registered; run make mac-debug-unregister first" >&2; exit 1; \
	fi
	rm -rf "$(DERIVED)"

help: ## The grouped listing of targets
	@awk 'BEGIN { FS = ":.*## " } \
		/^##@/ { printf "\n%s\n", substr($$0, 5) } \
		/^[a-zA-Z0-9_-]+( [a-zA-Z0-9_-]+)*:.*## / { printf "  %-22s %s\n", $$1, $$2 }' $(firstword $(MAKEFILE_LIST))
