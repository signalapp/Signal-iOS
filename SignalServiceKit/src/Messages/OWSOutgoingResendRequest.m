//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingResendRequest.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingResendRequest

- (instancetype)initWithFailedEnvelope:(SSKProtoEnvelope *)envelope
                            cipherType:(uint32_t)cipherType
                           transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(transaction);

    SignalServiceAddress *sender = [[SignalServiceAddress alloc] initWithUuidString:envelope.sourceUuid];
    if (!sender.isValid) {
        OWSFailDebug(@"Invalid UUID");
        return nil;
    }
    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:sender transaction:transaction];
    TSOutgoingMessageBuilder *builder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];

    self = [super initOutgoingMessageWithBuilder:builder];
    if (self) {
        _originalMessageBytes = envelope.content;
        _cipherType = cipherType;
        _originalMessageTimestamp = envelope.timestamp;
        _senderDeviceId = envelope.sourceDevice;
    }
    return self;
}

- (nullable NSData *)buildPlainTextData:(nullable SignalServiceAddress *)address
                                 thread:(TSThread *)thread
                            transaction:(SDSAnyReadTransaction *)transaction
{
    NSData *decryptionErrorData = [self buildDecryptionError];
    if (!decryptionErrorData) {
        OWSFailDebug(@"");
        return nil;
    }

    SSKProtoContentBuilder *builder = [SSKProtoContent builder];
    builder.decryptionErrorMessage = decryptionErrorData;

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

@end

NS_ASSUME_NONNULL_END
