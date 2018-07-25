# See README.md in this dir for prerequisite setup.

PROTOC=protoc \
		--proto_path='./'

all: signal_service_protos provisioning_protos fingerprint_protos websocket_protos signal_ios_protos

signal_service_protos: SignalService.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		SignalService.proto

provisioning_protos: Provisioning.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		Provisioning.proto

fingerprint_protos: Fingerprint.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		Fingerprint.proto

websocket_protos: WebSocketResources.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		WebSocketResources.proto

signal_ios_protos: SignalIOS.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		SignalIOS.proto
