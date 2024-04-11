SCHEME=Signal

.PHONY: dependencies
dependencies: pod-setup fetch-ringrtc

.PHONY: pod-setup
pod-setup:
	git submodule foreach --recursive "git clean -xfd"
	git submodule foreach --recursive "git reset --hard"
	./Scripts/setup_private_pods
	git submodule update --init --progress

.PHONY: fetch-ringrtc
fetch-ringrtc:
	$(CURDIR)/Pods/SignalRingRTC/bin/set-up-for-cocoapods

.PHONY: test
test: dependencies
	bundle exec fastlane scan --scheme ${SCHEME}

.PHONY: release
release:
	@echo This command has been deprecated by Xcode Cloud.
