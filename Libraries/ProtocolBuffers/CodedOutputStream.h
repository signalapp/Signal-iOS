// Copyright 2008 Cyrus Najmabadi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@class PBUnknownFieldSet;
@protocol PBMessage;

/**
 * Encodes and writes protocol message fields.
 *
 * <p>This class contains two kinds of methods:  methods that write specific
 * protocol message constructs and field types (e.g. {@link #writeTag} and
 * {@link #writeInt32}) and methods that write low-level values (e.g.
 * {@link #writeRawVarint32} and {@link #writeRawBytes}).  If you are
 * writing encoded protocol messages, you should use the former methods, but if
 * you are writing some other format of your own design, use the latter.
 *
 * <p>This class is totally unsynchronized.
 *
 * @author Cyrus Najmabadi
 */
@interface PBCodedOutputStream : NSObject {
    NSMutableData* buffer;
    int32_t position;
    NSOutputStream* output;
}

+ (PBCodedOutputStream*) streamWithData:(NSMutableData*) data;
+ (PBCodedOutputStream*) streamWithOutputStream:(NSOutputStream*) output;
+ (PBCodedOutputStream*) streamWithOutputStream:(NSOutputStream*) output bufferSize:(int32_t) bufferSize;


/**
 * Encode a ZigZag-encoded 32-bit value.  ZigZag encodes signed integers
 * into values that can be efficiently encoded with varint.  (Otherwise,
 * negative values must be sign-extended to 64 bits to be varint encoded,
 * thus always taking 10 bytes on the wire.)
 *
 * @param n A signed 32-bit integer.
 * @return An unsigned 32-bit integer, stored in a signed int.
 */
int32_t encodeZigZag32(int32_t n);

/**
 * Encode a ZigZag-encoded 64-bit value.  ZigZag encodes signed integers
 * into values that can be efficiently encoded with varint.  (Otherwise,
 * negative values must be sign-extended to 64 bits to be varint encoded,
 * thus always taking 10 bytes on the wire.)
 *
 * @param n A signed 64-bit integer.
 * @return An unsigned 64-bit integer, stored in a signed int.
 */
int64_t encodeZigZag64(int64_t n);

int32_t computeDoubleSize(int32_t fieldNumber, Float64 value);
int32_t computeFloatSize(int32_t fieldNumber, Float32 value);
int32_t computeUInt64Size(int32_t fieldNumber, int64_t value);
int32_t computeInt64Size(int32_t fieldNumber, int64_t value);
int32_t computeInt32Size(int32_t fieldNumber, int32_t value);
int32_t computeFixed64Size(int32_t fieldNumber, int64_t value);
int32_t computeFixed32Size(int32_t fieldNumber, int32_t value);
int32_t computeBoolSize(int32_t fieldNumber, BOOL value);
int32_t computeStringSize(int32_t fieldNumber, NSString* value);
int32_t computeGroupSize(int32_t fieldNumber, id<PBMessage> value);
int32_t computeUnknownGroupSize(int32_t fieldNumber, PBUnknownFieldSet* value);
int32_t computeMessageSize(int32_t fieldNumber, id<PBMessage> value);
int32_t computeDataSize(int32_t fieldNumber, NSData* value);
int32_t computeUInt32Size(int32_t fieldNumber, int32_t value);
int32_t computeSFixed32Size(int32_t fieldNumber, int32_t value);
int32_t computeSFixed64Size(int32_t fieldNumber, int64_t value);
int32_t computeSInt32Size(int32_t fieldNumber, int32_t value);
int32_t computeSInt64Size(int32_t fieldNumber, int64_t value);
int32_t computeTagSize(int32_t fieldNumber);

int32_t computeDoubleSizeNoTag(Float64 value);
int32_t computeFloatSizeNoTag(Float32 value);
int32_t computeUInt64SizeNoTag(int64_t value);
int32_t computeInt64SizeNoTag(int64_t value);
int32_t computeInt32SizeNoTag(int32_t value);
int32_t computeFixed64SizeNoTag(int64_t value);
int32_t computeFixed32SizeNoTag(int32_t value);
int32_t computeBoolSizeNoTag(BOOL value);
int32_t computeStringSizeNoTag(NSString* value);
int32_t computeGroupSizeNoTag(id<PBMessage> value);
int32_t computeUnknownGroupSizeNoTag(PBUnknownFieldSet* value);
int32_t computeMessageSizeNoTag(id<PBMessage> value);
int32_t computeDataSizeNoTag(NSData* value);
int32_t computeUInt32SizeNoTag(int32_t value);
int32_t computeEnumSizeNoTag(int32_t value);
int32_t computeSFixed32SizeNoTag(int32_t value);
int32_t computeSFixed64SizeNoTag(int64_t value);
int32_t computeSInt32SizeNoTag(int32_t value);
int32_t computeSInt64SizeNoTag(int64_t value);

/**
 * Compute the number of bytes that would be needed to encode a varint.
 * {@code value} is treated as unsigned, so it won't be sign-extended if
 * negative.
 */
int32_t computeRawVarint32Size(int32_t value);
int32_t computeRawVarint64Size(int64_t value);

/**
 * Compute the number of bytes that would be needed to encode a
 * MessageSet extension to the stream.  For historical reasons,
 * the wire format differs from normal fields.
 */
int32_t computeMessageSetExtensionSize(int32_t fieldNumber, id<PBMessage> value);

/**
 * Compute the number of bytes that would be needed to encode an
 * unparsed MessageSet extension field to the stream.  For
 * historical reasons, the wire format differs from normal fields.
 */
int32_t computeRawMessageSetExtensionSize(int32_t fieldNumber, NSData* value);

/**
 * Compute the number of bytes that would be needed to encode an
 * enum field, including tag.  Caller is responsible for converting the
 * enum value to its numeric value.
 */
int32_t computeEnumSize(int32_t fieldNumber, int32_t value);

/**
 * Flushes the stream and forces any buffered bytes to be written.  This
 * does not flush the underlying NSOutputStream.
 */
- (void) flush;

- (void) writeRawByte:(uint8_t) value;

- (void) writeTag:(int32_t) fieldNumber format:(int32_t) format;

/**
 * Encode and write a varint.  {@code value} is treated as
 * unsigned, so it won't be sign-extended if negative.
 */
- (void) writeRawVarint32:(int32_t) value;
- (void) writeRawVarint64:(int64_t) value;

- (void) writeRawLittleEndian32:(int32_t) value;
- (void) writeRawLittleEndian64:(int64_t) value;

- (void) writeRawData:(NSData*) data;
- (void) writeRawData:(NSData*) data offset:(int32_t) offset length:(int32_t) length;

- (void) writeData:(int32_t) fieldNumber value:(NSData*) value;

- (void) writeDouble:(int32_t) fieldNumber value:(Float64) value;
- (void) writeFloat:(int32_t) fieldNumber value:(Float32) value;
- (void) writeUInt64:(int32_t) fieldNumber value:(int64_t) value;
- (void) writeInt64:(int32_t) fieldNumber value:(int64_t) value;
- (void) writeInt32:(int32_t) fieldNumber value:(int32_t) value;
- (void) writeFixed64:(int32_t) fieldNumber value:(int64_t) value;
- (void) writeFixed32:(int32_t) fieldNumber value:(int32_t) value;
- (void) writeBool:(int32_t) fieldNumber value:(BOOL) value;
- (void) writeString:(int32_t) fieldNumber value:(NSString*) value;
- (void) writeGroup:(int32_t) fieldNumber value:(id<PBMessage>) value;
- (void) writeUnknownGroup:(int32_t) fieldNumber value:(PBUnknownFieldSet*) value;
- (void) writeMessage:(int32_t) fieldNumber value:(id<PBMessage>) value;
- (void) writeUInt32:(int32_t) fieldNumber value:(int32_t) value;
- (void) writeSFixed32:(int32_t) fieldNumber value:(int32_t) value;
- (void) writeSFixed64:(int32_t) fieldNumber value:(int64_t) value;
- (void) writeSInt32:(int32_t) fieldNumber value:(int32_t) value;
- (void) writeSInt64:(int32_t) fieldNumber value:(int64_t) value;

- (void) writeDoubleNoTag:(Float64) value;
- (void) writeFloatNoTag:(Float32) value;
- (void) writeUInt64NoTag:(int64_t) value;
- (void) writeInt64NoTag:(int64_t) value;
- (void) writeInt32NoTag:(int32_t) value;
- (void) writeFixed64NoTag:(int64_t) value;
- (void) writeFixed32NoTag:(int32_t) value;
- (void) writeBoolNoTag:(BOOL) value;
- (void) writeStringNoTag:(NSString*) value;
- (void) writeGroupNoTag:(int32_t) fieldNumber value:(id<PBMessage>) value;
- (void) writeUnknownGroupNoTag:(int32_t) fieldNumber value:(PBUnknownFieldSet*) value;
- (void) writeMessageNoTag:(id<PBMessage>) value;
- (void) writeDataNoTag:(NSData*) value;
- (void) writeUInt32NoTag:(int32_t) value;
- (void) writeEnumNoTag:(int32_t) value;
- (void) writeSFixed32NoTag:(int32_t) value;
- (void) writeSFixed64NoTag:(int64_t) value;
- (void) writeSInt32NoTag:(int32_t) value;
- (void) writeSInt64NoTag:(int64_t) value;


/**
 * Write a MessageSet extension field to the stream.  For historical reasons,
 * the wire format differs from normal fields.
 */
- (void) writeMessageSetExtension:(int32_t) fieldNumber value:(id<PBMessage>) value;

/**
 * Write an unparsed MessageSet extension field to the stream.  For
 * historical reasons, the wire format differs from normal fields.
 */
- (void) writeRawMessageSetExtension:(int32_t) fieldNumber value:(NSData*) value;

/**
 * Write an enum field, including tag, to the stream.  Caller is responsible
 * for converting the enum value to its numeric value.
 */
- (void) writeEnum:(int32_t) fieldNumber value:(int32_t) value;

@end
