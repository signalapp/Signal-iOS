# Make sure we're failing even though we pipe to xcpretty
SHELL=/bin/bash -o pipefail -o errexit

WORKING_DIR = Example/TSKitiOSTestApp
SCHEME = TSKitiOSTestApp

DEVICE_UUID:=$(shell xcrun instruments -s | grep -o "iPhone 6 (9.3) \[.*\]" | grep -o "\[.*\]" | sed "s/^\[\(.*\)\]$$/\1/")
BUILD_DESTINATION = platform=iOS Simulator,id=${DEVICE_UUID}
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

retest: optional_early_start_simulator
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) \
			-destination '${BUILD_DESTINATION}' \
			test | xcpretty

clean:
	cd $(WORKING_DIR) && \
		$(XCODE_BUILD) \
			clean | xcpretty

optional_early_start_simulator:
ifdef EARLY_START_SIMULATOR
		echo "Waiting for simulator to start to help with testing timeouts" &&\
		xcrun instruments -w '${DEVICE_UUID}' || true # xcrun can return irrelevant non-zeroes.
else
		echo "Not waiting for simulator."
endif

