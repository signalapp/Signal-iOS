# See README.md in this dir for prerequisite setup.
	
PROTOC=protoc \
		--plugin=/usr/local/bin/protoc-gen-objc \
		--proto_path="${HOME}/code/workspace/ows/protobuf-objc/src/compiler/" \
		--proto_path="${HOME}/code/workspace/ows/protobuf-objc/src/compiler/google/protobuf/" \
		--proto_path='./'

all: signal_service_proto provisioning_protos fingerprint_protos

signal_service_proto: OWSSignalServiceProtos.proto
	$(PROTOC) --objc_out=../src/Messages/ \
		OWSSignalServiceProtos.proto

provisioning_protos: OWSProvisioningProtos.proto
	$(PROTOC) --objc_out=../src/Devices/ \
		OWSProvisioningProtos.proto

fingerprint_protos: OWSFingerprintProtos.proto
	$(PROTOC) --objc_out=../src/Security/ \
		OWSFingerprintProtos.proto

