
PROTOC=protoc \
		--proto_path='./'
WRAPPER_SCRIPT=../../Scripts/ProtoWrappers.py \
		--proto-dir='./' --verbose

all: session_protos

session_protos: SessionProtos.proto
	$(PROTOC) --swift_out=./Generated \SessionProtos.proto
	$(WRAPPER_SCRIPT) --dst-dir=./Generated \
		--wrapper-prefix=SNProto --proto-prefix=SessionProtos --proto-file=SessionProtos.proto
