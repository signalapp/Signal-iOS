//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "PreKeyWhisperMessage.h"
#import "AxolotlExceptions.h"
#import "Constants.h"
#import "SerializationUtilities.h"
#import <SessionProtocolKit/SessionProtocolKit-Swift.h>
#import <SignalCoreKit/SCKExceptionWrapper.h>
#import <SignalCoreKit/OWSAsserts.h>

NS_ASSUME_NONNULL_BEGIN

@interface PreKeyWhisperMessage ()

@property (nonatomic, readwrite) NSData *identityKey;
@property (nonatomic, readwrite) NSData *baseKey;
@property (nonatomic, readwrite) NSData *serialized;

@end

#pragma mark -

@implementation PreKeyWhisperMessage

- (instancetype)init_throws_withWhisperMessage:(WhisperMessage *)whisperMessage
                                registrationId:(int)registrationId
                                      prekeyId:(int)prekeyId
                                signedPrekeyId:(int)signedPrekeyId
                                       baseKey:(NSData *)baseKey
                                   identityKey:(NSData *)identityKey
{
    OWSAssert(whisperMessage);
    OWSAssert(baseKey);
    OWSAssert(identityKey);

    if (self = [super init]) {
        _registrationId = registrationId;
        _version = whisperMessage.version;
        _prekeyID = prekeyId;
        _signedPrekeyId = signedPrekeyId;
        _baseKey = baseKey;
        _identityKey = identityKey;
        _message = whisperMessage;

        SPKProtoTSProtoPreKeyWhisperMessageBuilder *messageBuilder = [SPKProtoTSProtoPreKeyWhisperMessage builderWithSignedPreKeyID:signedPrekeyId
                                                                                                                            baseKey:baseKey
                                                                                                                        identityKey:identityKey
                                                                                                                            message:whisperMessage.serialized];
        [messageBuilder setRegistrationID:registrationId];

        if (prekeyId != -1) {
            [messageBuilder setPreKeyID:prekeyId];
        }

        Byte versionByte = [SerializationUtilities intsToByteHigh:_version low:CURRENT_VERSION];
        NSMutableData *serialized = [NSMutableData dataWithBytes:&versionByte length:1];

        NSError *error;
        NSData *_Nullable messageData = [messageBuilder buildSerializedDataAndReturnError:&error];
        if (!messageData || error) {
            OWSFailDebug(@"Could not serialize proto: %@.", error);
            OWSRaiseException(InvalidMessageException, @"Could not serialize proto.");
        }
        [serialized appendData:messageData];

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
        if (serialized.length < 1) {
            OWSFailDebug(@"Empty data");
            OWSRaiseException(InvalidMessageException, @"Empty data");
        }

        Byte version;
        [serialized getBytes:&version length:1];
        _version = [SerializationUtilities highBitsToIntFromByte:version];

        if (_version > CURRENT_VERSION && _version < MINIMUM_SUPPORTED_VERSION) {
            @throw [NSException exceptionWithName:InvalidVersionException
                                           reason:@"Unknown version"
                                         userInfo:@{ @"version" : [NSNumber numberWithInt:_version] }];
        }

        NSUInteger messageDataLength;
        ows_sub_overflow(serialized.length, 1, &messageDataLength);
        NSData *messageData = [serialized subdataWithRange:NSMakeRange(1, messageDataLength)];

        NSError *error;
        SPKProtoTSProtoPreKeyWhisperMessage *_Nullable preKeyWhisperMessage =
            [SPKProtoTSProtoPreKeyWhisperMessage parseData:messageData error:&error];
        if (!preKeyWhisperMessage || error) {
            OWSFailDebug(@"Could not parse proto: %@.", error);
            OWSRaiseException(InvalidMessageException, @"Could not parse proto.");
        }

        _serialized = serialized;
        _registrationId = preKeyWhisperMessage.registrationID;

        // This method is called when decrypting a received PreKeyMessage, but to be symmetrical with
        // encrypting a PreKeyWhisperMessage before sending, we use "-1" to indicate *no* unsigned prekey was
        // included.
        _prekeyID = preKeyWhisperMessage.hasPreKeyID ? preKeyWhisperMessage.preKeyID : -1;
        _signedPrekeyId = preKeyWhisperMessage.signedPreKeyID;
        _baseKey = preKeyWhisperMessage.baseKey;
        _identityKey = preKeyWhisperMessage.identityKey;
        _message = [[WhisperMessage alloc] init_throws_withData:preKeyWhisperMessage.message];
    }

    return self;
}

- (CipherMessageType)cipherMessageType {
    return CipherMessageType_Prekey;
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
