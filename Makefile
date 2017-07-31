# Make sure we're failing even though we pipe to xcpretty
SHELL=/bin/bash -o pipefail -o errexit

WORKING_DIR = ./
SCHEME = Signal

.PHONY: build test retest clean dependencies

default: test

ci: dependencies test
	cd SignalServiceKit && make ci

update_dependencies:
	bundle exec pod update
	carthage update --platform iOS

dependencies:
	cd $(WORKING_DIR) && \
		git submodule update --init
		bundle exec pod install
		carthage build --platform iOS

build: dependencies
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) build | xcpretty

test:
	bundle exec fastlane scan

clean:
	cd $(WORKING_DIR) && \
		rm -fr Carthage/Build && \
		$(XCODE_BUILD) \
			clean | xcpretty

