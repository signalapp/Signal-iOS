# Make sure we're failing even though we pipe to xcpretty
SHELL=/bin/bash -o pipefail -o errexit

WORKING_DIR = Example/TSKitiOSTestApp
SCHEME = TSKitiOSTestApp

XCODE_BUILD = xcrun xcodebuild -workspace $(SCHEME).xcworkspace -scheme $(SCHEME) -sdk iphonesimulator

.PHONY: build test retest clean

default: test
ci: dependencies test

dependencies:
	cd $(WORKING_DIR) && \
		bundle exec pod install

build: pod_install
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) build | xcpretty

test:
	bundle exec fastlane scan

clean:
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) \
			clean | xcpretty

