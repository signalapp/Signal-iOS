# See README.md in this dir for prerequisite setup.

PROTOC=protoc \
		--proto_path='./'
WRAPPER_SCRIPT=../../Scripts/ProtoWrappers.py \
		--proto-dir='./' --verbose

all: signal_service_protos provisioning_protos fingerprint_protos websocket_protos signal_ios_protos

signal_service_protos: SignalService.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		SignalService.proto
	$(WRAPPER_SCRIPT) --dst-dir=../src/Protos/Generated \
		--wrapper-prefix=SSKProto --proto-prefix=SignalServiceProtos --proto-file=SignalService.proto

provisioning_protos: Provisioning.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		Provisioning.proto
	$(WRAPPER_SCRIPT) --dst-dir=../src/Protos/Generated \
		--wrapper-prefix=ProvisioningProto --proto-prefix=ProvisioningProtos --proto-file=Provisioning.proto

fingerprint_protos: Fingerprint.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		Fingerprint.proto
	$(WRAPPER_SCRIPT) --dst-dir=../src/Protos/Generated \
		--wrapper-prefix=FingerprintProto --proto-prefix=FingerprintProtos --proto-file=Fingerprint.proto

websocket_protos: WebSocketResources.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		WebSocketResources.proto
	$(WRAPPER_SCRIPT) --dst-dir=../src/Protos/Generated \
		--wrapper-prefix=WebSocketProto --proto-prefix=WebSocketProtos --proto-file=WebSocketResources.proto

signal_ios_protos: SignalIOS.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		SignalIOS.proto
	$(WRAPPER_SCRIPT) --dst-dir=../src/Protos/Generated \
		--wrapper-prefix=SignalIOSProto --proto-prefix=IOSProtos --proto-file=SignalIOS.proto
