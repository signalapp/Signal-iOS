//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "WhisperMessage.h"
#import "AxolotlExceptions.h"
#import "Constants.h"
#import "NSData+keyVersionByte.h"
#import "SerializationUtilities.h"
#import <SessionProtocolKit/OWSAsserts.h>
#import <SessionProtocolKit/SessionProtocolKit-Swift.h>
#import <SessionProtocolKit/NSData+OWS.h>
#import <SessionProtocolKit/SCKExceptionWrapper.h>
#import <SessionProtocolKit/SessionProtocolKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#define VERSION_LENGTH 1

@implementation WhisperMessage

- (instancetype)init_throws_withVersion:(int)version
                                 macKey:(NSData *)macKey
                       senderRatchetKey:(NSData *)senderRatchetKey
                                counter:(int)counter
                        previousCounter:(int)previousCounter
                             cipherText:(NSData *)cipherText
                      senderIdentityKey:(NSData *)senderIdentityKey
                    receiverIdentityKey:(NSData *)receiverIdentityKey
{
    OWSAssert(macKey);
    OWSAssert(senderRatchetKey);
    OWSAssert(cipherText);
    OWSAssert(cipherText);
    OWSAssert(senderIdentityKey);
    OWSAssert(receiverIdentityKey);

    if (self = [super init]) {
        Byte versionByte = [SerializationUtilities intsToByteHigh:version low:CURRENT_VERSION];
        NSMutableData *serialized = [NSMutableData dataWithBytes:&versionByte length:1];

        SPKProtoTSProtoWhisperMessageBuilder *messageBuilder = [SPKProtoTSProtoWhisperMessage builderWithRatchetKey:senderRatchetKey
                                                                                                            counter:counter
                                                                                                         ciphertext:cipherText];
        [messageBuilder setPreviousCounter:previousCounter];
        NSError *error;
        NSData *_Nullable messageData = [messageBuilder buildSerializedDataAndReturnError:&error];
        if (!messageData || error) {
            OWSFailDebug(@"Could not serialize proto: %@.", error);
            OWSRaiseException(InvalidMessageException, @"Could not serialize proto.");
        }
        [serialized appendData:messageData];

        NSData *mac = [SerializationUtilities throws_macWithVersion:version
                                                        identityKey:[senderIdentityKey prependKeyType]
                                                receiverIdentityKey:[receiverIdentityKey prependKeyType]
                                                             macKey:macKey
                                                         serialized:serialized];

        [serialized appendData:mac];

        _version = version;
        _senderRatchetKey = senderRatchetKey;
        _previousCounter = previousCounter;
        _counter = counter;
        _cipherText = cipherText;
        _serialized = [serialized copy];
    }

    return self;
}

- (nullable instancetype)initWithData:(NSData *)serialized error:(NSError **)outError
{
    @try {
        self = [self init_throws_withData:serialized];
        return self;
    } @catch (NSException *exception) {
        *outError = SCKExceptionWrapperErrorMake(exception);
        return nil;
    }
}

- (instancetype)init_throws_withData:(NSData *)serialized
{
    if (self = [super init]) {
        if (serialized.length <= (VERSION_LENGTH + MAC_LENGTH)) {
            @throw [NSException exceptionWithName:InvalidMessageException
                                           reason:@"Message size is too short to have content"
                                         userInfo:@{}];
        }

        Byte version;
        [serialized getBytes:&version length:VERSION_LENGTH];

        NSUInteger messageAndMacLength;
        ows_sub_overflow(serialized.length, VERSION_LENGTH, &messageAndMacLength);
        NSData *messageAndMac = [serialized subdataWithRange:NSMakeRange(VERSION_LENGTH, messageAndMacLength)];

        NSUInteger messageLength;
        ows_sub_overflow(messageAndMac.length, MAC_LENGTH, &messageLength);
        NSData *messageData = [messageAndMac subdataWithRange:NSMakeRange(0, messageLength)];

        if ([SerializationUtilities highBitsToIntFromByte:version] < MINIMUM_SUPPORTED_VERSION) {
            @throw [NSException
                exceptionWithName:LegacyMessageException
                           reason:@"Message was sent with an unsupported version of the TextSecure protocol."
                         userInfo:@{}];
        }

        if ([SerializationUtilities highBitsToIntFromByte:version] > CURRENT_VERSION) {
            @throw [NSException exceptionWithName:InvalidMessageException
                                           reason:@"Unknown Version"
                                         userInfo:@{
                                             @"Version" : [NSNumber
                                                 numberWithChar:[SerializationUtilities highBitsToIntFromByte:version]]
                                         }];
        }

        NSError *error;
        SPKProtoTSProtoWhisperMessage *_Nullable whisperMessage =
            [SPKProtoTSProtoWhisperMessage parseData:messageData error:&error];
        if (!whisperMessage || error) {
            OWSFailDebug(@"Could not parse proto: %@.", error);
            OWSRaiseException(InvalidMessageException, @"Could not parse proto.");
        }

        _serialized = serialized;
        _senderRatchetKey = [whisperMessage.ratchetKey throws_removeKeyType];
        _version = [SerializationUtilities highBitsToIntFromByte:version];
        _counter = whisperMessage.counter;
        _previousCounter = whisperMessage.previousCounter;
        _cipherText = whisperMessage.ciphertext;
    }

    return self;
}

- (void)throws_verifyMacWithVersion:(int)messageVersion
                  senderIdentityKey:(NSData *)senderIdentityKey
                receiverIdentityKey:(NSData *)receiverIdentityKey
                             macKey:(NSData *)macKey
{
    OWSAssert(senderIdentityKey);
    OWSAssert(receiverIdentityKey);
    OWSAssert(macKey);

    OWSDataParser *dataParser = [[OWSDataParser alloc] initWithData:self.serialized];
    NSError *error;

    NSUInteger messageLength;
    if (__builtin_sub_overflow(self.serialized.length, MAC_LENGTH, &messageLength)) {
        OWSFailDebug(@"Data too short");
        OWSRaiseException(InvalidMessageException, @"Data too short");
    }
    NSData *_Nullable data = [dataParser nextDataWithLength:messageLength
                                                       name:@"message data"
                                                      error:&error];
    if (!data || error) {
        OWSFailDebug(@"Could not parse data: %@.", error);
        OWSRaiseException(InvalidMessageException, @"Could not parse data.");
    }
    NSData *_Nullable theirMac = [dataParser nextDataWithLength:MAC_LENGTH
                                                           name:@"mac data"
                                                          error:&error];
    if (!theirMac || error) {
        OWSFailDebug(@"Could not parse their mac: %@.", error);
        OWSRaiseException(InvalidMessageException, @"Could not parse their mac.");
    }

    NSData *ourMac = [SerializationUtilities throws_macWithVersion:messageVersion
                                                       identityKey:[senderIdentityKey prependKeyType]
                                               receiverIdentityKey:[receiverIdentityKey prependKeyType]
                                                            macKey:macKey
                                                        serialized:data];

    if (![theirMac ows_constantTimeIsEqualToData:ourMac]) {
        OWSFailDebug(@"Bad Mac! Their Mac: %@ Our Mac: %@", theirMac, ourMac);
        OWSRaiseException(InvalidMessageException, @"Bad Mac!");
    }
}

- (CipherMessageType)cipherMessageType {
    return CipherMessageType_Whisper;
}

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end

NS_ASSUME_NONNULL_END
