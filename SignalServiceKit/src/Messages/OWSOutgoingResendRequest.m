//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingResendRequest.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingResendRequest ()
@property (strong, nonatomic, readonly) NSData *decryptionErrorData;
@property (strong, nonatomic, nullable, readonly) NSData *failedEnvelopeGroupId;
@end

@implementation OWSOutgoingResendRequest

- (nullable instancetype)initWithFailedEnvelope:(SSKProtoEnvelope *)envelope
                                     cipherType:(uint8_t)cipherType
                          failedEnvelopeGroupId:(nullable NSData *)failedEnvelopeGroupId
                                    transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(envelope.content);
    OWSAssertDebug(transaction);

    SignalServiceAddress *sender = [[SignalServiceAddress alloc] initWithUuidString:envelope.sourceUuid];
    if (!sender.isValid) {
        OWSFailDebug(@"Invalid UUID");
        return nil;
    }
    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:sender transaction:transaction];
    NSData *errorData = [self buildDecryptionErrorFrom:envelope.content
                                                  type:cipherType
                              originalMessageTimestamp:envelope.timestamp
                                        senderDeviceId:envelope.sourceDevice];
    if (!errorData) {
        OWSFailDebug(@"Couldn't build DecryptionErrorMessage");
        return nil;
    }

    TSOutgoingMessageBuilder *builder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:builder transaction:transaction];
    if (self) {
        _decryptionErrorData = errorData;
        _failedEnvelopeGroupId = failedEnvelopeGroupId;
    }
    return self;
}

- (EncryptionStyle)encryptionStyle
{
    return EncryptionStylePlaintext;
}

- (BOOL)isUrgent
{
    return NO;
}

- (BOOL)shouldRecordSendLog
{
    /// We have to return NO since our preferred style is Plaintext. If we returned YES, a future resend response would
    /// encrypt since MessageSender only deals with plaintext as Data. This is fine since its contentHint is `default`
    /// anyway.
    /// TODO: Maybe we should explore having a first class type to represent the plaintext message content mid-send?
    /// That way we don't need to call back to the original TSOutgoingMessage for questions about the plaintext. This
    /// makes sense in a world where the TSOutgoingMessage is divorced from the constructed plaintext because of the
    /// MessageSendLog and OWSOutgoingResendResponse
    return NO;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintDefault;
}

- (nullable NSData *)envelopeGroupIdWithTransaction:(__unused SDSAnyReadTransaction *)transaction
{
    return self.failedEnvelopeGroupId;
}

@end

NS_ASSUME_NONNULL_END
