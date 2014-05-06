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

#import "CodedOutputStream.h"

#import "Message.h"
#import "Utilities.h"
#import "WireFormat.h"
#import "UnknownFieldSet.h"

@interface PBCodedOutputStream ()
@property (retain) NSMutableData* buffer;
@property int32_t position;
@property (retain) NSOutputStream* output;
@end


@implementation PBCodedOutputStream

const int32_t DEFAULT_BUFFER_SIZE = 4096;
const int32_t LITTLE_ENDIAN_32_SIZE = 4;
const int32_t LITTLE_ENDIAN_64_SIZE = 8;

@synthesize output;
@synthesize buffer;
@synthesize position;

- (void) dealloc {
  [output close];
  self.output = nil;
  self.buffer = nil;
  self.position = 0;
}


- (id) initWithOutputStream:(NSOutputStream*) output_
                       data:(NSMutableData*) data_ {
  if ((self = [super init])) {
    self.output = output_;
    self.buffer = data_;
    self.position = 0;

    [output open];
  }

  return self;
}


+ (PBCodedOutputStream*) streamWithOutputStream:(NSOutputStream*) output
                                     bufferSize:(int32_t) bufferSize {
  NSMutableData* data = [NSMutableData dataWithLength:(NSUInteger)bufferSize];
  return [[PBCodedOutputStream alloc] initWithOutputStream:output
                                                       data:data];
}


+ (PBCodedOutputStream*) streamWithOutputStream:(NSOutputStream*) output {
  return [PBCodedOutputStream streamWithOutputStream:output bufferSize:DEFAULT_BUFFER_SIZE];
}


+ (PBCodedOutputStream*) streamWithData:(NSMutableData*) data {
    return [[PBCodedOutputStream alloc] initWithOutputStream:nil data:data];
}


- (void) writeDoubleNoTag:(Float64) value {
  [self writeRawLittleEndian64:convertFloat64ToInt64(value)];
}


/** Write a {@code double} field, including tag, to the stream. */
- (void) writeDouble:(int32_t) fieldNumber
               value:(Float64) value {
  [self writeTag:fieldNumber format:PBWireFormatFixed64];
  [self writeDoubleNoTag:value];
}


- (void) writeFloatNoTag:(Float32) value {
  [self writeRawLittleEndian32:convertFloat32ToInt32(value)];
}


/** Write a {@code float} field, including tag, to the stream. */
- (void) writeFloat:(int32_t) fieldNumber
              value:(Float32) value {
  [self writeTag:fieldNumber format:PBWireFormatFixed32];
  [self writeFloatNoTag:value];
}


- (void) writeUInt64NoTag:(int64_t) value {
  [self writeRawVarint64:value];
}


/** Write a {@code uint64} field, including tag, to the stream. */
- (void) writeUInt64:(int32_t) fieldNumber
               value:(int64_t) value {
  [self writeTag:fieldNumber format:PBWireFormatVarint];
  [self writeUInt64NoTag:value];
}


- (void) writeInt64NoTag:(int64_t) value {
  [self writeRawVarint64:value];
}


/** Write an {@code int64} field, including tag, to the stream. */
- (void) writeInt64:(int32_t) fieldNumber
              value:(int64_t) value {
  [self writeTag:fieldNumber format:PBWireFormatVarint];
  [self writeInt64NoTag:value];
}


- (void) writeInt32NoTag:(int32_t) value {
  if (value >= 0) {
    [self writeRawVarint32:value];
  } else {
    // Must sign-extend
    [self writeRawVarint64:value];
  }
}


/** Write an {@code int32} field, including tag, to the stream. */
- (void) writeInt32:(int32_t) fieldNumber
              value:(int32_t) value {
  [self writeTag:fieldNumber format:PBWireFormatVarint];
  [self writeInt32NoTag:value];
}


- (void) writeFixed64NoTag:(int64_t) value {
  [self writeRawLittleEndian64:value];
}


/** Write a {@code fixed64} field, including tag, to the stream. */
- (void) writeFixed64:(int32_t) fieldNumber
                value:(int64_t) value {
  [self writeTag:fieldNumber format:PBWireFormatFixed64];
  [self writeFixed64NoTag:value];
}


- (void) writeFixed32NoTag:(int32_t) value {
  [self writeRawLittleEndian32:value];
}


/** Write a {@code fixed32} field, including tag, to the stream. */
- (void) writeFixed32:(int32_t) fieldNumber
                value:(int32_t) value {
  [self writeTag:fieldNumber format:PBWireFormatFixed32];
  [self writeFixed32NoTag:value];
}


- (void) writeBoolNoTag:(BOOL) value {
  [self writeRawByte:(value ? 1 : 0)];
}


/** Write a {@code bool} field, including tag, to the stream. */
- (void) writeBool:(int32_t) fieldNumber
             value:(BOOL) value {
  [self writeTag:fieldNumber format:PBWireFormatVarint];
  [self writeBoolNoTag:value];
}


- (void) writeStringNoTag:(NSString*) value {
  NSData* data = [value dataUsingEncoding:NSUTF8StringEncoding];
  [self writeRawVarint32:(int32_t)data.length];
  [self writeRawData:data];
}


/** Write a {@code string} field, including tag, to the stream. */
- (void) writeString:(int32_t) fieldNumber
               value:(NSString*) value {
  // TODO(cyrusn): we could probably use:
  // NSString:getBytes:maxLength:usedLength:encoding:options:range:remainingRange:
  // to write directly into our buffer.
  [self writeTag:fieldNumber format:PBWireFormatLengthDelimited];
  [self writeStringNoTag:value];
}


- (void) writeGroupNoTag:(int32_t) fieldNumber
                   value:(id<PBMessage>) value {
  [value writeToCodedOutputStream:self];
  [self writeTag:fieldNumber format:PBWireFormatEndGroup];
}


/** Write a {@code group} field, including tag, to the stream. */
- (void) writeGroup:(int32_t) fieldNumber
              value:(id<PBMessage>) value {
  [self writeTag:fieldNumber format:PBWireFormatStartGroup];
  [self writeGroupNoTag:fieldNumber value:value];
}


- (void) writeUnknownGroupNoTag:(int32_t) fieldNumber
                     value:(PBUnknownFieldSet*) value {
  [value writeToCodedOutputStream:self];
  [self writeTag:fieldNumber format:PBWireFormatEndGroup];
}


/** Write a group represented by an {@link PBUnknownFieldSet}. */
- (void) writeUnknownGroup:(int32_t) fieldNumber
                     value:(PBUnknownFieldSet*) value {
  [self writeTag:fieldNumber format:PBWireFormatStartGroup];
  [self writeUnknownGroupNoTag:fieldNumber value:value];
}


- (void) writeMessageNoTag:(id<PBMessage>) value {
  [self writeRawVarint32:[value serializedSize]];
  [value writeToCodedOutputStream:self];
}


/** Write an embedded message field, including tag, to the stream. */
- (void) writeMessage:(int32_t) fieldNumber
                value:(id<PBMessage>) value {
  [self writeTag:fieldNumber format:PBWireFormatLengthDelimited];
  [self writeMessageNoTag:value];
}


- (void) writeDataNoTag:(NSData*) value {
  [self writeRawVarint32:(int32_t)value.length];
  [self writeRawData:value];
}


/** Write a {@code bytes} field, including tag, to the stream. */
- (void) writeData:(int32_t) fieldNumber value:(NSData*) value {
  [self writeTag:fieldNumber format:PBWireFormatLengthDelimited];
  [self writeDataNoTag:value];
}


- (void) writeUInt32NoTag:(int32_t) value {
  [self writeRawVarint32:value];
}


/** Write a {@code uint32} field, including tag, to the stream. */
- (void) writeUInt32:(int32_t) fieldNumber
               value:(int32_t) value {
  [self writeTag:fieldNumber format:PBWireFormatVarint];
  [self writeUInt32NoTag:value];
}


- (void) writeEnumNoTag:(int32_t) value {
  [self writeRawVarint32:value];
}


/**
 * Write an enum field, including tag, to the stream.  Caller is responsible
 * for converting the enum value to its numeric value.
 */
- (void) writeEnum:(int32_t) fieldNumber
             value:(int32_t) value {
  [self writeTag:fieldNumber format:PBWireFormatVarint];
  [self writeEnumNoTag:value];
}


- (void) writeSFixed32NoTag:(int32_t) value {
  [self writeRawLittleEndian32:value];
}


/** Write an {@code sfixed32} field, including tag, to the stream. */
- (void) writeSFixed32:(int32_t) fieldNumber
                 value:(int32_t) value {
  [self writeTag:fieldNumber format:PBWireFormatFixed32];
  [self writeSFixed32NoTag:value];
}


- (void) writeSFixed64NoTag:(int64_t) value {
  [self writeRawLittleEndian64:value];
}


/** Write an {@code sfixed64} field, including tag, to the stream. */
- (void) writeSFixed64:(int32_t) fieldNumber
                 value:(int64_t) value {
  [self writeTag:fieldNumber format:PBWireFormatFixed64];
  [self writeSFixed64NoTag:value];
}


- (void) writeSInt32NoTag:(int32_t) value {
  [self writeRawVarint32:encodeZigZag32(value)];
}


/** Write an {@code sint32} field, including tag, to the stream. */
- (void) writeSInt32:(int32_t) fieldNumber
               value:(int32_t) value {
  [self writeTag:fieldNumber format:PBWireFormatVarint];
  [self writeSInt32NoTag:value];
}


- (void) writeSInt64NoTag:(int64_t) value {
  [self writeRawVarint64:encodeZigZag64(value)];
}


/** Write an {@code sint64} field, including tag, to the stream. */
- (void) writeSInt64:(int32_t) fieldNumber
               value:(int64_t) value {
  [self writeTag:fieldNumber format:PBWireFormatVarint];
  [self writeSInt64NoTag:value];
}


/**
 * Write a MessageSet extension field to the stream.  For historical reasons,
 * the wire format differs from normal fields.
 */
- (void) writeMessageSetExtension:(int32_t) fieldNumber
                            value:(id<PBMessage>) value {
  [self writeTag:PBWireFormatMessageSetItem format:PBWireFormatStartGroup];
  [self writeUInt32:PBWireFormatMessageSetTypeId value:fieldNumber];
  [self writeMessage:PBWireFormatMessageSetMessage value:value];
  [self writeTag:PBWireFormatMessageSetItem format:PBWireFormatEndGroup];
}


/**
 * Write an unparsed MessageSet extension field to the stream.  For
 * historical reasons, the wire format differs from normal fields.
 */
- (void) writeRawMessageSetExtension:(int32_t) fieldNumber
                               value:(NSData*) value {
  [self writeTag:PBWireFormatMessageSetItem format:PBWireFormatStartGroup];
  [self writeUInt32:PBWireFormatMessageSetTypeId value:fieldNumber];
  [self writeData:PBWireFormatMessageSetMessage value:value];
  [self writeTag:PBWireFormatMessageSetItem format:PBWireFormatEndGroup];
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code double} field, including tag.
 */
int32_t computeDoubleSizeNoTag(Float64 value) {
  return LITTLE_ENDIAN_64_SIZE;
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code float} field, including tag.
 */
int32_t computeFloatSizeNoTag(Float32 value) {
  return LITTLE_ENDIAN_32_SIZE;
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code uint64} field, including tag.
 */
int32_t computeUInt64SizeNoTag(int64_t value) {
  return computeRawVarint64Size(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code int64} field, including tag.
 */
int32_t computeInt64SizeNoTag(int64_t value) {
  return computeRawVarint64Size(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code int32} field, including tag.
 */
int32_t computeInt32SizeNoTag(int32_t value) {
  if (value >= 0) {
    return computeRawVarint32Size(value);
  } else {
    // Must sign-extend.
    return 10;
  }
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code fixed64} field, including tag.
 */
int32_t computeFixed64SizeNoTag(int64_t value) {
  return LITTLE_ENDIAN_64_SIZE;
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code fixed32} field, including tag.
 */
int32_t computeFixed32SizeNoTag(int32_t value) {
  return LITTLE_ENDIAN_32_SIZE;
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code bool} field, including tag.
 */
int32_t computeBoolSizeNoTag(BOOL value) {
  return 1;
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code string} field, including tag.
 */
int32_t computeStringSizeNoTag(NSString* value) {
  NSData* data = [value dataUsingEncoding:NSUTF8StringEncoding];
  return computeRawVarint32Size((int32_t)data.length) + (int32_t)data.length;
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code group} field, including tag.
 */
int32_t computeGroupSizeNoTag(id<PBMessage> value) {
  return [value serializedSize];
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code group} field represented by an {@code PBUnknownFieldSet}, including
 * tag.
 */
int32_t computeUnknownGroupSizeNoTag(PBUnknownFieldSet* value) {
  return value.serializedSize;
}


/**
 * Compute the number of bytes that would be needed to encode an
 * embedded message field, including tag.
 */
int32_t computeMessageSizeNoTag(id<PBMessage> value) {
  int32_t size = [value serializedSize];
  return computeRawVarint32Size(size) + size;
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code bytes} field, including tag.
 */
int32_t computeDataSizeNoTag(NSData* value) {
  return computeRawVarint32Size((int32_t)value.length) + (int32_t)value.length;
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code uint32} field, including tag.
 */
int32_t computeUInt32SizeNoTag(int32_t value) {
  return computeRawVarint32Size(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * enum field, including tag.  Caller is responsible for converting the
 * enum value to its numeric value.
 */
int32_t computeEnumSizeNoTag(int32_t value) {
  return computeRawVarint32Size(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code sfixed32} field, including tag.
 */
int32_t computeSFixed32SizeNoTag(int32_t value) {
  return LITTLE_ENDIAN_32_SIZE;
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code sfixed64} field, including tag.
 */
int32_t computeSFixed64SizeNoTag(int64_t value) {
  return LITTLE_ENDIAN_64_SIZE;
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code sint32} field, including tag.
 */
int32_t computeSInt32SizeNoTag(int32_t value) {
  return computeRawVarint32Size(encodeZigZag32(value));
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code sint64} field, including tag.
 */
int32_t computeSInt64SizeNoTag(int64_t value) {
  return computeRawVarint64Size(encodeZigZag64(value));
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code double} field, including tag.
 */
int32_t computeDoubleSize(int32_t fieldNumber, Float64 value) {
  return computeTagSize(fieldNumber) + computeDoubleSizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code float} field, including tag.
 */
int32_t computeFloatSize(int32_t fieldNumber, Float32 value) {
  return computeTagSize(fieldNumber) + computeFloatSizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code uint64} field, including tag.
 */
int32_t computeUInt64Size(int32_t fieldNumber, int64_t value) {
  return computeTagSize(fieldNumber) + computeUInt64SizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code int64} field, including tag.
 */
int32_t computeInt64Size(int32_t fieldNumber, int64_t value) {
  return computeTagSize(fieldNumber) + computeInt64SizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code int32} field, including tag.
 */
int32_t computeInt32Size(int32_t fieldNumber, int32_t value) {
  return computeTagSize(fieldNumber) + computeInt32SizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code fixed64} field, including tag.
 */
int32_t computeFixed64Size(int32_t fieldNumber, int64_t value) {
  return computeTagSize(fieldNumber) + computeFixed64SizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code fixed32} field, including tag.
 */
int32_t computeFixed32Size(int32_t fieldNumber, int32_t value) {
  return computeTagSize(fieldNumber) + computeFixed32SizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code bool} field, including tag.
 */
int32_t computeBoolSize(int32_t fieldNumber, BOOL value) {
  return computeTagSize(fieldNumber) + computeBoolSizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code string} field, including tag.
 */
int32_t computeStringSize(int32_t fieldNumber, NSString* value) {
  return computeTagSize(fieldNumber) + computeStringSizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code group} field, including tag.
 */
int32_t computeGroupSize(int32_t fieldNumber, id<PBMessage> value) {
  return computeTagSize(fieldNumber) * 2 + computeGroupSizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code group} field represented by an {@code PBUnknownFieldSet}, including
 * tag.
 */
int32_t computeUnknownGroupSize(int32_t fieldNumber,
                                PBUnknownFieldSet* value) {
  return computeTagSize(fieldNumber) * 2 + computeUnknownGroupSizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * embedded message field, including tag.
 */
int32_t computeMessageSize(int32_t fieldNumber, id<PBMessage> value) {
  return computeTagSize(fieldNumber) + computeMessageSizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code bytes} field, including tag.
 */
int32_t computeDataSize(int32_t fieldNumber, NSData* value) {
  return computeTagSize(fieldNumber) + computeDataSizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode a
 * {@code uint32} field, including tag.
 */
int32_t computeUInt32Size(int32_t fieldNumber, int32_t value) {
  return computeTagSize(fieldNumber) + computeUInt32SizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * enum field, including tag.  Caller is responsible for converting the
 * enum value to its numeric value.
 */
int32_t computeEnumSize(int32_t fieldNumber, int32_t value) {
  return computeTagSize(fieldNumber) + computeEnumSizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code sfixed32} field, including tag.
 */
int32_t computeSFixed32Size(int32_t fieldNumber, int32_t value) {
  return computeTagSize(fieldNumber) + computeSFixed32SizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code sfixed64} field, including tag.
 */
int32_t computeSFixed64Size(int32_t fieldNumber, int64_t value) {
  return computeTagSize(fieldNumber) + computeSFixed64SizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code sint32} field, including tag.
 */
int32_t computeSInt32Size(int32_t fieldNumber, int32_t value) {
  return computeTagSize(fieldNumber) + computeSInt32SizeNoTag(value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * {@code sint64} field, including tag.
 */
int32_t computeSInt64Size(int32_t fieldNumber, int64_t value) {
  return computeTagSize(fieldNumber) +
  computeRawVarint64Size(encodeZigZag64(value));
}


/**
 * Compute the number of bytes that would be needed to encode a
 * MessageSet extension to the stream.  For historical reasons,
 * the wire format differs from normal fields.
 */
int32_t computeMessageSetExtensionSize(int32_t fieldNumber, id<PBMessage> value) {
  return computeTagSize(PBWireFormatMessageSetItem) * 2 +
  computeUInt32Size(PBWireFormatMessageSetTypeId, fieldNumber) +
  computeMessageSize(PBWireFormatMessageSetMessage, value);
}


/**
 * Compute the number of bytes that would be needed to encode an
 * unparsed MessageSet extension field to the stream.  For
 * historical reasons, the wire format differs from normal fields.
 */
int32_t computeRawMessageSetExtensionSize(int32_t fieldNumber, NSData* value) {
  return computeTagSize(PBWireFormatMessageSetItem) * 2 +
  computeUInt32Size(PBWireFormatMessageSetTypeId, fieldNumber) +
  computeDataSize(PBWireFormatMessageSetMessage, value);
}


/**
 * Internal helper that writes the current buffer to the output. The
 * buffer position is reset to its initial value when this returns.
 */
- (void) refreshBuffer {
  if (output == nil) {
    // We're writing to a single buffer.
    @throw [NSException exceptionWithName:@"OutOfSpace" reason:@"" userInfo:nil];
  }


  [output write:buffer.bytes maxLength:(NSUInteger)position];
  position = 0;
}


/**
 * Flushes the stream and forces any buffered bytes to be written.  This
 * does not flush the underlying OutputStream.
 */
- (void) flush {
  if (output != nil) {
    [self refreshBuffer];
  }
}


/**
 * If writing to a flat array, return the space left in the array.
 * Otherwise, throws {@code UnsupportedOperationException}.
 */
- (int32_t) spaceLeft {
  if (output == nil) {
    return (int32_t)buffer.length - position;
  } else {
    @throw [NSException exceptionWithName:@"UnsupportedOperation"
                                   reason:@"spaceLeft() can only be called on CodedOutputStreams that are writing to a flat array."
                                 userInfo:nil];
  }
}


/**
 * Verifies that {@link #spaceLeft()} returns zero.  It's common to create
 * a byte array that is exactly big enough to hold a message, then write to
 * it with a {@code PBCodedOutputStream}.  Calling {@code checkNoSpaceLeft()}
 * after writing verifies that the message was actually as big as expected,
 * which can help catch bugs.
 */
- (void) checkNoSpaceLeft {
  if (self.spaceLeft != 0) {
    @throw [NSException exceptionWithName:@"IllegalState" reason:@"Did not write as much data as expected." userInfo:nil];
  }
}


/** Write a single byte. */
- (void) writeRawByte:(uint8_t) value {
  if (position == (int32_t)buffer.length) {
    [self refreshBuffer];
  }

  ((uint8_t*)buffer.mutableBytes)[position++] = value;
}


/** Write an array of bytes. */
- (void) writeRawData:(NSData*) data {
  [self writeRawData:data offset:0 length:(int32_t)data.length];
}


- (void) writeRawData:(NSData*) value offset:(int32_t) offset length:(int32_t) length {
  if ((int32_t)buffer.length - position >= length) {
    // We have room in the current buffer.
    memcpy(((uint8_t*)buffer.mutableBytes) + position, ((uint8_t*)value.bytes) + offset, length);
    position += length;
  } else {
    // Write extends past current buffer.  Fill the rest of this buffer and flush.
    int32_t bytesWritten = (int32_t)buffer.length - position;
    memcpy(((uint8_t*)buffer.mutableBytes) + position, ((uint8_t*)value.bytes) + offset, bytesWritten);
    offset += bytesWritten;
    length -= bytesWritten;
    position = (int32_t)buffer.length;
    [self refreshBuffer];

    // Now deal with the rest.
    // Since we have an output stream, this is our buffer
    // and buffer offset == 0
    if (length <= (int32_t)buffer.length) {
      // Fits in new buffer.
      memcpy((uint8_t*)buffer.mutableBytes, ((uint8_t*)value.bytes) + offset, length);
      position = length;
    } else {
      // Write is very big.  Let's do it all at once.
      [output write:((uint8_t*) value.bytes) + offset maxLength:(NSUInteger)length];
    }
  }
}


/** Encode and write a tag. */
- (void) writeTag:(int32_t) fieldNumber
           format:(int32_t) format {
  [self writeRawVarint32:PBWireFormatMakeTag(fieldNumber, format)];
}


/** Compute the number of bytes that would be needed to encode a tag. */
int32_t computeTagSize(int32_t fieldNumber) {
  return computeRawVarint32Size(PBWireFormatMakeTag(fieldNumber, 0));
}


/**
 * Encode and write a varint.  {@code value} is treated as
 * unsigned, so it won't be sign-extended if negative.
 */
- (void) writeRawVarint32:(int32_t) value {
  while (YES) {
    if ((value & ~0x7F) == 0) {
      [self writeRawByte:(uint8_t)value];
      return;
    } else {
      [self writeRawByte:((value & 0x7F) | 0x80)];
      value = logicalRightShift32(value, 7);
    }
  }
}


/**
 * Compute the number of bytes that would be needed to encode a varint.
 * {@code value} is treated as unsigned, so it won't be sign-extended if
 * negative.
 */
int32_t computeRawVarint32Size(int32_t value) {
  if ((value & (0xffffffffLL <<  7)) == 0) return 1;
  if ((value & (0xffffffffLL << 14)) == 0) return 2;
  if ((value & (0xffffffffLL << 21)) == 0) return 3;
  if ((value & (0xffffffffLL << 28)) == 0) return 4;
  return 5;
}


/** Encode and write a varint. */
- (void) writeRawVarint64:(int64_t) value{
  while (YES) {
    if ((value & ~0x7FL) == 0) {
      [self writeRawByte:(uint8_t)((int32_t) value)];
      return;
    } else {
      [self writeRawByte:(uint8_t)(((int32_t) value & 0x7F) | 0x80)];
      value = logicalRightShift64(value, 7);
    }
  }
}


/** Compute the number of bytes that would be needed to encode a varint. */
int32_t computeRawVarint64Size(int64_t value) {
  if (((uint64_t)value & (0xffffffffffffffffULL <<  7)) == 0) return 1;
  if (((uint64_t)value & (0xffffffffffffffffULL << 14)) == 0) return 2;
  if (((uint64_t)value & (0xffffffffffffffffULL << 21)) == 0) return 3;
  if (((uint64_t)value & (0xffffffffffffffffULL << 28)) == 0) return 4;
  if (((uint64_t)value & (0xffffffffffffffffULL << 35)) == 0) return 5;
  if (((uint64_t)value & (0xffffffffffffffffULL << 42)) == 0) return 6;
  if (((uint64_t)value & (0xffffffffffffffffULL << 49)) == 0) return 7;
  if (((uint64_t)value & (0xffffffffffffffffULL << 56)) == 0) return 8;
  if (((uint64_t)value & (0xffffffffffffffffULL << 63)) == 0) return 9;
  return 10;
}


/** Write a little-endian 32-bit integer. */
- (void) writeRawLittleEndian32:(int32_t) value {
  [self writeRawByte:((value      ) & 0xFF)];
  [self writeRawByte:((value >>  8) & 0xFF)];
  [self writeRawByte:((value >> 16) & 0xFF)];
  [self writeRawByte:((value >> 24) & 0xFF)];
}


/** Write a little-endian 64-bit integer. */
- (void) writeRawLittleEndian64:(int64_t) value {
  [self writeRawByte:((int32_t)(value      ) & 0xFF)];
  [self writeRawByte:((int32_t)(value >>  8) & 0xFF)];
  [self writeRawByte:((int32_t)(value >> 16) & 0xFF)];
  [self writeRawByte:((int32_t)(value >> 24) & 0xFF)];
  [self writeRawByte:((int32_t)(value >> 32) & 0xFF)];
  [self writeRawByte:((int32_t)(value >> 40) & 0xFF)];
  [self writeRawByte:((int32_t)(value >> 48) & 0xFF)];
  [self writeRawByte:((int32_t)(value >> 56) & 0xFF)];
}


/**
 * Encode a ZigZag-encoded 32-bit value.  ZigZag encodes signed integers
 * into values that can be efficiently encoded with varint.  (Otherwise,
 * negative values must be sign-extended to 64 bits to be varint encoded,
 * thus always taking 10 bytes on the wire.)
 *
 * @param n A signed 32-bit integer.
 * @return An unsigned 32-bit integer, stored in a signed int
 */
int32_t encodeZigZag32(int32_t n) {
  // Note:  the right-shift must be arithmetic
  return (n << 1) ^ (n >> 31);
}


/**
 * Encode a ZigZag-encoded 64-bit value.  ZigZag encodes signed integers
 * into values that can be efficiently encoded with varint.  (Otherwise,
 * negative values must be sign-extended to 64 bits to be varint encoded,
 * thus always taking 10 bytes on the wire.)
 *
 * @param n A signed 64-bit integer.
 * @return An unsigned 64-bit integer, stored in a signed int
 */
int64_t encodeZigZag64(int64_t n) {
  // Note:  the right-shift must be arithmetic
  return (n << 1) ^ (n >> 63);
}

@end
