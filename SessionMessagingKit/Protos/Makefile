
PROTOC=protoc \
		--proto_path='./'
WRAPPER_SCRIPT=../../Scripts/ProtoWrappers.py \
		--proto-dir='./' --verbose

all: session_protos websocket_protos

session_protos: SessionProtos.proto
	$(PROTOC) --swift_out=./Generated \SessionProtos.proto
	$(WRAPPER_SCRIPT) --dst-dir=./Generated \
		--wrapper-prefix=SNProto --proto-prefix=SessionProtos --proto-file=SessionProtos.proto


websocket_protos: WebSocketResources.proto
	$(PROTOC) --swift_out=./Generated \WebSocketResources.proto
	$(WRAPPER_SCRIPT) --dst-dir=./Generated \
		--wrapper-prefix=WebSocketProto --proto-prefix=WebSocketProtos --proto-file=WebSocketResources.proto
