//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "NSData+messagePadding.h"

@implementation NSData (messagePadding)

- (NSData *)removePadding
{
    unsigned long paddingStart = self.length;

    Byte data[self.length];
    [self getBytes:data length:self.length];

    for (long i = (long)self.length - 1; i >= 0; i--) {
        if (data[i] == (Byte)0x80) {
            paddingStart = (unsigned long)i;
            break;
        } else if (data[i] != (Byte)0x00) {
            OWSLogWarn(@"Failed to remove padding, returning unstripped padding");
            return self;
        }
    }

    return [self subdataWithRange:NSMakeRange(0, paddingStart)];
}


- (NSData *)paddedMessageBody
{
    // From
    // https://github.com/signalapp/Signal-Android/blob/c4bc2162f23e0fd6bc25941af8fb7454d91a4a35/libsignal/service/src/main/java/org/whispersystems/signalservice/internal/push/PushTransportDetails.java#L36-L45
    // NOTE: This is dumb.  We have our own padding scheme, but so does the cipher.
    // The +1 -1 here is to make sure the Cipher has room to add one padding byte,
    // otherwise it'll add a full 16 extra bytes.

    NSUInteger paddedMessageLength = [self paddedMessageLength:(self.length + 1)] - 1;
    NSMutableData *paddedMessage = [NSMutableData dataWithLength:paddedMessageLength];

    Byte paddingByte = 0x80;

    [paddedMessage replaceBytesInRange:NSMakeRange(0, self.length) withBytes:[self bytes]];
    [paddedMessage replaceBytesInRange:NSMakeRange(self.length, 1) withBytes:&paddingByte];

    return paddedMessage;
}

- (NSUInteger)paddedMessageLength:(NSUInteger)messageLength
{
    NSUInteger messageLengthWithTerminator = messageLength + 1;
    NSUInteger messagePartCount = messageLengthWithTerminator / 160;

    if (messageLengthWithTerminator % 160 != 0) {
        messagePartCount++;
    }

    return messagePartCount * 160;
}

@end
