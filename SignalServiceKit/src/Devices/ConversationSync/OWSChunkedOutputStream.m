//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSChunkedOutputStream.h"
#import <SignalCoreKit/NSData+OWS.h>

NS_ASSUME_NONNULL_BEGIN

NSErrorDomain const OWSChunkedOutputStreamErrorDomain = @"OWSChunkedOutputStreamErrorDomain";

@interface OWSChunkedOutputStream ()

@property (nonatomic, readonly) NSOutputStream *outputStream;

@end

#pragma mark -

@implementation OWSChunkedOutputStream

- (instancetype)initWithOutputStream:(NSOutputStream *)outputStream
{
    self = [super init];
    if (self) {
        OWSAssertDebug(outputStream);
        _outputStream = outputStream;
    }
    return self;
}

- (BOOL)writeByte:(uint8_t)value error:(NSError **)error
{
    NSInteger written = [self.outputStream write:&value maxLength:sizeof(value)];
    if (written != sizeof(value)) {
        if (error != NULL) {
            *error = buildWriteError();
        }
        return NO;
    }
    return YES;
}

- (BOOL)writeData:(NSData *)value error:(NSError **)error
{
    OWSAssertDebug(value);

    if (value.length < 1) {
        return YES;
    }

    while (YES) {
        NSInteger signed_written = [self.outputStream write:value.bytes maxLength:value.length];
        if (signed_written < 1) {
            if (error != NULL) {
                *error = buildWriteError();
            }
            return NO;
        }
        NSUInteger unsigned_written = (NSUInteger)signed_written;
        if (unsigned_written < value.length) {
            value = [value subdataWithRange:NSMakeRange(unsigned_written, value.length - unsigned_written)];
        } else {
            return YES;
        }
    }
    return YES;
}

- (BOOL)writeVariableLengthUInt32:(UInt32)value error:(NSError **)error
{
    while (YES) {
        if (value <= 0x7F) {
            return [self writeByte:(uint8_t)value error:error];
        } else {
            if (![self writeByte:((value & 0x7F) | 0x80) error:error]) {
                return NO;
            }
            value >>= 7;
        }
    }
}

static NSError *buildWriteError(void)
{
    return [NSError errorWithDomain:OWSChunkedOutputStreamErrorDomain
                               code:OWSChunkedOutputStreamErrorWriteFailed
                           userInfo:nil];
}

@end

NS_ASSUME_NONNULL_END
