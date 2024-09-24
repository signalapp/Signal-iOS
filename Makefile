SCHEME=Signal
PODS=Pods
BACKUP_TESTS=SignalServiceKit/tests/MessageBackup/Signal-Message-Backup-Tests

.PHONY: dependencies
dependencies: pod-setup backup-tests-setup fetch-ringrtc

.PHONY: pod-setup
pod-setup:
	git -C ${PODS} clean -xfd
	git -C ${PODS} reset --hard
	./Scripts/setup_private_pods
	git submodule update --init --progress ${PODS}

.PHONY: backup-tests-setup
backup-tests-setup:
	git submodule update --init --progress ${BACKUP_TESTS}

.PHONY: fetch-ringrtc
fetch-ringrtc:
	$(CURDIR)/Pods/SignalRingRTC/bin/set-up-for-cocoapods

.PHONY: test
test: dependencies
	bundle exec fastlane scan --scheme ${SCHEME}
