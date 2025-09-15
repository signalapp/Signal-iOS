#
# Copyright 2023 Signal Messenger, LLC
# SPDX-License-Identifier: AGPL-3.0-only
#

# See README.md in Specifications for prerequisite setup.

PROTOC=protoc --proto_path=Specifications
WRAPPER_SCRIPT=../../Scripts/protos/ProtoWrappers.py --proto-dir=Specifications --verbose

all: registration_protos signal_service_protos provisioning_protos fingerprint_protos websocket_protos signal_ios_protos storage_service_protos groups_protos device_transfer_protos session_record_protos svr_protos mobilecoin_protos backup_protos

signal_service_protos: Specifications/SignalService.proto
	$(PROTOC) --swift_out=Generated SignalService.proto
	$(WRAPPER_SCRIPT) --dst-dir=Generated --wrapper-prefix=SSKProto --proto-prefix=SignalServiceProtos --proto-file=SignalService.proto

provisioning_protos: Specifications/Provisioning.proto
	$(PROTOC) --swift_out=Generated Provisioning.proto
	$(WRAPPER_SCRIPT) --dst-dir=Generated --wrapper-prefix=ProvisioningProto --proto-prefix=ProvisioningProtos --proto-file=Provisioning.proto

fingerprint_protos: Specifications/Fingerprint.proto
	$(PROTOC) --swift_out=Generated Fingerprint.proto
	$(WRAPPER_SCRIPT) --dst-dir=Generated --wrapper-prefix=FingerprintProto --proto-prefix=FingerprintProtos --proto-file=Fingerprint.proto

websocket_protos: Specifications/WebSocketResources.proto
	$(PROTOC) --swift_out=Generated WebSocketResources.proto
	$(WRAPPER_SCRIPT) --dst-dir=Generated --wrapper-prefix=WebSocketProto --proto-prefix=WebSocketProtos --proto-file=WebSocketResources.proto

signal_ios_protos: Specifications/SignalIOS.proto
	$(PROTOC) --swift_out=Generated SignalIOS.proto
	$(WRAPPER_SCRIPT) --dst-dir=Generated --wrapper-prefix=SignalIOSProto --proto-prefix=IOSProtos --proto-file=SignalIOS.proto

storage_service_protos: Specifications/StorageService.proto
	$(PROTOC) --swift_out=Generated StorageService.proto
	$(WRAPPER_SCRIPT) --dst-dir=Generated --wrapper-prefix=StorageServiceProto --proto-prefix=StorageServiceProtos --proto-file=StorageService.proto

groups_protos: Specifications/Groups.proto
	$(PROTOC) --swift_out=Generated Groups.proto
	$(WRAPPER_SCRIPT) --dst-dir=Generated --wrapper-prefix=GroupsProto --proto-prefix=GroupsProtos --proto-file=Groups.proto

device_transfer_protos: Specifications/DeviceTransfer.proto
	$(PROTOC) --swift_out=Generated DeviceTransfer.proto
	$(WRAPPER_SCRIPT) --dst-dir=Generated --wrapper-prefix=DeviceTransferProto --proto-prefix=DeviceTransferProtos --proto-file=DeviceTransfer.proto

session_record_protos: Specifications/SessionRecord.proto
	$(PROTOC) --swift_out=Generated SessionRecord.proto

svr_protos: Specifications/svr2.proto
	$(PROTOC) --swift_out=Generated svr2.proto

mobilecoin_protos: Specifications/MobileCoinExternal.proto
	$(PROTOC) --swift_out=Generated MobileCoinExternal.proto

registration_protos: Specifications/Registration.proto
	$(PROTOC) --swift_out=Generated Registration.proto

backup_protos: Backups/Backup.proto
	$(PROTOC) --swift_out=Backups --proto_path=Backups --swift_opt=Visibility=public --swift_opt=UseAccessLevelOnImports=true Backup.proto
