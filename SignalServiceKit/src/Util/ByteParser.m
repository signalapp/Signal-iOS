//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

#pragma mark - UInt16

- (uint16_t)uint16AtIndex:(NSUInteger)index
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

- (uint16_t)nextUInt16
{
    uint16_t value = [self uint16AtIndex:self.cursor];
    self.cursor += sizeof(value);
    return value;
}

#pragma mark - UInt32

- (uint32_t)uint32AtIndex:(NSUInteger)index
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

- (uint32_t)nextUInt32
{
    uint32_t value = [self uint32AtIndex:self.cursor];
    self.cursor += sizeof(value);
    return value;
}

#pragma mark - UInt64

- (uint64_t)uint64AtIndex:(NSUInteger)index
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

- (uint64_t)nextUInt64
{
    uint64_t value = [self uint64AtIndex:self.cursor];
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
