# Assumes you've installed protobuf-objc
# see: https://github.com/alexeyxo/protobuf-objc

PROTOC=protoc \
		--plugin=/usr/local/bin/proto-gen-objc \
		--proto_path="${HOME}/src/Relay/protobuf-objc/src/compiler/" \
		--proto_path="${HOME}/src/Relay/protobuf-objc/src/compiler/google/protobuf/" \
		--proto_path='./'

all: webrtc_data_proto

webrtc_data_proto: OWSWebRTCDataProtos.proto
	$(PROTOC) --objc_out=../Relay/src/call/ \
		OWSWebRTCDataProtos.proto

