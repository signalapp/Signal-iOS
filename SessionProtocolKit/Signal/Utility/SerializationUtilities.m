//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SerializationUtilities.h"
#import <CommonCrypto/CommonCrypto.h>
#import <SessionProtocolKit/OWSAsserts.h>

NS_ASSUME_NONNULL_BEGIN

@implementation SerializationUtilities

+ (int)highBitsToIntFromByte:(Byte)byte
{
    return (byte & 0xFF) >> 4;
}

+ (int)lowBitsToIntFromByte:(Byte)byte
{
    return (byte & 0xF);
}

+ (Byte)intsToByteHigh:(int)highValue low:(int)lowValue
{
    return (Byte)((highValue << 4 | lowValue) & 0xFF);
}

+ (NSData *)throws_macWithVersion:(int)version
                      identityKey:(NSData *)senderIdentityKey
              receiverIdentityKey:(NSData *)receiverIdentityKey
                           macKey:(NSData *)macKey
                       serialized:(NSData *)serialized
{
    if (!macKey) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Missing macKey." userInfo:nil];
    }
    if (macKey.length >= SIZE_MAX) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Oversize macKey." userInfo:nil];
    }
    if (!senderIdentityKey) {
        @throw
            [NSException exceptionWithName:NSInvalidArgumentException reason:@"Missing senderIdentityKey" userInfo:nil];
    }
    if (senderIdentityKey.length >= SIZE_MAX) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Oversize senderIdentityKey"
                                     userInfo:nil];
    }
    if (!receiverIdentityKey) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Missing receiverIdentityKey"
                                     userInfo:nil];
    }
    if (receiverIdentityKey.length >= SIZE_MAX) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Oversize receiverIdentityKey"
                                     userInfo:nil];
    }
    if (!serialized) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Missing serialized." userInfo:nil];
    }
    if (serialized.length >= SIZE_MAX) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Oversize serialized." userInfo:nil];
    }

    NSMutableData *_Nullable bufferData = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    OWSAssert(bufferData);

    CCHmacContext context;
    CCHmacInit(&context, kCCHmacAlgSHA256, [macKey bytes], [macKey length]);
    CCHmacUpdate(&context, [senderIdentityKey bytes], [senderIdentityKey length]);
    CCHmacUpdate(&context, [receiverIdentityKey bytes], [receiverIdentityKey length]);
    CCHmacUpdate(&context, [serialized bytes], [serialized length]);
    CCHmacFinal(&context, bufferData.mutableBytes);

    return [bufferData subdataWithRange:NSMakeRange(0, MAC_LENGTH)];
}

@end

NS_ASSUME_NONNULL_END
