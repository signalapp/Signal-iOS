# Assumes you've installed protobug-objc
# see: https://github.com/alexeyxo/protobuf-objc
signal_service_proto:
	protoc --objc_out=../src/Messages/ \
		--plugin=/usr/local/bin/proto-gen-objc \
		--proto_path="${HOME}/src/WhisperSystems/protobuf-objc/src/compiler/" \
		--proto_path="${HOME}/src/WhisperSystems/protobuf-objc/src/compiler/google/protobuf/" \
		--proto_path='./' \
		OWSSignalServiceProtos.proto
