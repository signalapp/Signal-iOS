//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface ByteParser : NSObject

@property (nonatomic, readonly) BOOL hasError;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithData:(NSData *)data littleEndian:(BOOL)littleEndian;

#pragma mark - Short

- (uint16_t)shortAtIndex:(NSUInteger)index;
- (uint16_t)nextShort;

#pragma mark - Int

- (uint32_t)intAtIndex:(NSUInteger)index;
- (uint32_t)nextInt;

#pragma mark - Long

- (uint64_t)longAtIndex:(NSUInteger)index;
- (uint64_t)nextLong;

#pragma mark -

- (BOOL)readZero:(NSUInteger)length;

- (nullable NSData *)readBytes:(NSUInteger)length;

@end

NS_ASSUME_NONNULL_END
