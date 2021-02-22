//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ByteParser.h"

NS_ASSUME_NONNULL_BEGIN

@interface ByteParser ()

@property (nonatomic, readonly) BOOL littleEndian;
@property (nonatomic, readonly) NSData *data;
@property (nonatomic) NSUInteger cursor;
@property (nonatomic) BOOL hasError;

@end

#pragma mark -

@implementation ByteParser

- (instancetype)initWithData:(NSData *)data littleEndian:(BOOL)littleEndian
{
    if (self = [super init]) {
        _littleEndian = littleEndian;
        _data = data;
    }

    return self;
}

#pragma mark - Short

- (uint16_t)shortAtIndex:(NSUInteger)index
{
    uint16_t value;
    const size_t valueSize = sizeof(value);
    OWSAssertDebug(valueSize == 2);
    if (index + valueSize > self.data.length) {
        self.hasError = YES;
        return 0;
    }
    [self.data getBytes:&value range:NSMakeRange(index, valueSize)];
    if (self.littleEndian) {
        return CFSwapInt16LittleToHost(value);
    } else {
        return CFSwapInt16BigToHost(value);
    }
}

- (uint16_t)nextShort
{
    uint16_t value = [self shortAtIndex:self.cursor];
    self.cursor += sizeof(value);
    return value;
}

#pragma mark - Int

- (uint32_t)intAtIndex:(NSUInteger)index
{
    uint32_t value;
    const size_t valueSize = sizeof(value);
    OWSAssertDebug(valueSize == 4);
    if (index + valueSize > self.data.length) {
        self.hasError = YES;
        return 0;
    }
    [self.data getBytes:&value range:NSMakeRange(index, valueSize)];
    if (self.littleEndian) {
        return CFSwapInt32LittleToHost(value);
    } else {
        return CFSwapInt32BigToHost(value);
    }
}

- (uint32_t)nextInt
{
    uint32_t value = [self intAtIndex:self.cursor];
    self.cursor += sizeof(value);
    return value;
}

#pragma mark - Long

- (uint64_t)longAtIndex:(NSUInteger)index
{
    uint64_t value;
    const size_t valueSize = sizeof(value);
    OWSAssertDebug(valueSize == 8);
    if (index + valueSize > self.data.length) {
        self.hasError = YES;
        return 0;
    }
    [self.data getBytes:&value range:NSMakeRange(index, valueSize)];
    if (self.littleEndian) {
        return CFSwapInt64LittleToHost(value);
    } else {
        return CFSwapInt64BigToHost(value);
    }
}

- (uint64_t)nextLong
{
    uint64_t value = [self longAtIndex:self.cursor];
    self.cursor += sizeof(value);
    return value;
}

#pragma mark -

- (BOOL)readZero:(NSUInteger)length
{
    NSData *_Nullable subdata = [self readBytes:length];
    if (!subdata) {
        return NO;
    }
    uint8_t bytes[length];
    [subdata getBytes:bytes range:NSMakeRange(0, length)];
    for (int i = 0; i < length; i++) {
        if (bytes[i] != 0) {
            return NO;
        }
    }
    return YES;
}

- (nullable NSData *)readBytes:(NSUInteger)length
{
    NSUInteger index = self.cursor;
    if (index + length > self.data.length) {
        self.hasError = YES;
        return nil;
    }
    NSData *_Nullable subdata = [self.data subdataWithRange:NSMakeRange(index, length)];
    self.cursor += length;
    return subdata;
}

@end

NS_ASSUME_NONNULL_END
