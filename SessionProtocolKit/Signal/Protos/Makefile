PROTOC=protoc \
		--proto_path='./'
WRAPPER_SCRIPT=../../../../session-ios/Scripts/ProtoWrappers.py \
		--proto-dir='./' --verbose --add-log-tag

all: webrtc_data_proto unidentified_delivery_protos

webrtc_data_proto: WhisperTextProtocol.proto
	$(PROTOC) --swift_out=. \
		WhisperTextProtocol.proto
	$(WRAPPER_SCRIPT) --dst-dir=. \
		--wrapper-prefix=SPKProto --proto-prefix=SPKProtos --proto-file=WhisperTextProtocol.proto

unidentified_delivery_protos: OWSUnidentifiedDelivery.proto
	$(PROTOC) --swift_out=../SignalMetadataKit/src/Generated \
		OWSUnidentifiedDelivery.proto
	$(WRAPPER_SCRIPT) --dst-dir=../SignalMetadataKit/src/Generated \
		--wrapper-prefix=SMKProto --proto-prefix=SMKProtos --proto-file=OWSUnidentifiedDelivery.proto
