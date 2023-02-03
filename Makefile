APP_IDENTIFIER=org.whispersystems.signal
SCHEME=Signal

dependencies:
	git submodule foreach --recursive "git clean -xfd" 
	git submodule foreach --recursive "git reset --hard" 
	./Scripts/setup_private_pods
	git submodule update --init --progress
	$(CURDIR)/Pods/SignalRingRTC/bin/set-up-for-cocoapods

test: dependencies
	bundle exec fastlane scan --scheme ${SCHEME}

release: dependencies
	SCHEME=${SCHEME} APP_IDENTIFIER=${APP_IDENTIFIER} bundle exec fastlane release nightly:${NIGHTLY}
