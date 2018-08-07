//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSChunkedOutputStream : NSObject

// Indicates whether any write failed.
@property (nonatomic, readonly) BOOL hasError;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithOutputStream:(NSOutputStream *)outputStream;

// Returns NO on error.
- (BOOL)writeData:(NSData *)data;
- (BOOL)writeVariableLengthUInt32:(UInt32)value;

@end

NS_ASSUME_NONNULL_END
