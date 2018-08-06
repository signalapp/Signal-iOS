PROTOC=protoc \
		--proto_path='./'
WRAPPER_SCRIPT=../Scripts/ProtoWrappers.py \
		--proto-dir='./' --verbose

all: webrtc_data_proto

webrtc_data_proto: OWSWebRTCDataProtos.proto
	$(PROTOC) --swift_out=../Signal/src/Generated \
		OWSWebRTCDataProtos.proto
	$(WRAPPER_SCRIPT) --dst-dir=../Signal/src/Generated \
		--wrapper-prefix=WebRTCProto --proto-prefix=WebRTCProtos --proto-file=OWSWebRTCDataProtos.proto
