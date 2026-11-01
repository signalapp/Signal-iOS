SCHEME=Signal
PODS=Pods

.PHONY: dependencies
dependencies: pod-setup fetch-ringrtc

.PHONY: pod-setup
pod-setup:
	git -C ${PODS} clean -xfd
	git -C ${PODS} reset --hard
	./Scripts/setup_private_pods
	git submodule update --init --progress ${PODS}

.PHONY: fetch-ringrtc
fetch-ringrtc:
	$(CURDIR)/Pods/SignalRingRTC/bin/set-up-for-cocoapods
