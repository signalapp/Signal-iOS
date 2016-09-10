# Assumes you've installed protobug-objc
# see: https://github.com/alexeyxo/protobuf-objc

all: signal_service_proto provisioning_protos

signal_service_proto:
	protoc \
		--plugin=/usr/local/bin/proto-gen-objc \
		--proto_path="${HOME}/src/WhisperSystems/protobuf-objc/src/compiler/" \
		--proto_path="${HOME}/src/WhisperSystems/protobuf-objc/src/compiler/google/protobuf/" \
		--proto_path='./' \
		--objc_out=../src/Messages/ \
		OWSSignalServiceProtos.proto

provisioning_protos:
	protoc \
		--plugin=/usr/local/bin/proto-gen-objc \
		--proto_path="${HOME}/src/WhisperSystems/protobuf-objc/src/compiler/" \
		--proto_path="${HOME}/src/WhisperSystems/protobuf-objc/src/compiler/google/protobuf/" \
		--proto_path='./' \
		--objc_out=../src/Devices/ \
		OWSProvisioningProtos.proto

