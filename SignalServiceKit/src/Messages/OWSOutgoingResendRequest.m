//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingResendRequest.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingResendRequest ()
@property (strong, nonatomic, readonly) NSData *decryptionErrorData;
@end

@implementation OWSOutgoingResendRequest

- (nullable instancetype)initWithFailedEnvelope:(SSKProtoEnvelope *)envelope
                                     cipherType:(uint8_t)cipherType
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
    self = [super initOutgoingMessageWithBuilder:builder];
    if (self) {
        _decryptionErrorData = errorData;
    }
    return self;
}

- (nullable NSData *)buildPlainTextData:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoContentBuilder *builder = [SSKProtoContent builder];
    builder.decryptionErrorMessage = self.decryptionErrorData;

    NSError *error;
    NSData *_Nullable data = [builder buildSerializedDataAndReturnError:&error];
    if (error || !data) {
        OWSFailDebug(@"could not serialize protobuf: %@", error);
        return nil;
    }
    return data;
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

@end

NS_ASSUME_NONNULL_END
