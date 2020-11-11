#import "ClosedGroupCiphertextMessage.h"
#import "AxolotlExceptions.h"
#import <SignalCoreKit/OWSAsserts.h>
#import <SessionProtocolKit/SessionProtocolKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ClosedGroupCiphertextMessage

- (instancetype)init_throws_withIVAndCiphertext:(NSData *)ivAndCiphertext senderPublicKey:(NSData *)senderPublicKey keyIndex:(uint32_t)keyIndex
{
    if (self = [super init]) {
        _ivAndCiphertext = ivAndCiphertext;
        _senderPublicKey = senderPublicKey;
        _keyIndex = keyIndex;

        SPKProtoClosedGroupCiphertextMessageBuilder *builder = [SPKProtoClosedGroupCiphertextMessage builderWithCiphertext:ivAndCiphertext
                                                                                                           senderPublicKey:senderPublicKey
                                                                                                                  keyIndex:keyIndex];

        NSError *error;
        NSData *_Nullable serialized = [builder buildSerializedDataAndReturnError:&error];
        if (serialized == nil || error != nil) {
            OWSFailDebug(@"Couldn't serialize proto due to error: %@.", error);
            OWSRaiseException(InvalidMessageException, @"Couldn't serialize proto.");
        }
        
        _serialized = serialized;
    }

    return self;
}

- (instancetype)init_throws_withData:(NSData *)serialized
{
    if (self = [super init]) {
        NSError *error;
        SPKProtoClosedGroupCiphertextMessage *_Nullable ciphertextMessage = [SPKProtoClosedGroupCiphertextMessage parseData:serialized error:&error];
        if (ciphertextMessage == nil || error != nil) {
            OWSFailDebug(@"Couldn't parse proto due to error: %@.", error);
            OWSRaiseException(InvalidMessageException, @"Couldn't parse proto.");
        }

        _serialized = serialized;
        _ivAndCiphertext = ciphertextMessage.ciphertext;
        _senderPublicKey = ciphertextMessage.senderPublicKey;
        _keyIndex = ciphertextMessage.keyIndex;
    }

    return self;
}

- (CipherMessageType)cipherMessageType
{
    return CipherMessageType_ClosedGroupCiphertext;
}

@end

NS_ASSUME_NONNULL_END
