//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const OWSChunkedOutputStreamErrorDomain;
typedef NS_ERROR_ENUM(OWSChunkedOutputStreamErrorDomain, OWSChunkedOutputStreamError) {
    OWSChunkedOutputStreamErrorWriteFailed,
};

@interface OWSChunkedOutputStream : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithOutputStream:(NSOutputStream *)outputStream NS_DESIGNATED_INITIALIZER;

- (BOOL)writeData:(NSData *)value error:(NSError **)error NS_SWIFT_NAME(writeData(_:));
- (BOOL)writeVariableLengthUInt32:(UInt32)value error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
