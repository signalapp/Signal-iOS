//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface ByteParser : NSObject

@property (nonatomic, readonly) BOOL hasError;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithData:(NSData *)data littleEndian:(BOOL)littleEndian;

#pragma mark - UInt16

- (uint16_t)uint16AtIndex:(NSUInteger)index;
- (uint16_t)nextUInt16;

#pragma mark - UInt32

- (uint32_t)uint32AtIndex:(NSUInteger)index;
- (uint32_t)nextUInt32;

#pragma mark - UInt64

- (uint64_t)uint64AtIndex:(NSUInteger)index;
- (uint64_t)nextUInt64;

#pragma mark -

- (BOOL)readZero:(NSUInteger)length;

- (nullable NSData *)readBytes:(NSUInteger)length;

@end

NS_ASSUME_NONNULL_END
