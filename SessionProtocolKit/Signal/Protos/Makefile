PROTOC=protoc \
		--proto_path='./'
WRAPPER_SCRIPT=../../../../session-ios/Scripts/ProtoWrappers.py \
		--proto-dir='./' --verbose --add-log-tag

all: webrtc_data_proto

webrtc_data_proto: WhisperTextProtocol.proto
	$(PROTOC) --swift_out=. \
		WhisperTextProtocol.proto
	$(WRAPPER_SCRIPT) --dst-dir=. \
		--wrapper-prefix=SPKProto --proto-prefix=SPKProtos --proto-file=WhisperTextProtocol.proto
