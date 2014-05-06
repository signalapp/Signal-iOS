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

@class PBExtensionRegistry;
@class PBUnknownFieldSet_Builder;
@protocol PBMessage_Builder;

/**
 * Reads and decodes protocol message fields.
 *
 * This class contains two kinds of methods:  methods that read specific
 * protocol message constructs and field types (e.g. {@link #readTag()} and
 * {@link #readInt32()}) and methods that read low-level values (e.g.
 * {@link #readRawVarint32()} and {@link #readRawBytes}).  If you are reading
 * encoded protocol messages, you should use the former methods, but if you are
 * reading some other format of your own design, use the latter.
 *
 * @author Cyrus Najmabadi
 */
@interface PBCodedInputStream : NSObject {
@private
  NSMutableData* buffer;
  int32_t bufferSize;
  int32_t bufferSizeAfterLimit;
  int32_t bufferPos;
  NSInputStream* input;
  int32_t lastTag;

  /**
   * The total number of bytes read before the current buffer.  The total
   * bytes read up to the current position can be computed as
   * {@code totalBytesRetired + bufferPos}.
   */
  int32_t totalBytesRetired;

  /** The absolute position of the end of the current message. */
  int32_t currentLimit;

  /** See setRecursionLimit() */
  int32_t recursionDepth;
  int32_t recursionLimit;

  /** See setSizeLimit() */
  int32_t sizeLimit;
}

+ (PBCodedInputStream*) streamWithData:(NSData*) data;
+ (PBCodedInputStream*) streamWithInputStream:(NSInputStream*) input;

/**
 * Attempt to read a field tag, returning zero if we have reached EOF.
 * Protocol message parsers use this to read tags, since a protocol message
 * may legally end wherever a tag occurs, and zero is not a valid tag number.
 */
- (int32_t) readTag;
- (BOOL) refillBuffer:(BOOL) mustSucceed;

- (Float64) readDouble;
- (Float32) readFloat;
- (int64_t) readUInt64;
- (int32_t) readUInt32;
- (int64_t) readInt64;
- (int32_t) readInt32;
- (int64_t) readFixed64;
- (int32_t) readFixed32;
- (int32_t) readEnum;
- (int32_t) readSFixed32;
- (int64_t) readSFixed64;
- (int32_t) readSInt32;
- (int64_t) readSInt64;

/**
 * Read one byte from the input.
 *
 * @throws InvalidProtocolBuffer The end of the stream or the current
 *                                        limit was reached.
 */
- (int8_t) readRawByte;

/**
 * Read a raw Varint from the stream.  If larger than 32 bits, discard the
 * upper bits.
 */
- (int32_t) readRawVarint32;
- (int64_t) readRawVarint64;
- (int32_t) readRawLittleEndian32;
- (int64_t) readRawLittleEndian64;

/**
 * Read a fixed size of bytes from the input.
 *
 * @throws InvalidProtocolBuffer The end of the stream or the current
 *                                        limit was reached.
 */
- (NSData*) readRawData:(int32_t) size;

/**
 * Reads and discards a single field, given its tag value.
 *
 * @return {@code false} if the tag is an endgroup tag, in which case
 *         nothing is skipped.  Otherwise, returns {@code true}.
 */
- (BOOL) skipField:(int32_t) tag;


/**
 * Reads and discards {@code size} bytes.
 *
 * @throws InvalidProtocolBuffer The end of the stream or the current
 *                                        limit was reached.
 */
- (void) skipRawData:(int32_t) size;

/**
 * Reads and discards an entire message.  This will read either until EOF
 * or until an endgroup tag, whichever comes first.
 */
- (void) skipMessage;

- (BOOL) isAtEnd;
- (int32_t) pushLimit:(int32_t) byteLimit;
- (void) recomputeBufferSizeAfterLimit;
- (void) popLimit:(int32_t) oldLimit;
- (int32_t) bytesUntilLimit;

/**
 * Decode a ZigZag-encoded 32-bit value.  ZigZag encodes signed integers
 * into values that can be efficiently encoded with varint.  (Otherwise,
 * negative values must be sign-extended to 64 bits to be varint encoded,
 * thus always taking 10 bytes on the wire.)
 *
 * @param n An unsigned 32-bit integer, stored in a signed int.
 * @return A signed 32-bit integer.
 */
int32_t decodeZigZag32(int32_t n);

/**
 * Decode a ZigZag-encoded 64-bit value.  ZigZag encodes signed integers
 * into values that can be efficiently encoded with varint.  (Otherwise,
 * negative values must be sign-extended to 64 bits to be varint encoded,
 * thus always taking 10 bytes on the wire.)
 *
 * @param n An unsigned 64-bit integer, stored in a signed int.
 * @return A signed 64-bit integer.
 */
int64_t decodeZigZag64(int64_t n);

/** Read an embedded message field value from the stream. */
- (void) readMessage:(id<PBMessage_Builder>) builder extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) readBool;
- (NSString*) readString;
- (NSData*) readData;

- (void) readGroup:(int32_t) fieldNumber builder:(id<PBMessage_Builder>) builder extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

/**
 * Reads a {@code group} field value from the stream and merges it into the
 * given {@link UnknownFieldSet}.
 */
- (void) readUnknownGroup:(int32_t) fieldNumber builder:(PBUnknownFieldSet_Builder*) builder;

/**
 * Verifies that the last call to readTag() returned the given tag value.
 * This is used to verify that a nested group ended with the correct
 * end tag.
 *
 * @throws InvalidProtocolBuffer {@code value} does not match the
 *                                        last tag.
 */
- (void) checkLastTagWas:(int32_t) value;

@end
