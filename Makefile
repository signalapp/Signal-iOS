# Make sure we're failing even though we pipe to xcpretty
SHELL=/bin/bash -o pipefail -o errexit

WORKING_DIR = ./
THIRD_PARTY_DIR = $(WORKING_DIR)/ThirdParty
SCHEME = Signal
XCODE_BUILD = xcrun xcodebuild -workspace $(SCHEME).xcworkspace -scheme $(SCHEME) -sdk iphonesimulator

.PHONY: build test retest clean dependencies

default: test

ci: dependencies test

update_dependencies:
	bundle exec pod update

dependencies:
	cd $(WORKING_DIR) && \
		git submodule update --init
		cd $(THIRD_PARTY_DIR)

build: dependencies
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) build | xcpretty

test:
	bundle exec fastlane scan

clean: clean_carthage
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) clean | xcpretty
