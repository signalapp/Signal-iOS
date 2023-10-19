#
# Copyright 2023 Signal Messenger, LLC
# SPDX-License-Identifier: AGPL-3.0-only
#

# See README.md in this dir for prerequisite setup.

PROTOC=protoc \
		--proto_path='./'
WRAPPER_SCRIPT=../../Scripts/ProtoWrappers.py \
		--proto-dir='./' --verbose

all: signal_service_protos provisioning_protos fingerprint_protos websocket_protos signal_ios_protos key_backup_protos storage_service_protos groups_protos device_transfer_protos session_record_protos cdsi_protos svr_protos backup_protos

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

key_backup_protos: KeyBackup.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		KeyBackup.proto
	$(WRAPPER_SCRIPT) --dst-dir=../src/Protos/Generated \
		--wrapper-prefix=KeyBackupProto --proto-prefix=KeyBackupProtos --proto-file=KeyBackup.proto

storage_service_protos: StorageService.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		StorageService.proto
	$(WRAPPER_SCRIPT) --dst-dir=../src/Protos/Generated \
		--wrapper-prefix=StorageServiceProto --proto-prefix=StorageServiceProtos --proto-file=StorageService.proto

backup_protos: Backup.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		Backup.proto
	$(WRAPPER_SCRIPT) --dst-dir=../src/Protos/Generated \
		--wrapper-prefix=BackupProto --proto-prefix=BackupProtos --proto-file=Backup.proto


# TODO: Copy schema from zkgroup repository.
# TODO: Insert the following lines into the schema:
#
# // iOS - package name determines class prefix
# package GroupsProtos;
#
groups_protos: Groups.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		Groups.proto
	$(WRAPPER_SCRIPT) --dst-dir=../src/Protos/Generated \
		--wrapper-prefix=GroupsProto --proto-prefix=GroupsProtos --proto-file=Groups.proto

device_transfer_protos: DeviceTransfer.proto
	$(PROTOC) --swift_out=../src/Protos/Generated \
		DeviceTransfer.proto
	$(WRAPPER_SCRIPT) --dst-dir=../src/Protos/Generated \
		--wrapper-prefix=DeviceTransferProto --proto-prefix=DeviceTransferProtos --proto-file=DeviceTransfer.proto

session_record_protos: SessionRecord.proto
	$(PROTOC) --swift_out=../src/Protos/Generated SessionRecord.proto

cdsi_protos: cdsi.proto
	$(PROTOC) --swift_out=../src/Protos/Generated cdsi.proto

svr_protos: svr2.proto
	$(PROTOC) --swift_out=../src/Protos/Generated svr2.proto
