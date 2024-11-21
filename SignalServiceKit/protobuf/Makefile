#
# Copyright 2023 Signal Messenger, LLC
# SPDX-License-Identifier: AGPL-3.0-only
#

# See README.md in this dir for prerequisite setup.

PROTOC=protoc \
		--proto_path='./'
WRAPPER_SCRIPT=../../Scripts/protos/ProtoWrappers.py \
		--proto-dir='./' --verbose

all: signal_service_protos provisioning_protos fingerprint_protos websocket_protos signal_ios_protos storage_service_protos groups_protos device_transfer_protos session_record_protos svr_protos mobilecoin_protos

signal_service_protos: SignalService.proto
	$(PROTOC) --swift_out=../Protos/Generated \
		SignalService.proto
	$(WRAPPER_SCRIPT) --dst-dir=../Protos/Generated \
		--wrapper-prefix=SSKProto --proto-prefix=SignalServiceProtos --proto-file=SignalService.proto

provisioning_protos: Provisioning.proto
	$(PROTOC) --swift_out=../Protos/Generated \
		Provisioning.proto
	$(WRAPPER_SCRIPT) --dst-dir=../Protos/Generated \
		--wrapper-prefix=ProvisioningProto --proto-prefix=ProvisioningProtos --proto-file=Provisioning.proto

fingerprint_protos: Fingerprint.proto
	$(PROTOC) --swift_out=../Protos/Generated \
		Fingerprint.proto
	$(WRAPPER_SCRIPT) --dst-dir=../Protos/Generated \
		--wrapper-prefix=FingerprintProto --proto-prefix=FingerprintProtos --proto-file=Fingerprint.proto

websocket_protos: WebSocketResources.proto
	$(PROTOC) --swift_out=../Protos/Generated \
		WebSocketResources.proto
	$(WRAPPER_SCRIPT) --dst-dir=../Protos/Generated \
		--wrapper-prefix=WebSocketProto --proto-prefix=WebSocketProtos --proto-file=WebSocketResources.proto

signal_ios_protos: SignalIOS.proto
	$(PROTOC) --swift_out=../Protos/Generated \
		SignalIOS.proto
	$(WRAPPER_SCRIPT) --dst-dir=../Protos/Generated \
		--wrapper-prefix=SignalIOSProto --proto-prefix=IOSProtos --proto-file=SignalIOS.proto

storage_service_protos: StorageService.proto
	$(PROTOC) --swift_out=../Protos/Generated \
		StorageService.proto
	$(WRAPPER_SCRIPT) --dst-dir=../Protos/Generated \
		--wrapper-prefix=StorageServiceProto --proto-prefix=StorageServiceProtos --proto-file=StorageService.proto


# TODO: Copy schema from zkgroup repository.
# TODO: Insert the following lines into the schema:
#
# // iOS - package name determines class prefix
# package GroupsProtos;
#
groups_protos: Groups.proto
	$(PROTOC) --swift_out=../Protos/Generated \
		Groups.proto
	$(WRAPPER_SCRIPT) --dst-dir=../Protos/Generated \
		--wrapper-prefix=GroupsProto --proto-prefix=GroupsProtos --proto-file=Groups.proto

device_transfer_protos: DeviceTransfer.proto
	$(PROTOC) --swift_out=../Protos/Generated \
		DeviceTransfer.proto
	$(WRAPPER_SCRIPT) --dst-dir=../Protos/Generated \
		--wrapper-prefix=DeviceTransferProto --proto-prefix=DeviceTransferProtos --proto-file=DeviceTransfer.proto

session_record_protos: SessionRecord.proto
	$(PROTOC) --swift_out=../Protos/Generated SessionRecord.proto

svr_protos: svr2.proto
	$(PROTOC) --swift_out=../Protos/Generated svr2.proto

mobilecoin_protos: MobileCoinExternal.proto
	$(PROTOC) --swift_out=../Protos/Generated MobileCoinExternal.proto
