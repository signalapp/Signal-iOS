# Make sure we're failing even though we pipe to xcpretty
SHELL := /bin/bash -o pipefail -o errexit
WORKING_DIR := ./
SCHEME = Relay
XCODE_BUILD := xcrun xcodebuild -workspace $(SCHEME).xcworkspace -scheme $(SCHEME) -sdk iphonesimulator

.PHONY: build test retest clean dependencies ci

default: test

ci: dependencies test
	$(XCODE_BUILD) build

update_dependencies:
	bundle exec pod update

dependencies: update_dependencies
	bundle exec pod install

build: dependencies
	$(XCODE_BUILD) build | xcpretty

test:
	bundle exec fastlane scan
	cd SignalServiceKit && make test

clean:
	$(XCODE_BUILD) clean | xcpretty
