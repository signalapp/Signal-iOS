//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSChunkedOutputStream.h"
#import "NSData+OWS.h"

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
        NSInteger written = [self.outputStream write:data.bytes maxLength:data.length];
        if (written < 1) {
            OWSFailDebug(@"could not write to output stream.");
            self.hasError = YES;
            return NO;
        }
        if (written < data.length) {
            data = [data subdataWithRange:NSMakeRange(written, data.length - written)];
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
            return [self writeByte:value];
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
