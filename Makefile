# TimeTracking: build, install, and test (spec_architecture.md §2.5).
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

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

SHELL := /bin/bash
.DEFAULT_GOAL := all

# Tools and folders; tests override them (scripts/test_make.sh).
XCODEBUILD ?= xcodebuild
LAUNCHCTL ?= launchctl
DERIVED ?= build.noindex
KEYCHAIN ?=
XCFLAGS ?=
PROJECT := TimeTracking.xcodeproj
XCB = $(XCODEBUILD) -quiet -project $(PROJECT) -derivedDataPath $(DERIVED) -skipPackagePluginValidation -skipMacroValidation $(XCFLAGS)
SIGN := -allowProvisioningUpdates -allowProvisioningDeviceRegistration
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

PRODUCTS = $(DERIVED)/Build/Products
MAC_RELEASE_APP = $(PRODUCTS)/Release/$(APP_NAME).app
MAC_DEBUG_APP = $(PRODUCTS)/Debug/$(APP_NAME).app
DEBUG_AGENT = $(MAC_DEBUG_APP)/Contents/Library/LoginItems/TimeTrackingAgent.app
IOS_RELEASE_APP = $(PRODUCTS)/Release-iphoneos/$(APP_NAME).app
SIM_APP = $(PRODUCTS)/Debug-iphonesimulator/$(APP_NAME).app
INSTALLED_APP = /Applications/$(APP_NAME).app

SIM_IPHONE := TimeTracking iPhone
SIM_IPAD := TimeTracking iPad
SIM_IPHONE_TYPE := com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
SIM_IPAD_TYPE := com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB
MAC_DEST := -destination 'platform=macOS,arch=arm64'
IPHONE_DEST := -destination 'platform=iOS Simulator,name=$(SIM_IPHONE)'
IPAD_DEST := -destination 'platform=iOS Simulator,name=$(SIM_IPAD)'

LOCAL_XCCONFIG := Config/Local.xcconfig

# The first line of every recipe that builds an app (spec_architecture.md §2.3).
require_team = @if [ -z "$(TEAM)" ]; then echo "set TEAM in local.mk" >&2; exit 1; fi

.PHONY: all build build-mac build-ios build-sim sim sim-create stop mac-debug mac-debug-unregister \
	logs sim-logs screenshots install mac uninstall apns-key device iphone ipad devices console \
	unit-test agent-test ui-test test test-sync lint check-behaviors check-private check hooks \
	secrets xcode skills clean distclean help

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
	$(XCB) build -scheme TimeTrackingiOS -configuration Debug $(IPHONE_DEST) $(SIGN)

##@ Develop

sim: build-sim ## Install and launch on "TimeTracking iPhone" and "TimeTracking iPad" with ARGS
	@for name in "$(SIM_IPHONE)" "$(SIM_IPAD)"; do \
		xcrun simctl boot "$$name" 2>/dev/null || true; \
		xcrun simctl install "$$name" "$(SIM_APP)" && \
		xcrun simctl launch --terminate-running-process "$$name" "$(BUNDLE_ID).debug" $(ARGS) || exit 1; \
	done
	@open -a Simulator

sim-create: ## Create the two simulators unless they exist
	@runtime=$$(xcrun simctl list runtimes | awk '/^iOS / && !/unavailable/ { r = $$NF } END { print r }'); \
	[ -n "$$runtime" ] || { echo "no iOS simulator runtime installed" >&2; exit 1; }; \
	for pair in "$(SIM_IPHONE)=$(SIM_IPHONE_TYPE)" "$(SIM_IPAD)=$(SIM_IPAD_TYPE)"; do \
		name="$${pair%%=*}"; type="$${pair#*=}"; \
		if xcrun simctl list devices | grep -qF "    $$name ("; then continue; fi; \
		xcrun simctl create "$$name" "$$type" "$$runtime" >/dev/null && echo "Created $$name ($$runtime)"; \
	done

stop: ## Quit the app on both simulators
	@for name in "$(SIM_IPHONE)" "$(SIM_IPAD)"; do \
		xcrun simctl terminate "$$name" "$(BUNDLE_ID).debug" 2>/dev/null || true; \
	done

mac-debug: secrets ## Build and open the Debug Mac app from build.noindex/
	$(require_team)
	$(XCB) build -scheme TimeTracking -configuration Debug $(MAC_DEST) $(SIGN)
	open "$(MAC_DEBUG_APP)" --args $(ARGS)

mac-debug-unregister: ## Quit the Debug app and agent, unregister the agent, reset its TCC grants
	@[ ! -x "$(DEBUG_AGENT)/Contents/MacOS/TimeTrackingAgent" ] || "$(DEBUG_AGENT)/Contents/MacOS/TimeTrackingAgent" --unregister || true
	@osascript -e 'if application id "$(BUNDLE_ID).debug" is running then tell application id "$(BUNDLE_ID).debug" to quit' >/dev/null 2>&1 || true
	@$(LAUNCHCTL) bootout "gui/$$(id -u)/$(BUNDLE_ID).debug.agent" >/dev/null 2>&1 || true
	@for service in Accessibility AppleEvents SystemPolicyAllFiles; do \
		tccutil reset $$service "$(BUNDLE_ID).debug.agent" >/dev/null 2>&1 || true; \
	done
	@[ ! -d "$(DEBUG_AGENT)" ] || $(LSREGISTER) -u "$(DEBUG_AGENT)" 2>/dev/null || true
	@[ ! -d "$(PRODUCTS)/Debug/TimeTrackingAgent.app" ] || $(LSREGISTER) -u "$(PRODUCTS)/Debug/TimeTrackingAgent.app" 2>/dev/null || true
	@echo "The Debug agent is unregistered."

logs: ## Stream the unified log of the installed Mac app, agent, and tools
	log stream --style compact --level info \
		--predicate 'subsystem BEGINSWITH "$(BUNDLE_ID)" AND NOT subsystem CONTAINS ".debug"'

sim-logs: ## Stream the unified log of the simulator app
	xcrun simctl spawn "$(SIM_IPHONE)" log stream --style compact --level info \
		--predicate 'subsystem BEGINSWITH "$(BUNDLE_ID).debug"'

screenshots: ## Simulator screenshots to build.noindex/screenshots/
	@mkdir -p "$(DERIVED)/screenshots"
	@stamp=$$(date +%Y%m%d-%H%M%S); for name in "$(SIM_IPHONE)" "$(SIM_IPAD)"; do \
		file="$(DERIVED)/screenshots/$${name// /-}-$$stamp.png"; \
		xcrun simctl io "$$name" screenshot "$$file" >/dev/null 2>&1 && echo "$$file" || echo "$$name is not booted" >&2; \
	done

##@ Use

install: build-mac ## Install into /Applications; link the tools and completions into PREFIX
	scripts/install.sh install "$(MAC_RELEASE_APP)" "$(BUNDLE_ID)" "$(APP_NAME)" "$(PREFIX)" "$(ALIAS)"

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

devices: ## List known devices
	@xcrun devicectl list devices
	@echo; echo "Configured in local.mk:"; $(foreach v,$(filter DEVICE_%,$(.VARIABLES)),echo "  $(v:DEVICE_%=%) = $($(v))";) true

console: ## Relaunch on DEVICE_<D> and stream its console
	@[ -n "$(DEVICE_$(D))" ] || { echo "set DEVICE_$(D) in local.mk" >&2; exit 1; }
	xcrun devicectl device process launch --console --terminate-existing --device "$(DEVICE_$(D))" "$(BUNDLE_ID)" $(ARGS)

##@ Test

unit-test: secrets ## (3 min) swift test, then TimeTrackingTests, TimeTrackingAgentTests, TimeTrackingCLITests
	swift test --package-path Packages/TimeTrackingCore
	$(require_team)
	$(XCB) test -scheme TimeTracking $(MAC_DEST) -only-testing:TimeTrackingTests -only-testing:TimeTrackingCLITests $(SIGN)
	$(XCB) test -scheme TimeTrackingAgent $(MAC_DEST) -only-testing:TimeTrackingAgentTests $(SIGN)

agent-test: secrets ## (1 min) TimeTrackingAgentTests
	$(require_team)
	$(XCB) test -scheme TimeTrackingAgent $(MAC_DEST) -only-testing:TimeTrackingAgentTests $(SIGN)

ui-test: secrets ## (8 min) Mac UI tests, iOS UI tests on both simulators
	$(require_team)
	@$(MAKE) --no-print-directory sim-create
	$(XCB) test -scheme TimeTracking $(MAC_DEST) -only-testing:TimeTrackingUITests $(SIGN)
	$(XCB) test -scheme TimeTrackingiOS $(IPHONE_DEST) $(IPAD_DEST) -only-testing:TimeTrackingiOSUITests $(SIGN)

test: unit-test ## (15 min) unit-test, slow library tests, TimeTrackingiOSTests on the iPhone simulator, ui-test
	@# Timing targets hold for optimized builds, one test at a time (spec_data_and_sync.md §7.5).
	TIMETRACKING_TEST_SLOW=1 swift test --package-path Packages/TimeTrackingCore -c release -Xswiftc -enable-testing --no-parallel --filter PerformanceTests
	@$(MAKE) --no-print-directory sim-create
	$(XCB) test -scheme TimeTrackingiOS $(IPHONE_DEST) -only-testing:TimeTrackingiOSTests $(SIGN)
	@$(MAKE) --no-print-directory ui-test

test-sync: secrets ## (3 min) CloudKit integration tests against iCloud.<BUNDLE_ID>.debug; never part of test
	$(require_team)
	TEST_RUNNER_TIMETRACKING_TEST_SYNC=1 $(XCB) test -scheme TimeTracking $(MAC_DEST) -only-testing:TimeTrackingTests $(SIGN)

##@ Check

lint: ## SwiftFormat --lint and SwiftLint --strict from the package checkouts; no build
	@scripts/lint.sh "$(DERIVED)"

check-behaviors: ## Every testable behavior has a test (ONLY=ARCH,DATA limits the failures)
	@scripts/check_behaviors.sh $(if $(ONLY),--only $(ONLY))

check-private: ## Refuse tracked files with personal data
	@.githooks/check-private tree

check: lint check-behaviors check-private ## lint, check-behaviors, check-private

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
		find "$(DERIVED)" -mindepth 1 -maxdepth 1 ! -name Build ! -name SourcePackages ! -name LintTools ! -name screenshots -exec rm -rf {} +; \
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
