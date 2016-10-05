# Make sure we're failing even though we pipe to xcpretty
SHELL=/bin/bash -o pipefail

BUILD_PLATFORM=iOS Simulator,name=iPhone 6,OS=10.0
WORKING_DIR = ./

default: test

build_signal:
	cd $(WORKING_DIR) && \
		pod install && \
		xcodebuild -workspace Signal.xcworkspace -scheme Signal \
		-sdk iphonesimulator \
		build | xcpretty

retest:
	cd $(WORKING_DIR) && \
	xcodebuild -workspace Signal.xcworkspace -scheme Signal \
		-sdk iphonesimulator \
		-destination 'platform=${BUILD_PLATFORM}' \
		test | xcpretty

test: build_signal retest

