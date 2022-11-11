//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSChunkedOutputStream : NSObject

// Indicates whether any write failed.
@property (nonatomic, readonly) BOOL hasError;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithOutputStream:(NSOutputStream *)outputStream;

// Returns NO on error.
- (BOOL)writeData:(NSData *)data;
- (BOOL)writeVariableLengthUInt32:(UInt32)value;

@end

NS_ASSUME_NONNULL_END
