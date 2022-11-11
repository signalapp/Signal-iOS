//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSChunkedOutputStream.h"
#import <SignalCoreKit/NSData+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSChunkedOutputStream ()

@property (nonatomic, readonly) NSOutputStream *outputStream;
@property (nonatomic) BOOL hasError;

@end

#pragma mark -

@implementation OWSChunkedOutputStream

- (instancetype)initWithOutputStream:(NSOutputStream *)outputStream
{
    if (self = [super init]) {
        OWSAssertDebug(outputStream);
        _outputStream = outputStream;
    }

    return self;
}

- (BOOL)writeByte:(uint8_t)value
{
    NSInteger written = [self.outputStream write:&value maxLength:sizeof(value)];
    if (written != sizeof(value)) {
        OWSFailDebug(@"could not write to output stream.");
        self.hasError = YES;
        return NO;
    }
    return YES;
}

- (BOOL)writeData:(NSData *)data
{
    OWSAssertDebug(data);

    if (data.length < 1) {
        return YES;
    }

    while (YES) {
        NSInteger signed_written = [self.outputStream write:data.bytes maxLength:data.length];
        if (signed_written < 1) {
            OWSFailDebug(@"could not write to output stream.");
            self.hasError = YES;
            return NO;
        }
        NSUInteger unsigned_written = (NSUInteger)signed_written;
        if (unsigned_written < data.length) {
            data = [data subdataWithRange:NSMakeRange(unsigned_written, data.length - unsigned_written)];
        } else {
            return YES;
        }
    }
    return YES;
}

- (BOOL)writeVariableLengthUInt32:(UInt32)value
{
    while (YES) {
        if (value <= 0x7F) {
            return [self writeByte:(uint8_t)value];
        } else {
            if (![self writeByte:((value & 0x7F) | 0x80)]) {
                return NO;
            }
            value >>= 7;
        }
    }
}

@end

NS_ASSUME_NONNULL_END
