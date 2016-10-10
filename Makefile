# Make sure we're failing even though we pipe to xcpretty
SHELL=/bin/bash -o pipefail -o errexit

BUILD_DESTINATION = platform=iOS Simulator,name=iPhone 6,OS=9.3
WORKING_DIR = ./
SCHEME = Signal
XCODE_BUILD = xcrun xcodebuild -workspace $(SCHEME).xcworkspace -scheme $(SCHEME) -sdk iphonesimulator

.PHONY: build test retest clean

default: test

test: pod_install retest

pod_install:
	cd $(WORKING_DIR) && \
		pod install

build: pod_install
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) build | xcpretty

retest:
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) \
			-destination '${BUILD_DESTINATION}' \
			build test | xcpretty

clean:
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) \
			clean | xcpretty

